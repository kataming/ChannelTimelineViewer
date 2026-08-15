import XCTest
@testable import ChannelTimelineViewer

/// 「続きから再生」と「終了時の自動再生」のテスト。
@MainActor
final class PlaybackResumeTests: XCTestCase {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "test.\(label).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeVideos(_ count: Int) -> [VideoItem] {
        (0..<count).map { i in
            VideoItem(id: "video\(i)",
                      title: "第\(i + 1)回",
                      description: "",
                      publishedAt: Date(timeIntervalSince1970: TimeInterval(i) * 86_400),
                      thumbnailURL: nil,
                      channelId: "UCtest")
        }
    }

    private func makeViewModel(videos: [VideoItem],
                               startIndex: Int = 0,
                               positionStore: PlaybackPositionStore,
                               settings: PlaybackSettingsStore) -> PlayerViewModel {
        PlayerViewModel(videos: videos,
                        startIndex: startIndex,
                        watchStore: WatchHistoryStore(defaults: makeDefaults("watch")),
                        positionStore: positionStore,
                        settings: settings)
    }

    // MARK: - 再生位置の保存

    func testRecordsAndReadsPosition() {
        let store = PlaybackPositionStore(defaults: makeDefaults("pos"))
        store.record(videoId: "v1", seconds: 125, duration: 600)
        XCTAssertEqual(store.position(for: "v1"), 125)
        XCTAssertTrue(store.hasPosition(for: "v1"))
    }

    func testDoesNotRecordPositionTooCloseToStart() {
        let store = PlaybackPositionStore(defaults: makeDefaults("pos"))
        store.record(videoId: "v1", seconds: 3, duration: 600)
        XCTAssertNil(store.position(for: "v1"), "冒頭すぎる位置は「続きから」の意味がないので保存しない")
    }

    func testClearsPositionWhenNearlyFinished() {
        let store = PlaybackPositionStore(defaults: makeDefaults("pos"))
        store.record(videoId: "v1", seconds: 100, duration: 600)
        store.record(videoId: "v1", seconds: 595, duration: 600)   // ほぼ見終わり
        XCTAssertNil(store.position(for: "v1"), "見終わった動画は次回また最初から")
    }

    func testPositionPersistsAcrossStoreInstances() {
        let defaults = makeDefaults("pos")
        let store = PlaybackPositionStore(defaults: defaults)
        store.record(videoId: "v1", seconds: 300, duration: 1200)

        let reloaded = PlaybackPositionStore(defaults: defaults)
        XCTAssertEqual(reloaded.position(for: "v1"), 300)
    }

    // MARK: - 設定

    func testSettingsDefaultToOn() {
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        XCTAssertTrue(settings.resumeFromLastPosition, "既定は「続きから再生」オン")
        XCTAssertTrue(settings.autoPlayNext, "既定は「自動で次を再生」オン")
    }

    func testSettingsPersist() {
        let defaults = makeDefaults("settings")
        let settings = PlaybackSettingsStore(defaults: defaults)
        settings.autoPlayNext = false
        settings.resumeFromLastPosition = false

        let reloaded = PlaybackSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.autoPlayNext)
        XCTAssertFalse(reloaded.resumeFromLastPosition)
    }

    // MARK: - 続きから再生

    func testStartsFromSavedPositionWhenEnabled() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3)
        positions.record(videoId: videos[0].id, seconds: 90, duration: 600)

        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)
        XCTAssertEqual(vm.startSecondsForCurrent, 90)
        XCTAssertTrue(vm.isResumingFromSavedPosition)
    }

    func testStartsFromBeginningWhenResumeDisabled() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.resumeFromLastPosition = false
        let videos = makeVideos(3)
        positions.record(videoId: videos[0].id, seconds: 90, duration: 600)

        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)
        XCTAssertEqual(vm.startSecondsForCurrent, 0)
        XCTAssertFalse(vm.isResumingFromSavedPosition)
    }

    func testRestartFromBeginningClearsSavedPosition() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3)
        positions.record(videoId: videos[0].id, seconds: 90, duration: 600)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        vm.restartFromBeginning()

        XCTAssertEqual(vm.startSecondsForCurrent, 0)
        XCTAssertNil(positions.position(for: videos[0].id))
        XCTAssertEqual(vm.seekRequest?.seconds, 0, "プレイヤーに先頭へ戻る要求を出す")
    }

    func testMovingToNextUsesThatVideosSavedPosition() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3)
        positions.record(videoId: videos[1].id, seconds: 45, duration: 600)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        vm.goNext()

        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.startSecondsForCurrent, 45)
    }

    func testTimeUpdateIsStoredForTheReportedVideoNotTheCurrentOne() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        // 動画を切り替えた直後に、切り替え前の動画の位置が届くことがある。
        vm.goNext()
        vm.handleTimeUpdate(videoId: videos[0].id, seconds: 120, duration: 600)

        XCTAssertEqual(positions.position(for: videos[0].id), 120)
        XCTAssertNil(positions.position(for: videos[1].id), "現在の動画に誤って記録しない")
    }

    // MARK: - 終了時の自動再生

    func testAutoPlaysNextWhenEnabled() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        vm.handleState(.ended)

        XCTAssertEqual(vm.currentIndex, 1, "続けて次の動画を再生する")
        XCTAssertTrue(vm.didAutoAdvance)
        XCTAssertFalse(vm.showEndedSuggestion)
    }

    func testShowsSuggestionInsteadWhenAutoPlayDisabled() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.autoPlayNext = false
        let videos = makeVideos(3)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        vm.handleState(.ended)

        XCTAssertEqual(vm.currentIndex, 0, "自動では進まない")
        XCTAssertTrue(vm.showEndedSuggestion, "「次の動画を再生」ボタンを出す")
    }

    func testDoesNotAdvancePastTheLastVideo() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(2)
        let vm = makeViewModel(videos: videos, startIndex: 1, positionStore: positions, settings: settings)

        vm.handleState(.ended)

        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertFalse(vm.showEndedSuggestion, "最後の動画では次を提示しない")
    }

    func testEndedClearsSavedPositionAndMarksWatched() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.autoPlayNext = false
        let watch = WatchHistoryStore(defaults: makeDefaults("watch"))
        let videos = makeVideos(2)
        positions.record(videoId: videos[0].id, seconds: 100, duration: 600)
        let vm = PlayerViewModel(videos: videos, startIndex: 0, watchStore: watch,
                                 positionStore: positions, settings: settings)

        vm.handleState(.ended)

        XCTAssertTrue(watch.isWatched(videos[0].id))
        XCTAssertNil(positions.position(for: videos[0].id), "見終わったら次は最初から")
    }

    func testDuplicateEndedEventsAdvanceOnlyOnce() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(4)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        vm.handleState(.ended)
        vm.handleState(.ended)   // 同じ動画の終了通知が重複して届いた場合

        XCTAssertEqual(vm.currentIndex, 1, "1本だけ進む")
    }

    // MARK: - 表示用

    func testTimeString() {
        XCTAssertEqual(PlaybackPosition.timeString(0), "0:00")
        XCTAssertEqual(PlaybackPosition.timeString(65), "1:05")
        XCTAssertEqual(PlaybackPosition.timeString(3725), "1:02:05")
    }

    func testPlayerPageURLIncludesStartOnlyWhenNeeded() throws {
        let withStart = try XCTUnwrap(
            YouTubePlayerWebView.pageURL(videoId: "dQw4w9WgXcQ", autoplay: true, start: 90)
        )
        XCTAssertTrue(withStart.absoluteString.contains("start=90"))

        let withoutStart = try XCTUnwrap(
            YouTubePlayerWebView.pageURL(videoId: "dQw4w9WgXcQ", autoplay: true, start: 0)
        )
        XCTAssertFalse(withoutStart.absoluteString.contains("start="))
    }
}
