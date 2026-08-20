import Foundation

/// チャンネルを開くときに必要なストア一式と、いまの Pro 状態。
///
/// 保存件数の制限とロックの判定にどれも要るので、まとめて渡す。
@MainActor
struct ChannelAccessContext {
    let favorites: FavoriteChannelStore
    let activeChannel: ActiveChannelStore
    let remover: ChannelDataRemover
    let isPro: Bool

    var savedIdsNewestFirst: [String] { favorites.favorites.map(\.id) }

    /// いま開けるチャンネル。ここに入らない保存済みチャンネルはロック表示にする。
    var usableChannelIds: Set<String> {
        ChannelSlotPolicy.usableChannelIds(savedChannelIdsNewestFirst: savedIdsNewestFirst,
                                           isPro: isPro,
                                           activeChannelId: activeChannel.activeChannelId)
    }
}

@MainActor
final class ChannelInputViewModel: ObservableObject {

    /// 確認が要る操作。どれも「記録が消える」か「Pro が要る」かのどちらか。
    enum Prompt: Identifiable {
        /// 無料で2件目を開こうとした。入れ替えると保存中のチャンネルの記録が消える。
        case replace(candidate: Channel, leavingTitles: String)
        /// 保存中のチャンネルを削除しようとした。記録も消える。
        case delete(favorite: FavoriteChannel)
        /// Pro が無効になってロックされたチャンネルを開こうとした。記録は消えない。
        case locked(favorite: FavoriteChannel)

        var id: String {
            switch self {
            case .replace(let candidate, _): return "replace-\(candidate.id)"
            case .delete(let favorite): return "delete-\(favorite.id)"
            case .locked(let favorite): return "locked-\(favorite.id)"
            }
        }
    }

    @Published var urlText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// 解決できたチャンネル。View はこれを監視して一覧画面へ遷移する。
    @Published var resolvedChannel: Channel?
    /// 出したい確認シート。
    @Published var prompt: Prompt?

    private let api: YouTubeAPIClient

    init(api: YouTubeAPIClient = YouTubeAPIClient()) {
        self.api = api
    }

    var isAPIConfigured: Bool { ConfigLoader.isConfigured }

    /// 入力URLからチャンネルを解決し、保存できるなら開く。
    /// 上限に当たったときは開かずに入れ替えの確認を出す。
    func fetch(context: ChannelAccessContext) async {
        errorMessage = nil

        guard isAPIConfigured else {
            errorMessage = YouTubeAPIError.apiKeyMissing.errorDescription
            return
        }
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = YouTubeAPIError.invalidChannelURL.errorDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var channel = try await api.resolveChannel(from: trimmed)
            if channel.uploadsPlaylistId == nil {
                channel.uploadsPlaylistId = try await api.fetchUploadsPlaylistId(channelId: channel.id)
            }
            openOrAskForPro(channel, context: context)
        } catch let error as YouTubeAPIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = YouTubeAPIError.unknown.errorDescription
        }
    }

    /// 共有シートから受け取った YouTube URL を開く。
    func openSharedLink(_ link: String, context: ChannelAccessContext) async {
        urlText = link
        // すでに一覧を開いている場合でも、共有された別チャンネルへ確実に切り替える。
        if resolvedChannel != nil {
            resolvedChannel = nil
            await Task.yield()
        }
        await fetch(context: context)
    }

    /// 保存済みの一覧から開く。ロック中なら開かずに案内を出す。
    func open(_ favorite: FavoriteChannel, context: ChannelAccessContext) {
        guard context.usableChannelIds.contains(favorite.id) else {
            prompt = .locked(favorite: favorite)
            return
        }
        openResolved(favorite.asChannel, context: context)
    }

    /// 削除の確認を出す（実行は `confirmDelete`）。
    func askToDelete(_ favorite: FavoriteChannel) {
        prompt = .delete(favorite: favorite)
    }

    func dismissPrompt() {
        prompt = nil
    }

    /// 入れ替えを実行する。**外すチャンネルの視聴済み・進捗・メモ・再生位置は削除される。**
    func confirmReplace(context: ChannelAccessContext) {
        guard case .replace(let candidate, _) = prompt else { return }
        prompt = nil
        ChannelSlotPolicy
            .idsToRemoveForReplacement(savedChannelIdsNewestFirst: context.savedIdsNewestFirst)
            .forEach { context.remover.removeChannel($0) }
        openResolved(candidate, context: context)
    }

    /// 削除を実行する。**そのチャンネルの記録も削除される。**
    func confirmDelete(context: ChannelAccessContext) {
        guard case .delete(let favorite) = prompt else { return }
        prompt = nil
        context.remover.removeChannel(favorite.id)
    }

    /// ロック中のチャンネルを「無料で使う1チャンネル」にする。記録はどちらも消えない。
    func useLockedChannel(context: ChannelAccessContext) {
        guard case .locked(let favorite) = prompt else { return }
        prompt = nil
        context.activeChannel.set(favorite.id)
        openResolved(favorite.asChannel, context: context)
    }

    /// Pro が無効なときに、無料で使い続けるチャンネルを選ぶ。
    func chooseFreeChannel(_ favorite: FavoriteChannel, context: ChannelAccessContext) {
        context.activeChannel.set(favorite.id)
    }

    // MARK: - 内部

    private func openOrAskForPro(_ channel: Channel, context: ChannelAccessContext) {
        guard ChannelSlotPolicy.canOpen(savedChannelIds: context.savedIdsNewestFirst,
                                        channelId: channel.id,
                                        isPro: context.isPro) else {
            // 警告に出す名前は「実際に外れるチャンネル」。複数まとめて外れることもあるので全部並べる。
            let leaving = Set(ChannelSlotPolicy
                .idsToRemoveForReplacement(savedChannelIdsNewestFirst: context.savedIdsNewestFirst))
            let titles = context.favorites.favorites
                .filter { leaving.contains($0.id) }
                .map(\.title)
                .joined(separator: "、")
            prompt = .replace(candidate: channel, leavingTitles: titles)
            return
        }
        openResolved(channel, context: context)
    }

    private func openResolved(_ channel: Channel, context: ChannelAccessContext) {
        // 無料のときは「いま使うチャンネル」も更新する（1件だけなら常にこれ）。
        if !context.isPro { context.activeChannel.set(channel.id) }
        context.favorites.upsert(channel)
        resolvedChannel = channel
    }
}
