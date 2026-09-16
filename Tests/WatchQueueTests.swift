import XCTest
@testable import ChannelTimelineViewer

/// Watch Queue（V2）の再生とエラー表示の決まりごと。
///
/// ここで確かめるのは「保存に触れないこと」と「連続再生はユーザーが選んだときだけ働くこと」。
@MainActor
final class WatchQueueTests: XCTestCase {
    private func makeQueue(_ ids: [String], name: String = "Watch Queue") -> WatchQueueDTO {
        WatchQueueDTO(
            queueId: "11111111-2222-3333-4444-555555555555",
            name: name,
            version: 1,
            updatedAt: nil,
            items: ids.map {
                WatchQueueItemDTO(videoId: $0, title: "Title \($0)", channelName: "Ch", durationText: nil, addedAt: nil)
            })
    }

    private func makeSettings(autoPlayNext: Bool) -> PlaybackSettingsStore {
        let defaults = UserDefaults(suiteName: "watch-queue-tests-\(UUID().uuidString)")!
        defaults.set(autoPlayNext, forKey: "setting_autoplay_next_v1")
        return PlaybackSettingsStore(defaults: defaults)
    }

    func test_キューの順番どおりに再生する() {
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b", "c"]), settings: makeSettings(autoPlayNext: true))
        XCTAssertEqual(vm.current?.videoId, "a")
        XCTAssertEqual(vm.positionText, "1 / 3")

        vm.goNext()
        XCTAssertEqual(vm.current?.videoId, "b")
        vm.goLast()
        XCTAssertEqual(vm.current?.videoId, "c")
        XCTAssertFalse(vm.canGoNext)
        vm.goFirst()
        XCTAssertEqual(vm.current?.videoId, "a")
    }

    func test_自動再生がオンなら終了で次へ進む() {
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b"]), settings: makeSettings(autoPlayNext: true))
        vm.handleState(.playing)
        vm.handleState(.ended)
        XCTAssertEqual(vm.current?.videoId, "b")
        XCTAssertFalse(vm.showEndedSuggestion)
    }

    func test_自動再生がオフなら止まって次の動画を案内する() {
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b"]), settings: makeSettings(autoPlayNext: false))
        vm.handleState(.playing)
        vm.handleState(.ended)
        XCTAssertEqual(vm.current?.videoId, "a", "勝手に次へ進まない")
        XCTAssertTrue(vm.showEndedSuggestion)
        XCTAssertEqual(vm.nextEntry?.videoId, "b")

        vm.goNext()
        XCTAssertEqual(vm.current?.videoId, "b")
        XCTAssertFalse(vm.showEndedSuggestion)
    }

    func test_自動再生がオフのとき先回りの通知では進まない() {
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b"]), settings: makeSettings(autoPlayNext: false))
        vm.handleState(.playing)
        vm.handleNearEnd(videoId: "a")
        XCTAssertEqual(vm.current?.videoId, "a")
    }

    func test_再生が始まっていない動画の終了通知は無視する() {
        // 切り替えた直後に前の動画の終了通知が遅れて届いても、1本飛ばしにならないこと。
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b", "c"]), settings: makeSettings(autoPlayNext: true))
        vm.handleNearEnd(videoId: "a")
        XCTAssertEqual(vm.current?.videoId, "a")
    }

    func test_再生できない動画は飛ばす() {
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b", "c"]), settings: makeSettings(autoPlayNext: true))
        vm.handleError(150, videoId: "a")
        XCTAssertTrue(vm.unplayableIds.contains("a"))
        XCTAssertEqual(vm.current?.videoId, "b")

        vm.handleError(150, videoId: "b")
        XCTAssertEqual(vm.current?.videoId, "c")
    }

    func test_最後まで見たら完了になり最初から再生できる() {
        let vm = WatchQueuePlayerViewModel(queue: makeQueue(["a", "b"]), settings: makeSettings(autoPlayNext: true))
        vm.handleState(.playing)
        vm.handleState(.ended)          // a → b
        vm.handleState(.playing)
        vm.handleState(.ended)          // b で終わり
        XCTAssertTrue(vm.isCompleted)
        XCTAssertEqual(vm.playedIds, ["a", "b"])

        vm.restartQueue()
        XCTAssertFalse(vm.isCompleted)
        XCTAssertEqual(vm.current?.videoId, "a")
        XCTAssertTrue(vm.playedIds.isEmpty, "再生済みの印は画面の中だけのものなので消える")
    }

    func test_サーバーのエラーは利用者向けの文言に対応づく() {
        XCTAssertEqual(WatchQueueSyncError.disabled.messageKey, "watchQueue.error.disabled")
        XCTAssertEqual(WatchQueueSyncError.notFound.messageKey, "watchQueue.error.code")
        XCTAssertEqual(WatchQueueSyncError.expired.messageKey, "watchQueue.error.expired")
        XCTAssertEqual(WatchQueueSyncError.alreadyUsed.messageKey, "watchQueue.error.used")
        XCTAssertEqual(WatchQueueSyncError.tooManyAttempts.messageKey, "watchQueue.error.tooMany")
        XCTAssertEqual(WatchQueueSyncError.unauthorized.messageKey, "watchQueue.error.unauthorized")
        XCTAssertEqual(WatchQueueSyncError.network.messageKey, "watchQueue.error.network")
        XCTAssertEqual(WatchQueueSyncError.server.messageKey, "watchQueue.error.generic")
    }

    func test_接続していないあいだは何も出さない() {
        let defaults = UserDefaults(suiteName: "watch-queue-store-\(UUID().uuidString)")!
        let store = WatchQueueStore(defaults: defaults)
        // Feature Flag を一度も取れていない＝出さない。
        XCTAssertFalse(store.isAvailable)
        XCTAssertFalse(store.isPaired)
        XCTAssertTrue(store.queues.isEmpty)
    }
}
