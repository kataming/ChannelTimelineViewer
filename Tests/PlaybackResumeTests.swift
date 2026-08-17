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
                        skipStore: SkippedVideoStore(defaults: makeDefaults("skip")),
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

    func testAutoPlayIsOffByDefaultAndResumeIsOn() {
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        XCTAssertFalse(settings.autoPlayNext, "自動再生は任意機能なので既定オフ")
        XCTAssertTrue(settings.resumeFromLastPosition, "続きから再生は既定オン")
    }

    func testSettingsPersist() {
        let defaults = makeDefaults("settings")
        let settings = PlaybackSettingsStore(defaults: defaults)
        settings.autoPlayNext = true
        settings.resumeFromLastPosition = false

        let reloaded = PlaybackSettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.autoPlayNext, "ユーザーがオンにした設定は保持する")
        XCTAssertFalse(reloaded.resumeFromLastPosition)
    }

    /// 未操作の端末には値が保存されず、アップデートで勝手にオンにならないこと。
    func testUntouchedSettingIsNotPersistedAndStaysOff() {
        let defaults = makeDefaults("settings")
        _ = PlaybackSettingsStore(defaults: defaults)   // 生成しただけ（ユーザー操作なし）

        XCTAssertNil(defaults.object(forKey: "setting_autoplay_next_v1"),
                     "既定値は保存しない（あとで既定を変えても上書きしない）")
        XCTAssertFalse(PlaybackSettingsStore(defaults: defaults).autoPlayNext)
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
        XCTAssertEqual(vm.command?.kind, .seek(0), "プレイヤーに先頭へ戻る要求を出す")
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

    /// 実際のプレイヤーは「再生開始 → 終了」の順に通知してくる。
    private func playThrough(_ vm: PlayerViewModel) {
        vm.handleState(.playing)
        vm.handleState(.ended)
    }

    /// ユーザーが明示的にオンにした場合だけ、終了後に次へ進む。
    func testAutoPlaysNextOnlyWhenUserTurnsItOn() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.autoPlayNext = true        // ユーザーが再生画面のトグルでオンにした
        let videos = makeVideos(3)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        playThrough(vm)

        XCTAssertEqual(vm.currentIndex, 1, "続けて次の動画を再生する")
        XCTAssertTrue(vm.didAutoAdvance)
        XCTAssertFalse(vm.showEndedSuggestion)

        // 次の動画も最後まで見れば、さらに次へ進む。
        playThrough(vm)
        XCTAssertEqual(vm.currentIndex, 2)
    }

    /// 既定（オフ）のままなら、終了後は停止して手動ボタンを出す。
    func testStopsAndShowsManualButtonByDefault() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        XCTAssertFalse(settings.autoPlayNext, "既定オフのまま検証する")
        let videos = makeVideos(3)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        playThrough(vm)

        XCTAssertEqual(vm.currentIndex, 0, "自動では進まない")
        XCTAssertTrue(vm.showEndedSuggestion, "「次の動画を再生」ボタンを出す")
    }

    func testDoesNotAdvancePastTheLastVideo() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.autoPlayNext = true
        let videos = makeVideos(2)
        let vm = makeViewModel(videos: videos, startIndex: 1, positionStore: positions, settings: settings)

        playThrough(vm)

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
                                 skipStore: SkippedVideoStore(defaults: makeDefaults("skip")),
                                 positionStore: positions, settings: settings)

        playThrough(vm)

        XCTAssertTrue(watch.isWatched(videos[0].id))
        XCTAssertNil(positions.position(for: videos[0].id), "見終わったら次は最初から")
    }

    /// 自動送りの直後に、前の動画の「終了」通知が遅れて届いても1本しか進まないこと。
    /// （これを取りこぼすと動画が1本飛ばされる）
    func testStaleEndedEventAfterAutoAdvanceIsIgnored() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.autoPlayNext = true
        let watch = WatchHistoryStore(defaults: makeDefaults("watch"))
        let videos = makeVideos(4)
        let vm = PlayerViewModel(videos: videos, startIndex: 0, watchStore: watch,
                                 skipStore: SkippedVideoStore(defaults: makeDefaults("skip")),
                                 positionStore: positions, settings: settings)

        vm.handleState(.playing)
        vm.handleState(.ended)
        vm.handleState(.ended)   // 切り替え直後に遅れて届いた通知

        XCTAssertEqual(vm.currentIndex, 1, "1本だけ進む")
        XCTAssertTrue(watch.isWatched(videos[0].id), "実際に見た動画だけ視聴済みになる")
        XCTAssertFalse(watch.isWatched(videos[1].id), "再生していない動画に視聴済みが付かない")
        XCTAssertFalse(watch.isWatched(videos[2].id))
    }

    func testEndedBeforePlaybackStartsIsIgnored() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3)
        let vm = makeViewModel(videos: videos, positionStore: positions, settings: settings)

        vm.handleState(.ended)   // まだ一度も再生されていない

        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertFalse(vm.showEndedSuggestion)
    }

    // MARK: - 移動（最初へ / 最後へ / 戻る）

    func testGoFirstAndGoLast() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(10)
        let vm = makeViewModel(videos: videos, startIndex: 4, positionStore: positions, settings: settings)

        vm.goLast()
        XCTAssertEqual(vm.currentIndex, 9)
        XCTAssertFalse(vm.canGoNext)

        vm.goFirst()
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertFalse(vm.canGoPrevious)
    }

    /// 「最初へ」を押し間違えても、「戻る」で元の動画・再生位置に復帰できること。
    func testGoBackRestoresPreviousVideoAndPosition() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(10)
        let vm = makeViewModel(videos: videos, startIndex: 4, positionStore: positions, settings: settings)

        XCTAssertFalse(vm.canGoBack, "まだ移動していないので戻れない")

        // 5本目を 8分20秒まで見ている状態
        vm.handleState(.playing)
        vm.handleTimeUpdate(videoId: videos[4].id, seconds: 500, duration: 1800)

        vm.goFirst()   // 押し間違え
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertTrue(vm.canGoBack)

        vm.goBack()
        XCTAssertEqual(vm.currentIndex, 4, "元の動画に戻る")
        XCTAssertEqual(vm.startSecondsForCurrent, 500, "元の再生位置から再開する")
        XCTAssertFalse(vm.canGoBack, "履歴を使い切ったら無効になる")
    }

    /// 続きから再生をオフにしていても、「戻る」なら元の位置に戻ること。
    func testGoBackRestoresPositionEvenWhenResumeDisabled() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        settings.resumeFromLastPosition = false
        let videos = makeVideos(5)
        let vm = makeViewModel(videos: videos, startIndex: 1, positionStore: positions, settings: settings)

        vm.handleState(.playing)
        vm.handleTimeUpdate(videoId: videos[1].id, seconds: 300, duration: 1200)
        vm.goNext()
        XCTAssertEqual(vm.startSecondsForCurrent, 0, "通常の移動では最初から")

        vm.goBack()
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.startSecondsForCurrent, 300)
    }

    func testGoBackWalksThroughMultipleMoves() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(10)
        let vm = makeViewModel(videos: videos, startIndex: 3, positionStore: positions, settings: settings)

        vm.goNext()    // 4
        vm.goLast()    // 9
        vm.goFirst()   // 0

        vm.goBack()
        XCTAssertEqual(vm.currentIndex, 9)
        vm.goBack()
        XCTAssertEqual(vm.currentIndex, 4)
        vm.goBack()
        XCTAssertEqual(vm.currentIndex, 3)
        XCTAssertFalse(vm.canGoBack)
        vm.goBack()
        XCTAssertEqual(vm.currentIndex, 3, "履歴が空なら何も起きない")
    }

    // MARK: - 表示用

    func testPositionTextShowsCurrentAndTotalWithSeparators() {
        let positions = PlaybackPositionStore(defaults: makeDefaults("pos"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let videos = makeVideos(3_500)
        let vm = makeViewModel(videos: videos, startIndex: 1_033,
                               positionStore: positions, settings: settings)

        XCTAssertEqual(vm.currentPosition, 1_034)
        XCTAssertEqual(vm.totalCount, 3_500)
        XCTAssertEqual(vm.positionText, "1,034 / 3,500")
    }

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
