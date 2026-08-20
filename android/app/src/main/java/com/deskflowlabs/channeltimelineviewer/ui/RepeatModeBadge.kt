package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.deskflowlabs.channeltimelineviewer.data.RepeatMode
import com.deskflowlabs.channeltimelineviewer.ui.theme.WatchedGreen

/**
 * リピートの状態を表す角丸バッジ。iOS 版 `Views/RepeatModeBadge.swift` と**同じ形**を描く。
 *
 * - オフ: 枠線だけ（中は透明）＋リピート記号
 * - 1本: 緑地の記号の中央に「1」
 * - 全体: 緑地の記号の中央に「ALL」
 *
 * ## 形は見本を計測した値をそのまま使う（iOS と共通）
 *   - 横棒の太さ 0.046 / 横棒の中心 y 0.246
 *   - 左の縦棒（フック）: 中心 x 0.201、下端 y 0.435 まで伸びる
 *   - 矢じり: 付け根 x 0.470、先端 x 0.590、半分の高さ 0.076
 *   - 中央の文字: 大きさ 0.25
 *   - 下の矢印は、上の矢印を中心まわりに180度回転したもの
 *
 * 既製アイコンを加工すると継ぎ目や欠けが出るため、iOS と同じく自前で描いている。
 * 数値を変えたときは、デバッグビルドのバッジ確認画面（`--es preview badge`）で見比べること。
 */
@Composable
fun RepeatModeBadge(mode: RepeatMode, size: Dp = 26.dp) {
    val active = mode.isActive
    val outline = LocalContentColor.current
    // 緑地のときは白抜き。Android は画面が白基調なので、黒よりこちらの方が離れて見ても分かる。
    val ink = if (active) Color.White else outline

    Box(modifier = Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.size(size)) {
            val side = this.size.minDimension
            val corner = CornerRadius(side * 0.27f)

            if (active) {
                drawRoundRect(color = WatchedGreen, cornerRadius = corner)
            } else {
                // SwiftUI の strokeBorder と同じ「内側に描く枠線」にするため、線の太さの半分だけ内側へ。
                val stroke = maxOf(1f, side * 0.07f)
                drawRoundRect(
                    color = outline,
                    topLeft = Offset(stroke / 2, stroke / 2),
                    size = Size(side - stroke, side - stroke),
                    cornerRadius = CornerRadius(side * 0.27f - stroke / 2),
                    style = Stroke(width = stroke),
                )
            }

            drawRepeatArrow(side, ink)                                   // 上（右向き・左寄り）
            rotate(180f) { drawRepeatArrow(side, ink) }                  // 下（左向き・右寄り）
        }

        mode.centerLabel?.let { label ->
            val fontSize = with(LocalDensity.current) { (size * 0.25f).toSp() }
            Text(
                text = label,
                color = ink,
                fontSize = fontSize,
                fontWeight = FontWeight.Black,
                maxLines = 1,
                textAlign = TextAlign.Center,
                modifier = Modifier.size(width = size * 0.70f, height = size * 0.40f),
            )
        }
    }
}

/** 矢印1本（軸＋矢じり）。左端で立ち上がって右へ伸びる。 */
private fun DrawScope.drawRepeatArrow(side: Float, color: Color) {
    fun x(value: Float) = value * side
    fun y(value: Float) = value * side

    val shaft = Path().apply {
        moveTo(x(0.201f), y(0.435f))                                     // 縦棒の下端
        lineTo(x(0.201f), y(0.290f))
        quadraticBezierTo(x(0.201f), y(0.246f), x(0.245f), y(0.246f))    // 角
        lineTo(x(0.470f), y(0.246f))                                     // 横棒
    }
    drawPath(
        path = shaft,
        color = color,
        style = Stroke(width = side * 0.046f, cap = androidx.compose.ui.graphics.StrokeCap.Round),
    )

    val head = Path().apply {
        moveTo(x(0.590f), y(0.246f))                                     // 先端
        lineTo(x(0.468f), y(0.170f))
        lineTo(x(0.468f), y(0.322f))
        close()
    }
    drawPath(path = head, color = color)
}
