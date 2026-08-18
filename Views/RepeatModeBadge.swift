import SwiftUI

/// リピートの状態を表す角丸バッジ。
///
/// - オフ: 枠線だけ（中は透明）＋リピート記号
/// - 1本: 緑地のリピート記号の中央に「1」
/// - 全体: 緑地のリピート記号の中央に「ALL」
///
/// ## 矢印は自前で描いている
/// SF Symbols の `repeat` を切り貼りすると、継ぎ目の点が残ったり、
/// 文字の下地で矢印が消えたりする。見本（`yajirushi.png`）どおりの形にするため、
/// **矢印は Path で描き、中央は最初から空けてある**（切り抜きも分割もしない）。
/// 上の矢印を描き、それを180度回転させたものを下の矢印にしているので左右対称になる。
struct RepeatModeBadge: View {
    let mode: RepeatMode
    var size: CGFloat = 26

    private var cornerRadius: CGFloat { size * 0.27 }
    private var lineWidth: CGFloat { size * 0.075 }
    private var labelSize: CGFloat { size * 0.30 }
    private var fillColor: Color { mode.isActive ? .green : .clear }
    private var inkColor: Color { mode.isActive ? .black : .primary }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(mode.isActive ? Color.clear : Color.primary,
                              lineWidth: max(1, size * 0.07))

            arrow                                   // 上（右向き）
            arrow.rotationEffect(.degrees(180))     // 下（左向き）

            if let label = mode.centerLabel {
                Text(label)
                    .font(.system(size: labelSize, weight: .heavy))
                    .foregroundStyle(inkColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: size * 0.62)
            }
        }
        .frame(width: size, height: size)
    }

    /// 上側の矢印（軸＋矢じり）。
    private var arrow: some View {
        ZStack {
            RepeatArrowShaft()
                .stroke(inkColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            RepeatArrowHead()
                .fill(inkColor)
        }
    }
}

/// 矢印の軸。左下から立ち上がって右へ伸びる。
private struct RepeatArrowShaft: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        var path = Path()
        path.move(to: p(0.15, 0.50))
        path.addLine(to: p(0.15, 0.36))
        path.addQuadCurve(to: p(0.26, 0.26), control: p(0.15, 0.26))
        path.addLine(to: p(0.64, 0.26))
        return path
    }
}

/// 矢じり（軸の先の三角形）。
private struct RepeatArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        var path = Path()
        path.move(to: p(0.87, 0.26))     // 先端
        path.addLine(to: p(0.63, 0.13))
        path.addLine(to: p(0.63, 0.39))
        path.closeSubpath()
        return path
    }
}
