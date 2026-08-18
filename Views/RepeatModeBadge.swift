import SwiftUI

/// リピートの状態を表す角丸バッジ。
///
/// - オフ: 枠線だけ（中は透明）
/// - 1本: 緑の塗りつぶし＋「1」入りのリピート記号
/// - 全体: 緑の塗りつぶし＋「ALL」入りのリピート記号
///
/// 画像ではなく描画で作っているので、拡大しても滲まず、
/// ライト/ダークどちらでも枠線がはっきり見える。
struct RepeatModeBadge: View {
    let mode: RepeatMode
    var size: CGFloat = 22

    /// リピート記号の線の太さ。太いと「ALL」や「1」と干渉して潰れるので細めにする。
    var glyphWeight: Font.Weight = .regular

    private var cornerRadius: CGFloat { size * 0.27 }
    private var glyphSize: CGFloat { size * 0.62 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(mode.isActive ? Color.green : Color.clear)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(mode.isActive ? Color.clear : Color.primary,
                              lineWidth: max(1, size * 0.07))
            glyph
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        let color: Color = mode.isActive ? .black : .primary
        Image(systemName: mode.glyphSymbolName)
            .font(.system(size: glyphSize, weight: glyphWeight))
            .foregroundStyle(color)
            .overlay {
                if mode.showsAllLabel {
                    // 「ALL」はリピート記号の中央（矢印の間）に重ねる。
                    Text("ALL")
                        .font(.system(size: size * 0.24, weight: .heavy))
                        .foregroundStyle(color)
                }
            }
    }
}
