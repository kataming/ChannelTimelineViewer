import SwiftUI

/// リピートの状態を表す角丸バッジ。
///
/// - オフ: 枠線だけ（中は透明）＋リピート記号
/// - 1本: 緑地の記号の中央に「1」
/// - 全体: 緑地の記号の中央に「ALL」
///
/// ## 形は見本（yajirushi.png）を計測して写している
/// 画素を1列ずつ測った結果（バッジの大きさに対する比）:
///   - 横棒の太さ 0.043
///   - 上の矢印  x 0.162〜0.573 / y 0.179〜0.385
///   - 中央の文字 y 0.410〜0.607（高さ 0.197）
///   - 下の矢印  上の矢印を中心まわりに180度回転したもの
/// SF Symbols を加工すると継ぎ目の点や欠けが出るため、Path で直接描いている。
struct RepeatModeBadge: View {
    let mode: RepeatMode
    var size: CGFloat = 26

    private var cornerRadius: CGFloat { size * 0.27 }
    /// 横棒の太さ（見本の計測値）。
    private var lineWidth: CGFloat { size * 0.043 }
    private var labelSize: CGFloat { size * 0.27 }
    private var fillColor: Color { mode.isActive ? .green : .clear }
    private var inkColor: Color { mode.isActive ? .black : .primary }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(mode.isActive ? Color.clear : Color.primary,
                              lineWidth: max(1, size * 0.07))

            arrow                                   // 上（右向き・左寄り）
            arrow.rotationEffect(.degrees(180))     // 下（左向き・右寄り）

            if let label = mode.centerLabel {
                Text(label)
                    .font(.system(size: labelSize, weight: .heavy))
                    .foregroundStyle(inkColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: size * 0.70)
            }
        }
        .frame(width: size, height: size)
    }

    private var arrow: some View {
        ZStack {
            RepeatArrowShaft()
                .stroke(inkColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            RepeatArrowHead()
                .fill(inkColor)
        }
    }
}

/// 矢印の軸。左端で立ち上がって右へ伸びる（見本の座標）。
private struct RepeatArrowShaft: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.190, 0.372))                                  // 下端
        path.addLine(to: p(0.190, 0.300))
        path.addQuadCurve(to: p(0.232, 0.265), control: p(0.190, 0.265)) // 角
        path.addLine(to: p(0.455, 0.265))                                // 横棒
        return path
    }
}

/// 矢じり（軸の先の三角形）。
private struct RepeatArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.573, 0.265))      // 先端
        path.addLine(to: p(0.452, 0.179))
        path.addLine(to: p(0.452, 0.351))
        path.closeSubpath()
        return path
    }
}
