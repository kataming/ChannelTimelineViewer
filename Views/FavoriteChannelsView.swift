import SwiftUI

/// リモート画像のサムネイル（チャンネル/動画共用）。
struct RemoteThumbnail: View {
    let url: URL?
    var width: CGFloat = 120
    var height: CGFloat = 68
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color.gray.opacity(0.3).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            case .empty:
                Color.gray.opacity(0.15).overlay(ProgressView())
            @unknown default:
                Color.gray.opacity(0.15)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// お気に入り（最近使った）チャンネルの一覧行。
/// Form / List の Section 内に配置して使う。
struct FavoriteChannelsView: View {
    @EnvironmentObject private var favoriteStore: FavoriteChannelStore
    @EnvironmentObject private var progressStore: ChannelProgressStore
    var onSelect: (FavoriteChannel) -> Void

    var body: some View {
        ForEach(favoriteStore.favorites) { favorite in
            Button {
                onSelect(favorite)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        RemoteThumbnail(url: favorite.thumbnailURL, width: 44, height: 44, cornerRadius: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("最終: \(favorite.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    progressRow(for: favorite)
                    if progressStore.progress(for: favorite.id)?.lastOpenedVideoId != nil {
                        Label("続きから見る", systemImage: "play.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                    }
                }
            }
            // 1件ずつ消す導線（左スワイプ）。分かるように Section の footer で案内している。
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    remove(favorite)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
        .onDelete { offsets in
            // 編集モード（EditButton）からの削除。
            let targets = offsets.map { favoriteStore.favorites[$0] }
            targets.forEach { remove($0) }
        }
    }

    /// 一覧から1件消す。視聴済みの記録（動画単位）は残し、チャンネルの進捗キャッシュだけ消す。
    /// 同じチャンネルを開き直せば、視聴済みから進捗は再計算される。
    private func remove(_ favorite: FavoriteChannel) {
        favoriteStore.remove(favorite.id)
        progressStore.remove(favorite.id)
    }

    @ViewBuilder
    private func progressRow(for favorite: FavoriteChannel) -> some View {
        if let p = progressStore.progress(for: favorite.id), p.totalVideoCount > 0 {
            ProgressView(value: p.progressRate)
                .tint(.green)
            Text("\(p.watchedVideoCount) / \(p.totalVideoCount)本 視聴済み（\(Int((p.progressRate * 100).rounded()))%）")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("進捗はチャンネルを開くと表示されます")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
