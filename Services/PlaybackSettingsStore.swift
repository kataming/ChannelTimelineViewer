import Foundation

/// 繰り返し再生の種類。
enum RepeatMode: String, CaseIterable, Identifiable, Codable {
    /// 繰り返さない（既定）。
    case off
    /// いま再生している動画を繰り返す。
    case one
    /// 一覧の最後まで行ったら先頭に戻る（自動再生がオンのときに働く）。
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "オフ"
        case .one: return "1本"
        case .all: return "全体"
        }
    }

    /// ボタンを押したときの次の状態（オフ → 1本 → 全体 → オフ）。
    var next: RepeatMode {
        switch self {
        case .off: return .one
        case .one: return .all
        case .all: return .off
        }
    }

    /// リピートが働いている状態か（バッジを塗りつぶすかの判断に使う）。
    var isActive: Bool { self != .off }

    /// 記号の中央に重ねる文字（オフは無し）。
    var centerLabel: String? {
        switch self {
        case .off: return nil
        case .one: return "1"
        case .all: return "ALL"
        }
    }

    /// 読み上げ・説明用。
    var accessibilityDescription: String {
        switch self {
        case .off: return "リピートオフ"
        case .one: return "1本リピート"
        case .all: return "全体リピート"
        }
    }
}

/// 再生に関するユーザー設定（端末内に保存）。
///
/// - `resumeFromLastPosition`: 前回停止した位置から再生する（**既定オン**）
/// - `autoPlayNext`: 再生終了時に一覧の次の動画を続けて再生する（**既定オフ＝任意機能**）
///
/// 自動再生は既定でオフで、**ユーザーが再生画面のトグルで明示的にオンにしたときだけ**有効になる。
/// 対象は**ユーザーが開いたチャンネル一覧の中の「次の動画」だけ**で、YouTube の関連動画・
/// おすすめへは進まない。バックグラウンド再生は行わない（アプリを閉じると再生も止まる）。
///
/// 保存は「ユーザーが操作したときだけ」行う（`didSet` は init では呼ばれない）。
/// そのため未操作の端末には値が保存されず、アップデートで既定値が変わっても
/// **勝手にオンにはならない**。逆に、自分でオンにした人の設定は保持される。
@MainActor
final class PlaybackSettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let resumeKey = "setting_resume_from_last_position_v1"
    private let autoPlayNextKey = "setting_autoplay_next_v1"
    private let repeatModeKey = "setting_repeat_mode_v1"
    private let unwatchedOnlyKey = "setting_play_unwatched_only_v1"

    /// 続きから再生する（オフなら常に最初から）。
    @Published var resumeFromLastPosition: Bool {
        didSet { defaults.set(resumeFromLastPosition, forKey: resumeKey) }
    }

    /// 終了時に次の動画を自動で再生する（任意機能・既定オフ）。
    @Published var autoPlayNext: Bool {
        didSet { defaults.set(autoPlayNext, forKey: autoPlayNextKey) }
    }

    /// 繰り返し再生（既定オフ）。
    @Published var repeatMode: RepeatMode {
        didSet { defaults.set(repeatMode.rawValue, forKey: repeatModeKey) }
    }

    /// 自動再生で進むとき、未視聴の動画だけを再生する（既定オフ）。
    @Published var playUnwatchedOnly: Bool {
        didSet { defaults.set(playUnwatchedOnly, forKey: unwatchedOnlyKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 続きから再生は既定オン。
        self.resumeFromLastPosition = defaults.object(forKey: resumeKey) as? Bool ?? true
        // 自動再生は既定オフ。ユーザーが明示的にオンにした場合のみ true が保存されている。
        self.autoPlayNext = defaults.object(forKey: autoPlayNextKey) as? Bool ?? false
        self.repeatMode = (defaults.string(forKey: repeatModeKey))
            .flatMap(RepeatMode.init(rawValue:)) ?? .off
        self.playUnwatchedOnly = defaults.object(forKey: unwatchedOnlyKey) as? Bool ?? false
    }
}
