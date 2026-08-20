package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/**
 * 日付の書式は「アプリの表示言語」に合わせる。
 *
 * `DateFormat.getDateInstance()` は端末の言語をそのまま使うため、
 * Android 13 以降の「アプリごとの言語」やスクショ撮影用の言語切り替えでは
 * 文字は英語なのに日付だけ日本語、といった食い違いが起きる。
 */
@Composable
fun rememberAppLocale(): Locale {
    val configuration = LocalConfiguration.current
    return remember(configuration) {
        @Suppress("DEPRECATION")
        configuration.locales.get(0) ?: Locale.getDefault()
    }
}

/** 「2011年6月1日」「June 1, 2011」のような日付表記。 */
@Composable
fun formatDate(epochSeconds: Long, style: Int = DateFormat.MEDIUM): String {
    val locale = rememberAppLocale()
    val formatter = remember(locale, style) { DateFormat.getDateInstance(style, locale) }
    return formatter.format(Date(epochSeconds * 1000))
}

/** 日付＋時刻（最終更新の表示など）。 */
@Composable
fun formatDateTime(epochSeconds: Long): String {
    val locale = rememberAppLocale()
    val formatter = remember(locale) {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale)
    }
    return formatter.format(Date(epochSeconds * 1000))
}
