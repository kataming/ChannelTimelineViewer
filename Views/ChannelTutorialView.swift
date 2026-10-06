import SwiftUI
import UIKit

/// 「YouTube のチャンネルをこのアプリに追加する方法」の案内。
///
/// なぜ要るか: 追加の入口が「YouTube の共有 → このアプリを選ぶ」で、
/// 初めての人には見つけられない。入れた直後に何もできずに終わるのを防ぐ。
///
/// 2026-10-05 からは「チャンネルの追加」のシート（`ChannelAddGuideView`）の中の1ページで、
/// 「YouTube の共有から追加する」の案内の下の「共有メニューから〜を選ぶ方法を見る」から開く
/// （Android と同じ並び）。**この画面は NavigationStack を持たない**（シート側が持つ）。
/// 閉じるのも呼び出し側（`onComplete` / `onSkip` を受けてシートを閉じる）。
///
/// 画像は実機で撮った本物の画面を**7言語ぶん**用意してある（`tutorial_step1_ja` など）。
/// **説明文は画像に焼き込まない**ので、絵と文字の言語がいつも揃う。
/// 詳しくは docs/onboarding/CHANNEL_ADD_TUTORIAL.md。
struct ChannelTutorialView: View {
    /// 最後まで見て CTA を押した。
    let onComplete: () -> Void
    /// 途中でやめた／閉じた。何手順目だったかを渡す。
    let onSkip: (Int) -> Void

    @State private var index = 0

    /// 手順の数。iOS は**5つ**（共有したあと通知をタップして初めて一覧が開くため）。
    /// Android は通知が無く直接開くので4つ。数が違うのは本物の違い。
    private let stepCount = 5

    /// いまの表示言語に合う画像の名前。
    ///
    /// asset catalog は言語で切り替わらないので、`tutorial_step1_ja` のように
    /// **名前に言語を入れて**持ち、ここで組み立てる。用意が無い言語は英語に落とす。
    /// 文言は 35 言語あるが、画像はストアのスクショと同じく 7 言語のまま（2026-10-01 のユーザー判断）。
    private var imageLanguage: String { TutorialImageLanguage.current }

    private func imageName(for step: Int) -> String {
        "tutorial_step\(step)_\(imageLanguage)"
    }

    /// 書式に %@（アプリ名）が入るキーがあるので、String(format:) を通すために生キーで持つ。
    private func titleKey(_ step: Int) -> String {
        switch step {
        case 4: return "tutorial.step4.title.ios"   // 通知をタップ（iOS だけの手順）
        case 5: return "tutorial.step4.title"       // 一覧が開く
        default: return "tutorial.step\(step).title"
        }
    }

    /// 手順3・4は、共有の受け取り方が iOS だけ違うので別の文章を使う。
    /// 手順5（一覧が開く）は Android の手順4と同じ文章でよい。
    private func bodyKey(_ step: Int) -> String {
        switch step {
        case 3, 4: return "tutorial.step\(step).body.ios"
        case 5: return "tutorial.step4.body"
        default: return "tutorial.step\(step).body"
        }
    }

    private func imageA11yKey(_ step: Int) -> String {
        step == 5 ? "tutorial.step4.image.a11y" : "tutorial.step\(step).image.a11y"
    }

    private var isLast: Bool { index == stepCount - 1 }
    private var step: Int { index + 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(format: String(localized: "tutorial.progress.format"),
                            "\(step)", "\(stepCount)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(String(format: NSLocalizedString(titleKey(step), comment: ""),
                            AppInfo.displayName))
                    .font(.title3.bold())

                Text(String(format: NSLocalizedString(bodyKey(step), comment: ""),
                            AppInfo.displayName))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                stepImage

                controls

                // 例として他社のチャンネルを出している以上、関係が無いことは必ず書く。
                Text("tutorial.example.note")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text("tutorial.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isLast ? "tutorial.close" : "tutorial.skip") {
                    onSkip(index + 1)
                }
            }
        }
    }

    /// 画像。読み込めなくても案内は続けられる（説明は上の文章で完結している）。
    ///
    /// 言語ぶんの絵が無い端末では英語の絵が出る（[imageLanguage]）。それも無ければ
    /// 何も出さずに文章だけにする。**作り物の画面は描かない。**
    @ViewBuilder
    private var stepImage: some View {
        if let uiImage = UIImage(named: imageName(for: step)) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .accessibilityLabel(
                    Text(String(format: NSLocalizedString(imageA11yKey(step), comment: ""),
                                AppInfo.displayName)))
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if index > 0 {
                Button("tutorial.back") { index -= 1 }
                    .buttonStyle(.bordered)
            }
            if isLast {
                Button {
                    openYouTube()
                    onComplete()
                } label: {
                    Text("tutorial.cta").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    index += 1
                } label: {
                    Text("tutorial.next").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 4)
    }

    /// YouTube を開く。特定のチャンネルへは飛ばさない
    /// （例に出した NASA ではなく、**その人が見たいチャンネル**を探してもらう）。
    ///
    /// `https://www.youtube.com/` を渡すだけでよい。YouTube アプリが入っていれば
    /// iOS がユニバーサルリンクとしてアプリ側へ渡し、無ければ Safari で開く。
    private func openYouTube() {
        guard let url = URL(string: "https://www.youtube.com/") else { return }
        UIApplication.shared.open(url)
    }
}

/// 案内の画像（実機の画面・7言語）を選ぶための言語。チュートリアルと「YouTube の共有から追加する」で共用。
enum TutorialImageLanguage {
    /// 画像を用意している言語（ストアのスクショと同じ 7 言語）。
    static let available = ["en", "ja", "zh_Hans", "es", "de", "fr", "ko"]

    /// いまアプリが**実際に表示している言語**に合わせる（2026-10-06）。
    /// 以前は端末の言語（Locale.preferredLanguages）を見ていたため、iPhone の設定でアプリだけ
    /// 別の言語にしていると、文字は英語なのに画像は日本語、のようにずれていた。
    static var current: String {
        imageLanguage(forLocalization: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// アプリの表示言語（lproj の名前。"ja" / "zh-Hans" / "zh-Hant" / "pt-BR" など）→ 画像の言語。
    /// 用意が無い言語は英語に落とす。
    static func imageLanguage(forLocalization localization: String) -> String {
        let language = Locale(identifier: localization).language
        let code = language.languageCode?.identifier ?? "en"
        if code == "zh" {
            // 繁体字（zh-Hant / 台湾・香港・マカオ）に簡体字の画像を見せない。Android も同じく英語に落ちる。
            let traditional = language.script == .hanTraditional
                || ["TW", "HK", "MO"].contains(language.region?.identifier ?? "")
            return traditional ? "en" : "zh_Hans"
        }
        return available.contains(code) ? code : "en"
    }
}
