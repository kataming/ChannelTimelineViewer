import XCTest

/// App Store 提出用スクリーンショットを撮るための UI テスト。
///
/// 通常の CI では実行しない（実 API とネットワークを使い、時間もかかるため）。
/// `Screenshots` スキーム経由で `.github/workflows/ios-screenshots.yml` から実行される。
///
/// 撮影対象は docs/screenshot-production-guide.md の「推奨カット」に対応:
///   01 ホーム（お気に入り＋進捗）… 取得後に戻ってきて撮るので、お気に入りが入った状態になる
///   02 動画一覧（進捗バー＋次に見る）
///   03 フィルター（未視聴のみ）
///   04 再生画面（公式プレイヤー＋メモ）
///   05 進捗（視聴済みチェックが並んだ一覧）
///   06 このアプリについて（注意事項）
///
/// **多言語対応**: `SCREENSHOT_LANGUAGE`（例 `ja` / `en` / `zh-Hans`）でアプリの表示言語を切り替えて撮る。
/// 画面の要素は「表示されている文字」で探すため、テスト側も同じ言語の文言を使う必要がある。
/// そこで UITests ターゲットにもアプリと同じ `Localization/` を含め、`L(_:)` で同じキーから引く
/// （テストに日本語の文字列を直接書かない＝言語を足しても壊れない）。
///
/// 撮った画像は XCTAttachment として .xcresult に入る。ワークフロー側で
/// `xcrun xcresulttool export attachments` により PNG として取り出す。
///
/// 方針: 1カット撮れなかっただけで全部を失うと再実行コストが高いので、
/// 致命的でない失敗では止めず、撮れたところまで残す。
final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    /// 撮影対象チャンネル。ワークフローの入力から TEST_RUNNER_ 経由で渡る。
    private var channelURL: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_CHANNEL_URL"]
            ?? "https://www.youtube.com/@NASA"
    }

    /// 進捗バーに意味のある数字を出すため、何本を視聴済みにするか。
    private var watchedCount: Int {
        Int(ProcessInfo.processInfo.environment["SCREENSHOT_WATCHED_COUNT"] ?? "") ?? 3
    }

    /// 撮影する言語（アプリの表示言語）。未指定なら英語。
    private var language: String {
        let value = ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] ?? "en"
        return value.isEmpty ? "en" : value
    }

    /// 言語に対応する地域（日付や数字の書式を自然にするため）。
    private var locale: String {
        switch language {
        case "ja": return "ja_JP"
        case "zh-Hans": return "zh_CN"
        case "es": return "es_ES"
        case "de": return "de_DE"
        case "fr": return "fr_FR"
        case "ko": return "ko_KR"
        default: return "en_US"
        }
    }

    /// 撮影言語の .lproj。テスト側の文言もアプリと同じ翻訳から引く。
    private lazy var strings: Bundle = {
        let testBundle = Bundle(for: type(of: self))
        if let path = testBundle.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return testBundle
    }()

    /// 翻訳を引く。見つからなければキー名をそのまま返す（撮影は続ける）。
    private func L(_ key: String) -> String {
        strings.localizedString(forKey: key, value: key, table: nil)
    }

    /// メモ欄に入れるサンプル文（画面写真用。アプリの文言ではないのでここに置く）。
    private var sampleMemo: String {
        switch language {
        case "ja": return "導入回。用語の定義をここまでで押さえる。次回から実践パート。"
        case "zh-Hans": return "第一讲。先掌握术语定义，下一讲开始实践部分。"
        case "es": return "Clase 1. Repasar las definiciones; la práctica empieza en la siguiente."
        case "de": return "Folge 1: Begriffe bis hier festhalten. Praxisteil ab der nächsten Folge."
        case "fr": return "Séance 1 : retenir les définitions. La pratique commence ensuite."
        case "ko": return "1회차. 용어 정의까지 정리. 다음 회차부터 실습."
        default: return "Episode 1 — lock in the definitions. Hands-on starts next time."
        }
    }

    override func setUpWithError() throws {
        // 1カットの失敗で以降を諦めない
        continueAfterFailure = true
        print("[screenshots] channel=\(channelURL) watchedCount=\(watchedCount) language=\(language)")
        app = XCUIApplication()
        // 表示言語をアプリ側にも明示する（-testLanguage に頼らず、テストと確実に揃える）。
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
    }

    // MARK: - ヘルパー

    /// 画面を撮って .xcresult に添付する。名前の先頭の通し番号で並び順を保つ。
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)  // アニメーション・非同期描画の収束待ち
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 戻るボタン（ナビゲーションバーの先頭ボタン）を押す。無ければ何もしない。
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable {
            back.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    /// ルート（チャンネル入力画面）まで戻る。
    private func returnToRoot() {
        var attempts = 0
        while !app.buttons[L("input.fetch")].exists && attempts < 6 {
            goBack()
            attempts += 1
        }
    }

    /// いま動画一覧にいることを確かめる。ホームまで戻ってしまっていたら開き直す。
    private func ensureVideoList() {
        if app.buttons[L("list.menu.a11y")].exists { return }
        guard app.buttons[L("input.fetch")].exists else { return }
        // ホームの「最近使ったチャンネル」から入り直す（0=URL欄, 1=取得ボタン, 2=チャンネル行）
        let favorite = app.cells.element(boundBy: 2)
        guard favorite.exists && favorite.isHittable else { return }
        favorite.tap()
        _ = app.buttons[L("list.menu.a11y")].waitForExistence(timeout: 120)
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// 一覧の指定行を開いて、再生画面が出るまで待つ。開けなければ false。
    @discardableResult
    private func openVideoRow(_ index: Int) -> Bool {
        ensureVideoList()
        let row = app.cells.element(boundBy: index)
        guard row.exists && row.isHittable else { return false }
        row.tap()
        return waitForPlayerScreen()
    }

    /// 再生画面が使える状態になるまで待つ（移動ボタンの「次へ」が出れば描画済み）。
    @discardableResult
    private func waitForPlayerScreen(timeout: TimeInterval = 40) -> Bool {
        app.buttons[L("player.nav.next")].waitForExistence(timeout: timeout)
    }

    /// 再生画面の「…」メニューから、いまの動画を視聴済みにする。
    private func markCurrentVideoWatched() {
        let more = app.buttons[L("player.menu.a11y")]
        guard more.waitForExistence(timeout: 10), more.isHittable else { return }
        more.tap()
        Thread.sleep(forTimeInterval: 0.6)

        let mark = app.buttons[L("player.menu.markWatched")]
        if mark.waitForExistence(timeout: 5) {
            mark.tap()
        } else {
            // すでに視聴済みならメニューを閉じるだけ（撮影は続ける）
            app.tap()
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    // MARK: - 撮影本体

    func testCaptureAppStoreScreenshots() throws {
        // --- チャンネルURLを入力して取得（Return で onSubmit が走る） ---
        let urlField = app.textFields.firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 30), "チャンネルURL入力欄が出ない")
        urlField.tap()
        urlField.typeText(channelURL)
        capture("00-input-typed")   // 予備。うまく撮れていれば使わない
        urlField.typeText("\n")

        // 一覧が出るまで待つ（チャンネル解決 + ページネーションで時間がかかる）。
        //
        // ここで進捗の文字を待つと、一覧の行数が多い時に
        // 「Failed to get matching snapshots: Timed out while evaluating UI query」で落ちる。
        // ナビゲーションバーは要素数が少なく安価に評価できるので、タイトルの変化で判定する。
        let navBar = app.navigationBars.firstMatch
        let changed = NSPredicate(format: "identifier != %@ AND identifier != ''", "Channel Timeline")
        let reached = expectation(for: changed, evaluatedWith: navBar, handler: nil)
        guard XCTWaiter().wait(for: [reached], timeout: 240) == .completed else {
            capture("ERROR-fetch-failed")
            XCTFail("動画一覧を取得できませんでした（APIキー/ネットワーク/チャンネルURLを確認）")
            return
        }
        Thread.sleep(forTimeInterval: 2.0)  // 一覧の描画待ち

        // --- 何本かを視聴済みにして、進捗バーに数字を出す ---
        markSomeVideosAsWatched()

        // --- 02 動画一覧（進捗バー＋次に見る） ---
        capture("02-video-list-progress")

        // --- 05 進捗（視聴済みチェックが並んだところ） ---
        app.swipeUp()
        capture("05-progress-watched")
        app.swipeDown()

        // --- 03 フィルター（未視聴のみ） ---
        captureFilteredList()

        // --- 04 再生画面（公式プレイヤー＋メモ） ---
        capturePlayerScreen()

        // --- 01 ホーム（お気に入りに追加された状態で撮る） ---
        returnToRoot()
        capture("01-home-favorites")

        // --- 06 このアプリについて ---
        captureAboutScreen()
    }

    /// 一覧の先頭から数本を開いて視聴済みにし、進捗を作る。
    private func markSomeVideosAsWatched() {
        for _ in 0..<max(0, watchedCount) {
            // 「次に見る／続きから」行は常に未視聴の先頭を開くので、繰り返すと順に進む
            guard openVideoRow(1) else { break }
            markCurrentVideoWatched()
            goBack()
        }
    }

    private func captureFilteredList() {
        let filterButton = app.buttons[L("list.menu.a11y")]
        guard filterButton.waitForExistence(timeout: 10) else { return }
        filterButton.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Menu 内の Picker は環境により button / other として出る
        let unwatchedButton = app.buttons[L("filter.unwatched")]
        if unwatchedButton.waitForExistence(timeout: 5) {
            unwatchedButton.tap()
        } else {
            let alt = app.otherElements[L("filter.unwatched")].firstMatch
            if alt.exists { alt.tap() } else { return }
        }
        capture("03-filter-unwatched")

        // 全件表示に戻す
        filterButton.tap()
        Thread.sleep(forTimeInterval: 0.8)
        let all = app.buttons[L("filter.all")]
        if all.waitForExistence(timeout: 5) { all.tap() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// 再生画面を撮る。
    ///
    /// メモを入力した直後はキーボードが出たままになりやすく（SwiftUI の TextEditor は
    /// 確実に閉じる手段が無い）、ストア用の画像として使えない。そこで
    /// 「入力 → 一度戻る → 開き直す」ことでキーボードの無い状態を作る。
    /// メモは videoId ごとに自動保存されるので、開き直しても内容は残る。
    private func capturePlayerScreen() {
        let rowIndex = 3  // 0,1 は進捗ヘッダー/次に見る行

        // 1回目: メモを入力するだけ。
        // 入力直後はキーボードが出たままで写真に使えないので、ここでは撮らずに戻る
        //（画面ごと閉じればキーボードも消える。メモは videoId ごとに自動保存される）。
        guard openVideoRow(rowIndex) else { return }
        let memo = app.textViews.firstMatch
        if memo.exists && memo.isHittable {
            memo.tap()
            memo.typeText(sampleMemo)
            Thread.sleep(forTimeInterval: 0.8)
        }
        goBack()

        // 2回目: キーボードの無い状態で、プレイヤーの読み込みを待って撮る
        guard openVideoRow(rowIndex) else {
            capture("ERROR-player-not-opened")
            return
        }
        Thread.sleep(forTimeInterval: 10)  // 埋め込みプレイヤーの読み込み待ち
        capture("04-player-with-memo")

        goBack()
    }

    private func captureAboutScreen() {
        let aboutButton = app.buttons[L("about.open.a11y")]
        guard aboutButton.waitForExistence(timeout: 10) else { return }
        aboutButton.tap()
        Thread.sleep(forTimeInterval: 1.2)
        capture("06-about-notice")
    }
}
