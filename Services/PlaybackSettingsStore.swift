import Foundation

/// 再生に関するユーザー設定（端末内に保存）。
///
/// - `resumeFromLastPosition`: 前回停止した位置から再生する（既定オン）
/// - `autoPlayNext`: 再生終了時に一覧の次の動画を続けて再生する（既定オン）
///
/// 自動再生は**ユーザーが開いたチャンネル一覧の中の「次の動画」だけ**を対象にし、
/// いつでもオフにできる。バックグラウンド再生は行わない（アプリを閉じると再生も止まる）。
@MainActor
final class PlaybackSettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let resumeKey = "setting_resume_from_last_position_v1"
    private let autoPlayNextKey = "setting_autoplay_next_v1"

    /// 続きから再生する（オフなら常に最初から）。
    @Published var resumeFromLastPosition: Bool {
        didSet { defaults.set(resumeFromLastPosition, forKey: resumeKey) }
    }

    /// 終了時に次の動画を自動で再生する。
    @Published var autoPlayNext: Bool {
        didSet { defaults.set(autoPlayNext, forKey: autoPlayNextKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 未設定なら既定オン。
        self.resumeFromLastPosition = defaults.object(forKey: resumeKey) as? Bool ?? true
        self.autoPlayNext = defaults.object(forKey: autoPlayNextKey) as? Bool ?? true
    }
}
