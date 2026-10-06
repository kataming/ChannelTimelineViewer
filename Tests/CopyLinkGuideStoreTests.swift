import XCTest
@testable import ChannelTimelineViewer

/// 「YouTube の共有から追加する」で、YouTube から戻ってきたときにコピーしたリンクを拾う処理のテスト。
///
/// 大事なのは「**むやみに中身を読まない**」こと（iOS 16 以降、読むとペーストの確認が出る）:
/// 案内から行っていない・何もコピーしていない・URL らしくない、のどれでも中身を読まない。
@MainActor
final class CopyLinkGuideStoreTests: XCTestCase {

    private final class FakePasteboard: CopyGuidePasteboard {
        var changeCount = 10
        var looksLikeURL = true
        var content: String?
        /// 「ペーストを許可しない」を押された（中身が読めない）。
        var denied = false
        private(set) var readCount = 0

        func containsProbableWebURL() async -> Bool { looksLikeURL }

        func readText() -> String? {
            readCount += 1
            return denied ? nil : content
        }

        /// YouTube で［コピー］した、の代わり。
        func copy(_ text: String, looksLikeURL: Bool = true) {
            content = text
            self.looksLikeURL = looksLikeURL
            changeCount += 1
        }
    }

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var pasteboard: FakePasteboard!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        suiteName = "CopyLinkGuideStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        pasteboard = FakePasteboard()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> CopyLinkGuideStore {
        CopyLinkGuideStore(defaults: defaults, pasteboard: pasteboard, now: { [unowned self] in self.clock })
    }

    func testDoesNothingUnlessStartedFromTheGuide() async {
        let store = makeStore()
        pasteboard.copy("https://youtu.be/dQw4w9WgXcQ")

        let outcome = await store.takeNewlyCopiedLink()

        XCTAssertEqual(outcome, .none)
        XCTAssertEqual(pasteboard.readCount, 0, "案内から行っていなければクリップボードを読まない")
    }

    func testOpensNewlyCopiedYouTubeLink() async {
        let store = makeStore()
        store.startAwaiting()
        XCTAssertTrue(store.isAwaiting)

        pasteboard.copy("https://youtu.be/dQw4w9WgXcQ?si=abc")
        let outcome = await store.takeNewlyCopiedLink()

        guard case .link(let link) = outcome else { return XCTFail("リンクを返すはず: \(outcome)") }
        XCTAssertTrue(link.contains("dQw4w9WgXcQ"))
        XCTAssertEqual(pasteboard.readCount, 1)
        XCTAssertFalse(store.isAwaiting, "開いたら待ち状態は終わる")

        // 同じコピーで二度は開かない。
        let again = await store.takeNewlyCopiedLink()
        XCTAssertEqual(again, .none)
        XCTAssertEqual(pasteboard.readCount, 1)
    }

    func testReturningWithoutCopyingKeepsWaitingAndDoesNotRead() async {
        let store = makeStore()
        pasteboard.copy("https://youtu.be/oldoldold00")   // 案内を開く前からあったコピー
        store.startAwaiting()

        let outcome = await store.takeNewlyCopiedLink()

        XCTAssertEqual(outcome, .none, "前からあったリンクは新しいコピーではない")
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertTrue(store.isAwaiting, "YouTube を見ただけで戻っても、待ち状態は続ける")

        // そのあと改めてコピーして戻れば開く。
        pasteboard.copy("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        let later = await store.takeNewlyCopiedLink()
        guard case .link = later else { return XCTFail("リンクを返すはず: \(later)") }
    }

    func testCopiedTextThatIsNotAURLIsNotRead() async {
        let store = makeStore()
        store.startAwaiting()
        pasteboard.copy("hello", looksLikeURL: false)

        let outcome = await store.takeNewlyCopiedLink()

        XCTAssertEqual(outcome, .notYouTube)
        XCTAssertEqual(pasteboard.readCount, 0, "URL らしくなければ中身を読まない（ペーストの確認を出さない）")
        // 同じコピーでは二度聞かない。
        let again = await store.takeNewlyCopiedLink()
        XCTAssertEqual(again, .none)
    }

    func testNonYouTubeURLIsReportedOnce() async {
        let store = makeStore()
        store.startAwaiting()
        pasteboard.copy("https://example.com/page")

        let outcome = await store.takeNewlyCopiedLink()
        XCTAssertEqual(outcome, .notYouTube)
        XCTAssertTrue(store.isAwaiting, "YouTube のリンクを待ち続ける")

        let again = await store.takeNewlyCopiedLink()
        XCTAssertEqual(again, .none)
        XCTAssertEqual(pasteboard.readCount, 1, "同じコピーを二度読まない")
    }

    func testExpiresAfterThirtyMinutes() async {
        let store = makeStore()
        store.startAwaiting()
        clock = clock.addingTimeInterval(CopyLinkGuideStore.awaitInterval + 1)
        pasteboard.copy("https://youtu.be/dQw4w9WgXcQ")

        let outcome = await store.takeNewlyCopiedLink()

        XCTAssertEqual(outcome, .none)
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertFalse(store.isAwaiting)
    }

    func testAwaitingSurvivesRelaunch() async {
        makeStore().startAwaiting()
        pasteboard.copy("https://youtu.be/dQw4w9WgXcQ")

        // YouTube にいるあいだにアプリが終了していても、次の起動で拾える。
        let relaunched = makeStore()
        let outcome = await relaunched.takeNewlyCopiedLink()
        guard case .link = outcome else { return XCTFail("リンクを返すはず: \(outcome)") }
    }

    /// 「ペーストを許可しない」を押されたら pasteDenied を返し、待ち続ける。［もう一度読み込む］で読める。
    func testPasteDeniedCanBeRetried() async {
        let store = makeStore()
        store.startAwaiting()
        pasteboard.copy("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        pasteboard.denied = true

        let outcome = await store.takeNewlyCopiedLink()
        XCTAssertEqual(outcome, .pasteDenied)
        XCTAssertTrue(store.isAwaiting)

        pasteboard.denied = false
        guard case .link = store.retryRead() else { return XCTFail("許可されたら読めるはず") }
        XCTAssertFalse(store.isAwaiting)
    }
}
