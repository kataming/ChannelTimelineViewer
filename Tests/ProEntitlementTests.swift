import XCTest
@testable import ChannelTimelineViewer

/// 無料は1チャンネル、Pro は複数。入れ替え・削除では記録が消え、Pro 失効ではロックされる。
/// Android 版 `ProEntitlementTest.kt` / `ChannelDataRemoverTest.kt` と同じ約束を確かめる。
@MainActor
final class ProEntitlementTests: XCTestCase {

    // MARK: - 保存できる件数

    func test_無料は1件目を保存できる() {
        XCTAssertTrue(ChannelSlotPolicy.canOpen(savedChannelIds: [], channelId: "UC_new", isPro: false))
    }

    func test_無料は2件目を保存できない() {
        XCTAssertFalse(ChannelSlotPolicy.canOpen(savedChannelIds: ["UC_a"], channelId: "UC_new", isPro: false))
    }

    func test_無料でも保存済みのチャンネルは開ける() {
        XCTAssertTrue(ChannelSlotPolicy.canOpen(savedChannelIds: ["UC_a"], channelId: "UC_a", isPro: false))
    }

    func test_Proなら何件でも保存できる() {
        XCTAssertTrue(ChannelSlotPolicy.canOpen(savedChannelIds: ["UC_a", "UC_b"],
                                                channelId: "UC_new", isPro: true))
    }

    func test_入れ替えでは空きを作るぶんだけ外す() {
        XCTAssertEqual(ChannelSlotPolicy.idsToRemoveForReplacement(
            savedChannelIdsNewestFirst: ["UC_a"]), ["UC_a"])
        XCTAssertEqual(ChannelSlotPolicy.idsToRemoveForReplacement(
            savedChannelIdsNewestFirst: ["UC_b", "UC_c"]), ["UC_b", "UC_c"])
        XCTAssertTrue(ChannelSlotPolicy.idsToRemoveForReplacement(
            savedChannelIdsNewestFirst: []).isEmpty)
    }

    // MARK: - Pro 失効時のロック

    func test_Proなら保存済みは全部使える() {
        let saved = ["UC_a", "UC_b", "UC_c"]
        XCTAssertEqual(
            ChannelSlotPolicy.usableChannelIds(savedChannelIdsNewestFirst: saved,
                                               isPro: true, activeChannelId: nil),
            Set(saved))
    }

    func test_Proが外れると上限を超えた分はロックされる() {
        let saved = ["UC_new", "UC_old"]
        XCTAssertEqual(
            ChannelSlotPolicy.usableChannelIds(savedChannelIdsNewestFirst: saved,
                                               isPro: false, activeChannelId: nil),
            ["UC_new"])
        XCTAssertTrue(ChannelSlotPolicy.isLocked(savedChannelIdsNewestFirst: saved,
                                                 channelId: "UC_old",
                                                 isPro: false, activeChannelId: nil))
        XCTAssertFalse(ChannelSlotPolicy.isLocked(savedChannelIdsNewestFirst: saved,
                                                  channelId: "UC_new",
                                                  isPro: false, activeChannelId: nil))
    }

    func test_選んだチャンネルが無料枠になる() {
        let saved = ["UC_new", "UC_old"]
        XCTAssertEqual(
            ChannelSlotPolicy.usableChannelIds(savedChannelIdsNewestFirst: saved,
                                               isPro: false, activeChannelId: "UC_old"),
            ["UC_old"])
    }

    func test_保存が1件だけならロックは起きない() {
        XCTAssertFalse(ChannelSlotPolicy.isLocked(savedChannelIdsNewestFirst: ["UC_a"],
                                                  channelId: "UC_a",
                                                  isPro: false, activeChannelId: nil))
    }

    func test_選んだチャンネルが消えていても1つは使える() {
        XCTAssertEqual(
            ChannelSlotPolicy.usableChannelIds(savedChannelIdsNewestFirst: ["UC_a", "UC_b"],
                                               isPro: false, activeChannelId: "UC_gone"),
            ["UC_a"])
    }

    func test_Proに戻ればロックは解ける() {
        let saved = ["UC_a", "UC_b", "UC_c"]
        XCTAssertTrue(ChannelSlotPolicy.isLocked(savedChannelIdsNewestFirst: saved,
                                                 channelId: "UC_c",
                                                 isPro: false, activeChannelId: "UC_a"))
        XCTAssertFalse(ChannelSlotPolicy.isLocked(savedChannelIdsNewestFirst: saved,
                                                  channelId: "UC_c",
                                                  isPro: true, activeChannelId: "UC_a"))
    }

    // MARK: - 商品（価格）の取得状態

    func test_価格が取れるまで購入ボタンは押せない() {
        XCTAssertFalse(ProProductLoadState.idle.canPurchase)
        XCTAssertFalse(ProProductLoadState.loading.canPurchase)
        XCTAssertFalse(ProProductLoadState.failed("network").canPurchase)
        XCTAssertTrue(ProProductLoadState.loaded.canPurchase)
    }

    func test_価格を確認していますは取得中だけ出す() {
        // 取得に失敗したまま「価格を確認しています…」で止まるのが却下の原因だった。
        XCTAssertTrue(ProProductLoadState.idle.isLoading)
        XCTAssertTrue(ProProductLoadState.loading.isLoading)
        XCTAssertFalse(ProProductLoadState.failed("network").isLoading)
        XCTAssertFalse(ProProductLoadState.loaded.isLoading)
    }

    func test_失敗の理由は開発ログ用に残る() {
        XCTAssertEqual(ProProductLoadState.failed("商品が見つかりません").failureReason,
                       "商品が見つかりません")
        XCTAssertNil(ProProductLoadState.loaded.failureReason)
    }

    func test_商品IDはApp_Store_Connectの登録と完全一致する() {
        XCTAssertEqual(ProEntitlementStore.productID, "pro_unlock")
    }

    // MARK: - 記録の削除（入れ替え・削除で使う）

    func test_削除したチャンネルの記録は消え_他のチャンネルは残る() throws {
        let defaults = try makeDefaults()
        let favorites = FavoriteChannelStore(defaults: defaults)
        let progress = ChannelProgressStore(defaults: defaults)
        let cache = try makeCache()
        let watch = WatchHistoryStore(defaults: defaults)
        let skipped = SkippedVideoStore(defaults: defaults)
        let memos = VideoMemoStore(defaults: defaults)
        let positions = PlaybackPositionStore(defaults: defaults)

        let remover = ChannelDataRemover(favoriteStore: favorites,
                                         progressStore: progress,
                                         videoListCache: cache,
                                         watchHistoryStore: watch,
                                         skippedVideoStore: skipped,
                                         memoStore: memos,
                                         positionStore: positions)

        setUpChannel("UC_old", videoIds: ["v1", "v2"], favorites: favorites, progress: progress,
                     cache: cache, watch: watch, skipped: skipped, memos: memos, positions: positions)
        setUpChannel("UC_keep", videoIds: ["v9"], favorites: favorites, progress: progress,
                     cache: cache, watch: watch, skipped: skipped, memos: memos, positions: positions)

        let erased = remover.removeChannel("UC_old")

        XCTAssertEqual(erased, 2)
        XCTAssertFalse(watch.isWatched("v1"))
        XCTAssertFalse(watch.isWatched("v2"))
        XCTAssertFalse(skipped.isSkipped("v1"))
        XCTAssertEqual(memos.memo(for: "v1"), "")
        XCTAssertNil(positions.position(for: "v1"))
        XCTAssertNil(progress.progress(for: "UC_old"))
        XCTAssertNil(cache.videos(for: "UC_old"))
        XCTAssertFalse(favorites.favorites.contains { $0.id == "UC_old" })

        // 残す方は巻き込まれない。
        XCTAssertTrue(watch.isWatched("v9"))
        XCTAssertTrue(skipped.isSkipped("v9"))
        XCTAssertEqual(memos.memo(for: "v9"), "メモ v9")
        XCTAssertEqual(positions.position(for: "v9"), 120)
        XCTAssertTrue(favorites.favorites.contains { $0.id == "UC_keep" })
    }

    func test_一覧をまだ開いていないチャンネルでも削除できる() throws {
        let defaults = try makeDefaults()
        let favorites = FavoriteChannelStore(defaults: defaults)
        let remover = ChannelDataRemover(favoriteStore: favorites,
                                         progressStore: ChannelProgressStore(defaults: defaults),
                                         videoListCache: try makeCache(),
                                         watchHistoryStore: WatchHistoryStore(defaults: defaults),
                                         skippedVideoStore: SkippedVideoStore(defaults: defaults),
                                         memoStore: VideoMemoStore(defaults: defaults),
                                         positionStore: PlaybackPositionStore(defaults: defaults))
        favorites.upsert(Channel(id: "UC_never", title: "未取得", thumbnailURL: nil, uploadsPlaylistId: nil))

        XCTAssertEqual(remover.removeChannel("UC_never"), 0)
        XCTAssertTrue(favorites.favorites.isEmpty)
    }

    // MARK: - 補助

    /// 一覧キャッシュは実ファイルを使うので、テストごとに使い捨てのフォルダにする。
    private func makeCache() throws -> VideoListCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return VideoListCache(directory: directory)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "pro-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func setUpChannel(_ channelId: String,
                              videoIds: [String],
                              favorites: FavoriteChannelStore,
                              progress: ChannelProgressStore,
                              cache: VideoListCache,
                              watch: WatchHistoryStore,
                              skipped: SkippedVideoStore,
                              memos: VideoMemoStore,
                              positions: PlaybackPositionStore) {
        favorites.upsert(Channel(id: channelId, title: "チャンネル \(channelId)",
                                 thumbnailURL: nil, uploadsPlaylistId: nil))
        let videos = videoIds.map {
            VideoItem(id: $0, title: "動画 \($0)", description: "",
                      publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      thumbnailURL: nil, channelId: channelId)
        }
        cache.save(videos, for: channelId, uploadsPlaylistId: nil)
        for id in videoIds {
            watch.markWatched(id)
            skipped.markSkipped(id)
            memos.setMemo("メモ \(id)", for: id)
            positions.record(videoId: id, seconds: 120, duration: 600)
        }
        progress.updateCounts(channelId: channelId,
                              totalVideoCount: videoIds.count,
                              watchedVideoCount: videoIds.count)
    }
}
