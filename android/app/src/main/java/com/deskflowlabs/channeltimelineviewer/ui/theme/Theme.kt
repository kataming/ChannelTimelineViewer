package com.deskflowlabs.channeltimelineviewer.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// 視聴済み＝緑・スキップ＝オレンジは iOS 版と揃える（同じ意味の色を使う）。
val WatchedGreen = Color(0xFF2E7D32)
val SkippedOrange = Color(0xFFEF6C00)

private val LightColors = lightColorScheme(primary = Color(0xFF17914A))
private val DarkColors = darkColorScheme(primary = Color(0xFF35C46A))

@Composable
fun ChannelTimelineTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val colors = when {
        // Android 12 以降は端末の壁紙に合わせた配色（Material You）を使う。
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> DarkColors
        else -> LightColors
    }
    MaterialTheme(colorScheme = colors, content = content)
}
