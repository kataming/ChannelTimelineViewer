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

    override func setUpWithError() throws {
        // 1カットの失敗で以降を諦めない
        continueAfterFailure = true
        // 入力が届いているかログで確認できるようにする（既定値に落ちていないか）
        print("[screenshots] channel=\(channelURL) watchedCount=\(watchedCount)")
        app = XCUIApplication()
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

    /// キーボードを閉じる。SwiftUI の Form / ScrollView には「完了」ツールバーが無いため、
    /// 環境によって効く方法が違う。どれも失敗扱いにはしない。
    private func dismissKeyboard() {
        guard app.keyboards.count > 0 else { return }

        // 1) ツールバーがあるなら使う
        let toolbarButton = app.toolbars.buttons.firstMatch
        if toolbarButton.exists {
            toolbarButton.tap()
            if app.keyboards.count == 0 { return }
        }

        // 2) スクロールビューを下に払う（interactive dismissal）
        let scroll = app.scrollViews.firstMatch
        if scroll.exists { scroll.swipeDown() } else { app.swipeDown() }
        if app.keyboards.count == 0 { return }

        // 3) ナビゲーションバーをタップ
        let navBar = app.navigationBars.firstMatch
        if navBar.exists {
            navBar.tap()
        }
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
        while !app.buttons["動画を取得"].exists && attempts < 6 {
            goBack()
            attempts += 1
        }
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
        // ここで app.staticTexts["進捗"] を待つと、一覧の行数が多い時に
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

    /// 一覧の先頭から数本を開いて「視聴済みにする」を押し、進捗を作る。
    private func markSomeVideosAsWatched() {
        for _ in 0..<max(0, watchedCount) {
            // 「次に見る／続きから」行は常に未視聴の先頭を開くので、繰り返すと順に進む
            let resumeRow = app.cells.element(boundBy: 1)
            guard resumeRow.exists && resumeRow.isHittable else { break }
            resumeRow.tap()

            let markButton = app.buttons["視聴済みにする"]
            if markButton.waitForExistence(timeout: 40) {
                markButton.tap()
                Thread.sleep(forTimeInterval: 0.6)
            }
            goBack()
        }
    }

    private func captureFilteredList() {
        let filterButton = app.buttons["並び替えと表示"]
        guard filterButton.waitForExistence(timeout: 10) else { return }
        filterButton.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Menu 内の Picker は環境により button / other として出る
        let unwatchedButton = app.buttons["未視聴のみ"]
        if unwatchedButton.waitForExistence(timeout: 5) {
            unwatchedButton.tap()
        } else {
            let alt = app.otherElements["未視聴のみ"].firstMatch
            if alt.exists { alt.tap() } else { return }
        }
        capture("03-filter-unwatched")

        // 全件表示に戻す
        filterButton.tap()
        Thread.sleep(forTimeInterval: 0.8)
        let all = app.buttons["すべて"]
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

        // 1回目: メモを入力するだけ
        let row = app.cells.element(boundBy: rowIndex)
        guard row.exists && row.isHittable else { return }
        row.tap()
        _ = app.buttons["視聴済みにする"].waitForExistence(timeout: 40)

        let memo = app.textViews.firstMatch
        if memo.exists && memo.isHittable {
            memo.tap()
            memo.typeText("導入回。用語の定義をここまでで押さえる。次回から実践パート。")
            Thread.sleep(forTimeInterval: 0.8)
            dismissKeyboard()
        }
        goBack()

        // 2回目: キーボードの無い状態で、プレイヤーの読み込みを待って撮る
        let row2 = app.cells.element(boundBy: rowIndex)
        guard row2.exists && row2.isHittable else { return }
        row2.tap()
        _ = app.buttons["視聴済みにする"].waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 10)  // 埋め込みプレイヤーの読み込み待ち
        capture("04-player-with-memo")

        goBack()
    }

    private func captureAboutScreen() {
        let aboutButton = app.buttons["このアプリについて"]
        guard aboutButton.waitForExistence(timeout: 10) else { return }
        aboutButton.tap()
        Thread.sleep(forTimeInterval: 1.2)
        capture("06-about-notice")
    }
}
