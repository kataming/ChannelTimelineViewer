import XCTest

/// App Store 提出用スクリーンショットを撮るための UI テスト。
///
/// 通常の CI では実行しない（実 API とネットワークを使い、時間もかかるため）。
/// `Screenshots` スキーム経由で、`.github/workflows/ios-screenshots.yml` から実行される。
///
/// 撮影対象は docs/screenshot-production-guide.md の「推奨カット」に対応:
///   01 ホーム（チャンネル入力・お気に入り）
///   02 動画一覧（進捗バー＋次に見る）
///   03 フィルター（未視聴のみ）
///   04 再生画面（公式プレイヤー＋メモ）
///   05 進捗／続きから
///   06 このアプリについて（注意事項）
///
/// 撮った画像は XCTAttachment として .xcresult に入る。ワークフロー側で
/// `xcrun xcresulttool export attachments` により PNG として取り出す。
final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    /// 撮影対象チャンネル。ワークフローの入力から環境変数で渡す。
    private var channelURL: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_CHANNEL_URL"]
            ?? "https://www.youtube.com/@NASA"
    }

    /// 進捗バーに意味のある数字を出すため、何本を視聴済みにするか。
    private var watchedCount: Int {
        Int(ProcessInfo.processInfo.environment["SCREENSHOT_WATCHED_COUNT"] ?? "") ?? 3
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - ヘルパー

    /// 画面を撮って .xcresult に添付する。ファイル名の先頭に通し番号を付けて順序を保つ。
    private func capture(_ name: String) {
        // アニメーション・非同期描画が落ち着くのを待つ
        Thread.sleep(forTimeInterval: 1.2)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 30,
                         _ message: String = "") -> Bool {
        let ok = element.waitForExistence(timeout: seconds)
        if !ok && !message.isEmpty {
            XCTFail("要素が現れませんでした: \(message)")
        }
        return ok
    }

    // MARK: - 撮影本体

    func testCaptureAppStoreScreenshots() throws {
        // --- 01 ホーム（チャンネル入力） ---
        let urlField = app.textFields.firstMatch
        waitFor(urlField, 20, "チャンネルURL入力欄")
        urlField.tap()
        urlField.typeText(channelURL)
        // キーボードを閉じて画面全体を見せる
        if app.keyboards.count > 0 {
            app.toolbars.buttons.firstMatch.tap()
        }
        capture("01-home-channel-input")

        // --- 動画を取得 ---
        let fetchButton = app.buttons["動画を取得"]
        waitFor(fetchButton, 10, "『動画を取得』ボタン")
        fetchButton.tap()

        // 一覧が出るまで待つ（API 取得 + ページネーションで時間がかかる）
        let progressLabel = app.staticTexts["進捗"]
        guard waitFor(progressLabel, 120) else {
            capture("ERROR-fetch-failed")
            XCTFail("動画一覧を取得できませんでした（APIキー/ネットワークを確認）")
            return
        }

        // --- 何本かを視聴済みにして、進捗バーに数字を出す ---
        markSomeVideosAsWatched()

        // --- 02 動画一覧（進捗バー＋次に見る） ---
        capture("02-video-list-progress")

        // --- 05 進捗／続きから（一覧上部を拡大して見せる用に、先頭までスクロール） ---
        app.tables.firstMatch.swipeDown()
        capture("05-progress-resume")

        // --- 03 フィルター（未視聴のみ） ---
        let filterButton = app.buttons["並び替えと表示"]
        if waitFor(filterButton, 10) {
            filterButton.tap()
            let unwatched = app.buttons["未視聴のみ"]
            if waitFor(unwatched, 5) {
                unwatched.tap()
            } else {
                // Picker がボタンでなく別要素として現れる場合のフォールバック
                app.otherElements["未視聴のみ"].firstMatch.tap()
            }
            capture("03-filter-unwatched")

            // 元に戻す（全件表示）
            filterButton.tap()
            let all = app.buttons["すべて"]
            if waitFor(all, 5) { all.tap() }
        }

        // --- 04 再生画面（公式プレイヤー＋メモ） ---
        capturePlayerScreen()

        // --- 06 このアプリについて ---
        captureAboutScreen()
    }

    /// 一覧の先頭から数本を開いて「視聴済みにする」を押し、進捗を作る。
    private func markSomeVideosAsWatched() {
        for _ in 0..<max(0, watchedCount) {
            // 「次に見る／続きから」行を使うと、常に未視聴の先頭が開ける
            let resumeRow = app.cells.element(boundBy: 1)
            guard resumeRow.exists else { break }
            resumeRow.tap()

            let markButton = app.buttons["視聴済みにする"]
            if waitFor(markButton, 30) {
                markButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()  // 戻る
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    private func capturePlayerScreen() {
        // 一覧の適当な動画を開く
        let row = app.cells.element(boundBy: 3)
        guard row.exists else { return }
        row.tap()

        // プレイヤーの読み込み待ち（埋め込みプレイヤーは時間がかかる）
        _ = app.buttons["視聴済みにする"].waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: 6)

        // メモ欄にサンプルを入力（学習用途が伝わるように）
        let memo = app.textViews.firstMatch
        if memo.exists {
            memo.tap()
            memo.typeText("導入回。用語の定義をここまでで押さえる。次回から実践パート。")
            if app.keyboards.count > 0 {
                app.toolbars.buttons.firstMatch.tap()
            }
        }
        capture("04-player-with-memo")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func captureAboutScreen() {
        // ルート（チャンネル入力）まで戻る
        while app.navigationBars.buttons.element(boundBy: 0).exists,
              !app.buttons["動画を取得"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }

        let aboutButton = app.buttons["このアプリについて"]
        if waitFor(aboutButton, 10) {
            aboutButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
            capture("06-about-notice")
        }
    }
}
