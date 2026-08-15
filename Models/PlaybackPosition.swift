import Foundation

/// 動画ごとの「前回どこまで見たか」（秒）。
/// 公式プレイヤーから通知された再生位置を端末内に保存するだけで、動画データは保持しない。
struct PlaybackPosition: Codable, Hashable, Identifiable {
    let videoId: String
    /// 前回停止した位置（秒）。
    var seconds: Double
    /// 動画の長さ（秒）。取得できなかった場合は 0。
    var duration: Double
    var updatedAt: Date

    var id: String { videoId }

    /// 「12:34」「1:02:03」形式の表示用文字列。
    static func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
