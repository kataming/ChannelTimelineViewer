import SwiftUI
import UIKit

/// 「YouTube のチャンネルをこのアプリに追加する方法」の案内。
///
/// なぜ要るか: 追加の入口が「YouTube の共有 → このアプリを選ぶ」で、
/// 初めての人には見つけられない。入れた直後に何もできずに終わるのを防ぐ。
///
/// 出すのは**初めてチャンネルを追加しようとしたとき**だけ（起動のたびには出さない）。
/// あとは「ⓘ このアプリについて」からいつでも開き直せる。
///
/// 画像は実機で撮った本物の画面を**7言語ぶん**用意してある（`tutorial_step1_ja` など）。
/// **説明文は画像に焼き込まない**ので、絵と文字の言語がいつも揃う。
/// 詳しくは docs/onboarding/CHANNEL_ADD_TUTORIAL.md。
struct ChannelTutorialView: View {
    /// 最後まで見て CTA を押した。
    let onComplete: () -> Void
    /// 途中でやめた／閉じた。何手順目だったかを渡す。
    let onSkip: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    /// 手順の数。画像も文言も 1〜4 で揃えてある。
    private let stepCount = 4

    /// いまの表示言語に合う画像の名前。
    ///
    /// asset catalog は言語で切り替わらないので、`tutorial_step1_ja` のように
    /// **名前に言語を入れて**持ち、ここで組み立てる。用意が無い言語は英語に落とす
    /// （アプリの文言も同じ規則で英語に落ちるので、絵と文字がちぐはぐにならない）。
    private var imageLanguage: String {
        let available = ["en", "ja", "zh_Hans", "es", "de", "fr", "ko"]
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        if code == "zh" { return available.contains("zh_Hans") ? "zh_Hans" : "en" }
        return available.contains(code) ? code : "en"
    }

    private func imageName(for step: Int) -> String {
        "tutorial_step\(step)_\(imageLanguage)"
    }

    /// 書式に %@（アプリ名）が入るキーがあるので、String(format:) を通すために生キーで持つ。
    private func titleKey(_ step: Int) -> String { "tutorial.step\(step).title" }

    /// 手順3と4は、共有の受け取り方が iOS だけ違うので別の文章を使う。
    private func bodyKey(_ step: Int) -> String {
        step >= 3 ? "tutorial.step\(step).body.ios" : "tutorial.step\(step).body"
    }

    private func imageA11yKey(_ step: Int) -> String { "tutorial.step\(step).image.a11y" }

    private var isLast: Bool { index == stepCount - 1 }
    private var step: Int { index + 1 }

    var body: some View {
        NavigationStack {
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
                        dismiss()
                    }
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
                    dismiss()
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
