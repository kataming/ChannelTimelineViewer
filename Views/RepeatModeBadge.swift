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
/// ## 数値の決め方
/// 見本画像（`yajirushi.png`）の比率に合わせてある。
/// バッジの大きさに対して、線の太さ 約0.06 / 記号の縦の広がり 約0.64 / 横の広がり 約0.68。
/// 記号を拡大すると線まで太くなるため、線は細め（light）にしたうえで記号を大きくし、
/// さらに**記号を上下half に分けて離す**ことで中央（文字が入るところ）の空きを作っている。
/// 数値を変えたときは `tools/UIPreview` で描き出して見比べること。
struct RepeatModeBadge: View {
    let mode: RepeatMode
    var size: CGFloat = 26
    /// 上下の矢印を離す量（バッジの大きさに対する割合）。線の太さは変わらない。
    var arrowGap: CGFloat = 0.06
    /// 記号の大きさ（バッジに対する割合）。
    var glyphRatio: CGFloat = 0.68
    /// 記号の線の太さ。
    var glyphWeight: Font.Weight = .light
    /// 中央の文字の大きさ（バッジに対する割合）。
    var labelRatio: CGFloat = 0.26

    private var cornerRadius: CGFloat { size * 0.27 }
    /// 記号は横に広い（幅は文字サイズの約1.4倍）ので、枠に収まるよう小さめにする。
    private var glyphSize: CGFloat { size * glyphRatio }
    private var labelSize: CGFloat { size * labelRatio }
    private var fillColor: Color { mode.isActive ? .green : .clear }
    private var inkColor: Color { mode.isActive ? .black : .primary }
    /// 上下それぞれをずらす量。
    private var halfGap: CGFloat { size * arrowGap / 2 }

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

    private var symbol: some View {
        Image(systemName: "repeat")
            .font(.system(size: glyphSize, weight: glyphWeight))
            .foregroundStyle(inkColor)
    }

    @ViewBuilder
    private var glyph: some View {
        ZStack {
            // 上半分（右向きの矢印）を上へ、下半分（左向きの矢印）を下へずらす。
            symbol
                .mask(alignment: .top) { topHalfMask }
                .offset(y: -halfGap)
            symbol
                .mask(alignment: .bottom) { bottomHalfMask }
                .offset(y: halfGap)

            if let label = mode.centerLabel {
                Text(label)
                    .font(.system(size: labelSize, weight: .heavy))
                    .foregroundStyle(inkColor)
            }
        }
    }

    private var topHalfMask: some View {
        VStack(spacing: 0) {
            Rectangle()
            Color.clear
        }
    }

    private var bottomHalfMask: some View {
        VStack(spacing: 0) {
            Color.clear
            Rectangle()
        }
    }
}
