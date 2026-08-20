package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.deskflowlabs.channeltimelineviewer.data.RepeatMode

/**
 * リピートバッジの見た目を確認するためだけの画面（**デバッグビルド専用**）。
 *
 * ビルド前に形を確かめる手段が無いと、実機に入れてからでないと崩れに気づけない。
 * iOS 版で `tools/UIPreview` を用意しているのと同じ狙いで、こちらは端末上に並べて見る。
 *
 * 開き方:
 *   adb shell am start -n com.deskflowlabs.channeltimelineviewer/.MainActivity --es preview badge
 */
@Composable
fun BadgePreviewScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text("リピートバッジ確認用", style = MaterialTheme.typography.titleMedium)

        BadgeRow("実寸（26dp・ツールバー）", 26.dp)
        BadgeRow("拡大（56dp）", 56.dp)
        // 画面幅に収まる範囲にする（3つ並べるので 1つあたり 100dp が上限の目安）。
        BadgeRow("拡大（96dp）", 96.dp)

        // 濃い背景でも枠線が見えるか（ダークテーマ相当）
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF101418))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("濃い背景", color = Color.White)
            CompositionLocalProvider(LocalContentColor provides Color.White) {
                Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    RepeatMode.entries.forEach { mode ->
                        RepeatModeBadge(mode = mode, size = 64.dp)
                    }
                }
            }
        }
    }
}

@Composable
private fun BadgeRow(title: String, size: Dp) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge)
        Row(
            horizontalArrangement = Arrangement.spacedBy(24.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RepeatMode.entries.forEach { mode ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    RepeatModeBadge(mode = mode, size = size)
                    Text(mode.name, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}
