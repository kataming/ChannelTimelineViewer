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
/// 中央の文字は、**文字の高さのぶんだけ下地を敷いて記号の線を切り抜いてから**重ねている。
/// そのまま重ねると矢印と文字がぶつかって読めなくなる（`tools/UIPreview` で比較して決定）。
struct RepeatModeBadge: View {
    let mode: RepeatMode
    var size: CGFloat = 26
    /// 矢印の上下幅（記号を縦に伸ばす倍率）。中央の文字まわりの余裕を調整する。
    var verticalStretch: CGFloat = 1.0
    /// 矢印の左右幅（記号の大きさ自体の倍率）。
    var glyphScale: CGFloat = 1.0

    private var cornerRadius: CGFloat { size * 0.27 }
    /// 記号は横に広い（幅は文字サイズの約1.4倍）ので、枠に収まるよう小さめにする。
    private var glyphSize: CGFloat { size * 0.46 * glyphScale }
    private var labelSize: CGFloat { size * 0.26 }
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
            .font(.system(size: glyphSize, weight: .medium))
            .foregroundStyle(inkColor)
            .scaleEffect(x: 1, y: verticalStretch)
            .overlay {
                if let label = mode.centerLabel {
                    Text(label)
                        .font(.system(size: labelSize, weight: .heavy))
                        .foregroundStyle(inkColor)
                        .padding(.horizontal, size * 0.03)
                        .frame(height: labelSize * 0.9)
                        .background(fillColor)   // 矢印の線を切り抜く
                }
            }
    }
}
