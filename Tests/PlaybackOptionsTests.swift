import XCTest
@testable import ChannelTimelineViewer

/// 再生設定（速度・字幕）をプレイヤー外の画面から操作する仕組みのテスト。
@MainActor
final class PlaybackOptionsTests: XCTestCase {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "test.\(label).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeViewModel() -> PlayerViewModel {
        let videos = (0..<3).map { i in
            VideoItem(id: "video\(i)", title: "第\(i + 1)回", description: "",
                      publishedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                      thumbnailURL: nil, channelId: "UCtest")
        }
        return PlayerViewModel(videos: videos,
                               startIndex: 0,
                               watchStore: WatchHistoryStore(defaults: makeDefaults("watch")),
                               skipStore: SkippedVideoStore(defaults: makeDefaults("skip")),
                               positionStore: PlaybackPositionStore(defaults: makeDefaults("pos")),
                               settings: PlaybackSettingsStore(defaults: makeDefaults("settings")))
    }

    // MARK: - プレイヤーから届く選択肢の解釈

    func testParsesOptionsMessage() {
        let body: [String: Any] = [
            "event": "options",
            "rates": [0.5, 1, 1.5, 2],
            "rate": 1.5,
            "captions": [
                ["code": "ja", "name": "日本語（自動生成）"],
                ["code": "en", "name": "English"],
                ["code": "", "name": "壊れたトラック"],
            ],
            "activeCaption": "ja",
        ]
        let options = YouTubePlayerWebView.parseOptions(body)

        XCTAssertEqual(options.rates, [0.5, 1, 1.5, 2])
        XCTAssertEqual(options.rate, 1.5)
        XCTAssertEqual(options.captions.map(\.code), ["ja", "en"], "コードが空のものは無視する")
        XCTAssertEqual(options.captions.first?.name, "日本語（自動生成）")
        XCTAssertEqual(options.activeCaption, "ja")
    }

    func testParsesEmptyOptionsSafely() {
        let options = YouTubePlayerWebView.parseOptions(["event": "options"])
        XCTAssertTrue(options.rates.isEmpty)
        XCTAssertEqual(options.rate, 1)
        XCTAssertTrue(options.captions.isEmpty)
        XCTAssertNil(options.activeCaption)
    }

    // MARK: - 速度

    func testFallsBackToCommonRatesBeforePlayerReports() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.availableRates, [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2])
    }

    func testUsesRatesReportedByPlayer() {
        let vm = makeViewModel()
        vm.handleOptions(YouTubePlayerWebView.parseOptions(["rates": [1, 2], "rate": 1]))
        XCTAssertEqual(vm.availableRates, [1, 2])
    }

    func testSettingRateSendsCommand() {
        let vm = makeViewModel()
        vm.setPlaybackRate(1.5)

        XCTAssertEqual(vm.options.rate, 1.5)
        XCTAssertEqual(vm.command?.kind, .playbackRate(1.5))
        XCTAssertEqual(vm.command?.javaScript, "setRate(1.50);")
    }

    /// 表示は言語ごとに変わるので、数値の作り方だけを見る。
    func testRateLabels() {
        // 等倍は「1」（1.00 のような表記にしない）
        XCTAssertTrue(PlayerViewModel.rateLabel(1).contains("1"))
        XCTAssertFalse(PlayerViewModel.rateLabel(1).contains("1.0"))
        XCTAssertTrue(PlayerViewModel.rateLabel(2).contains("2"))
        // 端数はそのまま残す（余計な 0 を付けない）
        XCTAssertTrue(PlayerViewModel.rateLabel(1.5).contains("1.5"))
        XCTAssertFalse(PlayerViewModel.rateLabel(1.5).contains("1.50"))
        XCTAssertTrue(PlayerViewModel.rateLabel(1.25).contains("1.25"))
        XCTAssertTrue(PlayerViewModel.rateLabel(0.75).contains("0.75"))
    }

    // MARK: - 字幕

    func testSelectingCaptionTrackSendsCommand() {
        let vm = makeViewModel()
        vm.setCaptionTrack("ja")

        XCTAssertEqual(vm.options.activeCaption, "ja")
        XCTAssertEqual(vm.command?.javaScript, "setCaptionTrack('ja');")
    }

    func testTurningCaptionsOffSendsEmptyTrack() {
        let vm = makeViewModel()
        vm.setCaptionTrack("ja")
        vm.setCaptionTrack(nil)

        XCTAssertNil(vm.options.activeCaption)
        XCTAssertEqual(vm.command?.javaScript, "setCaptionTrack('');")
    }

    /// 外から来た値をそのまま JavaScript に埋め込まないこと。
    func testCaptionCodeIsSanitized() {
        let command = YouTubePlayerWebView.PlayerCommand(.captionTrack("ja'); alert('x"))
        XCTAssertEqual(command.javaScript, "setCaptionTrack('jaalertx');")
    }

    func testPlaybackRateIsClamped() {
        XCTAssertEqual(YouTubePlayerWebView.PlayerCommand(.playbackRate(99)).javaScript, "setRate(4.00);")
        XCTAssertEqual(YouTubePlayerWebView.PlayerCommand(.playbackRate(0)).javaScript, "setRate(0.25);")
    }

    func testRefreshOptionsSendsCommand() {
        let vm = makeViewModel()
        vm.refreshOptions()
        XCTAssertEqual(vm.command?.javaScript, "postOptions();")
    }

    // MARK: - 再生画面に出す状態表示

    /// 要約の文言は言語ごとに変わるので、必要な値が入っているかを見る。
    func testSummaryShowsRateAndCaptionState() {
        let vm = makeViewModel()
        let initial = vm.optionsSummary
        XCTAssertTrue(initial.contains("1"), "速度が入っている")
        XCTAssertTrue(initial.contains(String(localized: "captions.off")), "字幕オフが入っている")

        vm.handleOptions(YouTubePlayerWebView.parseOptions([
            "rates": [1, 1.5],
            "rate": 1.5,
            "captions": [["code": "ja", "name": "日本語（自動生成）"]],
            "activeCaption": "ja",
        ]))
        let updated = vm.optionsSummary
        XCTAssertTrue(updated.contains("1.5"), "変更後の速度が入っている")
        XCTAssertTrue(updated.contains("日本語（自動生成）"), "選んだ字幕トラック名が入っている")
    }

    /// 操作要求は毎回別の id を持ち、同じ操作を繰り返せること。
    func testCommandsAreDistinguishable() {
        let vm = makeViewModel()
        vm.setPlaybackRate(1.5)
        let first = vm.command
        vm.setPlaybackRate(1.5)
        XCTAssertNotEqual(first?.id, vm.command?.id)
    }
}
