import SwiftUI

/// リピートの状態を表す角丸バッジ。
///
/// - オフ: 枠線だけ（中は透明）＋リピート記号
/// - 1本: 緑地のリピート記号の中央に「1」
/// - 全体: 緑地のリピート記号の中央に「ALL」
///
/// 画像ではなく描画で作っているので、拡大しても滲まず、
/// ライト/ダークどちらでも枠線がはっきり見える。
///
/// 中央の文字は、記号の線を**同じ色で塗って切り抜いてから**重ねている。
/// そうしないと矢印と文字が重なって潰れる。
struct RepeatModeBadge: View {
    let mode: RepeatMode
    var size: CGFloat = 22

    /// リピート記号の線の太さ。
    var glyphWeight: Font.Weight = .medium

    private var cornerRadius: CGFloat { size * 0.27 }
    /// 記号は横に広い（幅は文字サイズの約1.4倍）ので、枠に収まるよう小さめにする。
    private var glyphSize: CGFloat { size * 0.46 }
    private var labelSize: CGFloat { size * 0.26 }
    /// 塗りつぶし色（中央の文字の下地にも使い、記号の線を切り抜く）。
    private var fillColor: Color { mode.isActive ? .green : .clear }
    private var inkColor: Color { mode.isActive ? .black : .primary }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(mode.isActive ? Color.clear : Color.primary,
                              lineWidth: max(1, size * 0.07))
            glyph
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        Image(systemName: "repeat")
            .font(.system(size: glyphSize, weight: glyphWeight))
            .foregroundStyle(inkColor)
            .overlay {
                if let label = mode.centerLabel {
                    Text(label)
                        .font(.system(size: labelSize, weight: .heavy))
                        .foregroundStyle(inkColor)
                        .padding(.horizontal, size * 0.04)
                        .background(fillColor)   // 矢印の線を切り抜く
                }
            }
    }
}
