import Foundation

/// チャンネルごとの動画一覧を端末内に保存しておくキャッシュ。
///
/// 本数の多いチャンネルは全ページ取得に時間がかかる（1ページ50本 × 最大100ページ）。
/// 2回目以降は保存した一覧をすぐ表示し、**新着だけ**を取りに行けるようにする。
///
/// - 保存先は Caches ディレクトリ。消えても取り直せる情報しか入れない。
/// - 保存するのは公式 API から取得した公開情報（videoId・タイトル・公開日など）のみ。
final class VideoListCache {
    /// 1チャンネル分の保存内容。
    struct Entry: Codable {
        var videos: [VideoItem]
        var updatedAt: Date
        /// 取得元のアップロードプレイリストID（チャンネル側で変わった場合に作り直すため）。
        var uploadsPlaylistId: String?
    }

    private let directory: URL
    private let fileManager: FileManager

    init(directoryName: String = "VideoLists", fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// テスト用に保存先を指定する。
    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func entry(for channelId: String) -> Entry? {
        guard let url = fileURL(for: channelId),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return entry
    }

    func videos(for channelId: String) -> [VideoItem]? {
        guard let entry = entry(for: channelId), !entry.videos.isEmpty else { return nil }
        return entry.videos
    }

    func save(_ videos: [VideoItem],
              for channelId: String,
              uploadsPlaylistId: String?,
              at date: Date = Date()) {
        guard let url = fileURL(for: channelId), !videos.isEmpty else { return }
        let entry = Entry(videos: videos, updatedAt: date, uploadsPlaylistId: uploadsPlaylistId)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func remove(_ channelId: String) {
        guard let url = fileURL(for: channelId) else { return }
        try? fileManager.removeItem(at: url)
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    /// チャンネルIDをファイル名に使えるようにする（記号は落とす）。
    private func fileURL(for channelId: String) -> URL? {
        let safe = channelId.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard !safe.isEmpty else { return nil }
        return directory.appendingPathComponent("\(safe).json", isDirectory: false)
    }
}
