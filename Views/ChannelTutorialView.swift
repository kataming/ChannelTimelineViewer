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
/// 画像は実機で撮った本物の画面。**説明文は画像に焼き込まず**ここでローカライズして出すので、
/// 同じ画像を7言語で使い回せる（docs/onboarding/CHANNEL_ADD_TUTORIAL.md）。
struct ChannelTutorialView: View {
    /// 最後まで見て CTA を押した。
    let onComplete: () -> Void
    /// 途中でやめた／閉じた。何手順目だったかを渡す。
    let onSkip: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    /// 1手順ぶんの中身。
    private struct Step {
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        /// アセット名。iOS の共有シートだけは本物を撮れていないので nil。
        let image: String?
        let imageDescription: LocalizedStringKey
    }

    private var steps: [Step] {
        [
            Step(title: "tutorial.step1.title",
                 body: "tutorial.step1.body",
                 image: "tutorial_youtube_channel",
                 imageDescription: "tutorial.step1.image.a11y"),
            Step(title: "tutorial.step2.title",
                 body: "tutorial.step2.body",
                 image: "tutorial_youtube_share",
                 imageDescription: "tutorial.step2.image.a11y"),
            // iOS の共有シートは端末ごとに並びが変わるうえ、本物を撮れていない。
            // 作り物の共有シートを描くのは誤解のもとなので、絵は出さずに文章で説明する。
            Step(title: "tutorial.step3.title",
                 body: "tutorial.step3.body.ios",
                 image: nil,
                 imageDescription: "tutorial.step3.image.a11y"),
        ]
    }

    private var step: Step { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(format: String(localized: "tutorial.progress.format"),
                                "\(index + 1)", "\(steps.count)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(String(format: NSLocalizedString(titleKey, comment: ""),
                                AppInfo.displayName))
                        .font(.title3.bold())

                    Text(String(format: NSLocalizedString(bodyKey, comment: ""),
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

    // 書式に %@（アプリ名）が入るキーがあるので、String(format:) を通すために生キーで持つ。
    private var titleKey: String {
        ["tutorial.step1.title", "tutorial.step2.title", "tutorial.step3.title"][index]
    }

    private var bodyKey: String {
        ["tutorial.step1.body", "tutorial.step2.body", "tutorial.step3.body.ios"][index]
    }

    /// 画像。読み込めなくても案内は続けられる（説明は上の文章で完結している）。
    @ViewBuilder
    private var stepImage: some View {
        if let name = step.image, let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .accessibilityLabel(
                    Text(String(format: NSLocalizedString("tutorial.step\(index + 1).image.a11y",
                                                          comment: ""),
                                AppInfo.displayName)))
        } else {
            // 本物の共有シートを載せられない手順。作り物の画面は描かず、
            // 「このアプリを選ぶ」ことだけを自分のUIで示す。
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label(AppInfo.displayName, systemImage: "list.bullet.rectangle.portrait")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(String(format: NSLocalizedString("tutorial.step3.image.a11y", comment: ""),
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
