import XCTest
@testable import ChannelTimelineViewer

/// リピート・スキップ・未視聴のみ再生のテスト。
@MainActor
final class PlaybackModeTests: XCTestCase {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "test.\(label).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeVideos(_ count: Int) -> [VideoItem] {
        (0..<count).map { i in
            VideoItem(id: "video\(i)", title: "第\(i + 1)回", description: "",
                      publishedAt: Date(timeIntervalSince1970: TimeInterval(i) * 86_400),
                      thumbnailURL: nil, channelId: "UCtest")
        }
    }

    /// テスト対象一式（あとから状態を確認できるようにストアも返す）。
    private struct Fixture {
        let vm: PlayerViewModel
        let videos: [VideoItem]
        let watch: WatchHistoryStore
        let skip: SkippedVideoStore
        let settings: PlaybackSettingsStore
    }

    private func makeFixture(count: Int = 5, startIndex: Int = 0) -> Fixture {
        let videos = makeVideos(count)
        let watch = WatchHistoryStore(defaults: makeDefaults("watch"))
        let skip = SkippedVideoStore(defaults: makeDefaults("skip"))
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        let vm = PlayerViewModel(videos: videos,
                                 startIndex: startIndex,
                                 watchStore: watch,
                                 skipStore: skip,
                                 positionStore: PlaybackPositionStore(defaults: makeDefaults("pos")),
                                 settings: settings)
        return Fixture(vm: vm, videos: videos, watch: watch, skip: skip, settings: settings)
    }

    private func playThrough(_ vm: PlayerViewModel) {
        vm.handleState(.playing)
        vm.handleState(.ended)
    }

    // MARK: - 既定値

    func testNewSettingsDefaults() {
        let settings = PlaybackSettingsStore(defaults: makeDefaults("settings"))
        XCTAssertEqual(settings.repeatMode, .off, "リピートは既定オフ")
        XCTAssertFalse(settings.playUnwatchedOnly, "未視聴のみ再生は既定オフ")
    }

    func testNewSettingsPersist() {
        let defaults = makeDefaults("settings")
        let settings = PlaybackSettingsStore(defaults: defaults)
        settings.repeatMode = .all
        settings.playUnwatchedOnly = true

        let reloaded = PlaybackSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.repeatMode, .all)
        XCTAssertTrue(reloaded.playUnwatchedOnly)
    }

    /// 右上のアイコンを押すたびに オフ → 1本 → 全体 → オフ と回ること。
    func testRepeatModeCyclesThroughAllStates() {
        XCTAssertEqual(RepeatMode.off.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .off)
    }

    /// 3状態がバッジで見分けられること（オフ＝枠線のみ、1本＝1入り、全体＝ALL入り）。
    func testRepeatModeBadgeAppearance() {
        XCTAssertFalse(RepeatMode.off.isActive, "オフは塗りつぶさない（枠線だけ）")
        XCTAssertTrue(RepeatMode.one.isActive)
        XCTAssertTrue(RepeatMode.all.isActive)

        XCTAssertEqual(RepeatMode.one.glyphSymbolName, "repeat.1", "1本は数字入りの記号")
        XCTAssertEqual(RepeatMode.off.glyphSymbolName, "repeat")
        XCTAssertEqual(RepeatMode.all.glyphSymbolName, "repeat")

        XCTAssertTrue(RepeatMode.all.showsAllLabel, "全体は ALL を重ねる")
        XCTAssertFalse(RepeatMode.one.showsAllLabel)
        XCTAssertFalse(RepeatMode.off.showsAllLabel)
    }

    // MARK: - ① リピート

    /// 1本リピートは、自動再生の設定に関わらず同じ動画を繰り返す。
    func testRepeatOneReplaysSameVideo() {
        let f = makeFixture()
        f.settings.repeatMode = .one
        f.settings.autoPlayNext = false

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 0, "動画は切り替わらない")
        XCTAssertEqual(f.vm.command?.kind, .replay, "先頭に戻して再生し直す")
        XCTAssertFalse(f.vm.showEndedSuggestion)
    }

    /// 1本リピートは何周でも続く（一度きりで止まらない）。
    func testRepeatOneKeepsRepeating() {
        let f = makeFixture()
        f.settings.repeatMode = .one

        playThrough(f.vm)
        let first = f.vm.command?.id
        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 0)
        XCTAssertEqual(f.vm.command?.kind, .replay)
        XCTAssertNotEqual(first, f.vm.command?.id, "毎回あらためて再生し直す")
    }

    /// 全体リピートは、最後まで行ったら先頭に戻る。
    func testRepeatAllWrapsToFirstVideo() {
        let f = makeFixture(count: 3, startIndex: 2)
        f.settings.autoPlayNext = true
        f.settings.repeatMode = .all

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 0, "先頭に戻る")
        XCTAssertTrue(f.vm.didAutoAdvance)
    }

    /// リピートなしなら最後で止まる。
    func testStopsAtLastVideoWithoutRepeat() {
        let f = makeFixture(count: 3, startIndex: 2)
        f.settings.autoPlayNext = true
        f.settings.repeatMode = .off

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 2)
        XCTAssertFalse(f.vm.showEndedSuggestion)
    }

    // MARK: - ② スキップ

    func testSkipStoreBasics() {
        let defaults = makeDefaults("skip")
        let store = SkippedVideoStore(defaults: defaults)

        XCTAssertFalse(store.isSkipped("v1"))
        store.toggleSkipped("v1")
        XCTAssertTrue(store.isSkipped("v1"))
        XCTAssertEqual(store.skippedCount, 1)

        // 再起動しても残る
        XCTAssertTrue(SkippedVideoStore(defaults: defaults).isSkipped("v1"))

        store.toggleSkipped("v1")
        XCTAssertFalse(store.isSkipped("v1"))
    }

    /// スキップ指定の動画は自動再生で飛ばされる。
    func testAutoAdvanceSkipsSkippedVideos() {
        let f = makeFixture(count: 5)
        f.settings.autoPlayNext = true
        f.skip.markSkipped(f.videos[1].id)
        f.skip.markSkipped(f.videos[2].id)

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 3, "スキップ2本を飛ばして4本目へ")
        XCTAssertFalse(f.watch.isWatched(f.videos[1].id), "飛ばした動画は視聴済みにしない")
    }

    /// スキップしか残っていなければ、そこで停止する。
    func testStopsWhenOnlySkippedVideosRemain() {
        let f = makeFixture(count: 3)
        f.settings.autoPlayNext = true
        f.skip.markSkipped(f.videos[1].id)
        f.skip.markSkipped(f.videos[2].id)

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 0, "進まない")
    }

    /// 手動の「次へ」はスキップ指定でも普通に進む（飛ばすのは自動再生のときだけ）。
    func testManualNextIgnoresSkipFlag() {
        let f = makeFixture(count: 3)
        f.skip.markSkipped(f.videos[1].id)

        f.vm.goNext()

        XCTAssertEqual(f.vm.currentIndex, 1)
    }

    func testToggleCurrentSkipped() {
        let f = makeFixture()
        XCTAssertFalse(f.vm.isCurrentSkipped())
        f.vm.toggleCurrentSkipped()
        XCTAssertTrue(f.vm.isCurrentSkipped())
        XCTAssertTrue(f.skip.isSkipped(f.videos[0].id))
    }

    // MARK: - ③ 未視聴のみ再生

    func testPlayUnwatchedOnlySkipsWatchedVideos() {
        let f = makeFixture(count: 5)
        f.settings.autoPlayNext = true
        f.settings.playUnwatchedOnly = true
        f.watch.markWatched(f.videos[1].id)
        f.watch.markWatched(f.videos[2].id)

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 3, "視聴済みを飛ばして未視聴へ")
    }

    func testPlaysWatchedVideosWhenUnwatchedOnlyIsOff() {
        let f = makeFixture(count: 3)
        f.settings.autoPlayNext = true
        f.settings.playUnwatchedOnly = false
        f.watch.markWatched(f.videos[1].id)

        playThrough(f.vm)

        XCTAssertEqual(f.vm.currentIndex, 1, "オフなら視聴済みでも再生する")
    }

    /// 未視聴のみ＋全体リピートでも、すべて視聴済みなら止まる（無限ループしない）。
    func testDoesNotLoopForeverWhenEverythingIsWatched() {
        let f = makeFixture(count: 3)
        f.settings.autoPlayNext = true
        f.settings.playUnwatchedOnly = true
        f.settings.repeatMode = .all
        f.videos.forEach { f.watch.markWatched($0.id) }

        XCTAssertNil(f.vm.nextIndexForAutoAdvance(), "再生できる動画が無ければ止まる")
    }

    /// 未視聴のみ＋全体リピートで、前方に未視聴が無ければ先頭側から探す。
    func testWrapsAroundToEarlierUnwatchedVideo() {
        let f = makeFixture(count: 4, startIndex: 2)
        f.settings.autoPlayNext = true
        f.settings.playUnwatchedOnly = true
        f.settings.repeatMode = .all
        f.watch.markWatched(f.videos[3].id)   // 後ろは視聴済み
        f.watch.markWatched(f.videos[0].id)   // 先頭も視聴済み
        // 残る未視聴は videos[1]

        XCTAssertEqual(f.vm.nextIndexForAutoAdvance(), 1)
    }
}
