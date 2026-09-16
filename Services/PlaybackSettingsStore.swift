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
        case .off: return String(localized: "repeat.off")
        case .one: return String(localized: "repeat.one")
        case .all: return String(localized: "repeat.all")
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
        case .off: return String(localized: "repeat.a11y.off")
        case .one: return String(localized: "repeat.a11y.one")
        case .all: return String(localized: "repeat.a11y.all")
        }
    }
}

/// 再生に関するユーザー設定（端末内に保存）。
///
/// - `resumeFromLastPosition`: 前回停止した位置から再生する（**既定オン**）
/// - `autoPlayNext`: 再生終了時に一覧の次の動画を続けて再生する（**既定オン**・2026-09-16 変更）
///
/// 自動再生が進む先は**ユーザーが開いたチャンネル一覧の中の「次の動画」だけ**で、
/// YouTube の関連動画・おすすめへは進まない。再生画面の「自動再生」トグルでいつでもオフにできる。
/// バックグラウンド再生は行わない（アプリを閉じると再生も止まる）。
///
/// ⚠️ **既定値は「まだ一度も操作していない人」にだけ効く。**
/// 保存は `didSet`＝ユーザーが操作したときだけ行う（init では呼ばれない）ので、
/// `defaults.object(forKey:)` が nil かどうかで「未操作」と「自分で選んだ」を見分けられる。
/// 自分でオフにした人は**オフのまま**、オンにした人は**オンのまま**引き継がれ、
/// 既定値の変更で上書きされることはない。ここを `defaults.bool(forKey:)` に変えると
/// 区別がつかなくなり、利用者が選んだ設定を踏み潰すので**変えないこと**。
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

    /// 終了時に次の動画を自動で再生する（既定オン。いつでもオフにできる）。
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
        // 自動再生は既定オン。自分で切り替えた人だけ値が保存されているので、その選択を優先する。
        self.autoPlayNext = defaults.object(forKey: autoPlayNextKey) as? Bool ?? true
        self.repeatMode = (defaults.string(forKey: repeatModeKey))
            .flatMap(RepeatMode.init(rawValue:)) ?? .off
        self.playUnwatchedOnly = defaults.object(forKey: unwatchedOnlyKey) as? Bool ?? false
    }
}
