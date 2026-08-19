package com.deskflowlabs.channeltimelineviewer.network

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

/**
 * API キーの「Android アプリ制限」を通すための自己申告。
 *
 * Google の API キーに Android アプリ制限（パッケージ名＋署名の SHA-1）をかけた場合、
 * リクエストに次の2つのヘッダーが必要になる。Google 製のクライアントライブラリは自動で付けるが、
 * 本アプリは素の HTTP で呼んでいるので**自分で付ける**必要がある。
 *
 *   X-Android-Package : パッケージ名
 *   X-Android-Cert    : 署名証明書の SHA-1（16進・大文字・区切りなし）
 *
 * 値は実行中のアプリ自身から取るので、デバッグ署名でも Play の署名でもそのまま通る。
 */
data class AndroidAppIdentity(val packageName: String, val signatureSha1: String) {

    companion object {
        /** 端末上の自分自身の情報から作る。取得できなければ null（ヘッダーを付けない）。 */
        fun from(context: Context): AndroidAppIdentity? {
            val certificate = signingCertificate(context) ?: return null
            val digest = MessageDigest.getInstance("SHA-1").digest(certificate)
            val hex = digest.joinToString("") { "%02X".format(it) }
            return AndroidAppIdentity(context.packageName, hex)
        }

        @Suppress("DEPRECATION")
        private fun signingCertificate(context: Context): ByteArray? = runCatching {
            val manager = context.packageManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = manager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES,
                )
                val signers = info.signingInfo?.apkContentsSigners
                signers?.firstOrNull()?.toByteArray()
            } else {
                val info = manager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
                info.signatures?.firstOrNull()?.toByteArray()
            }
        }.getOrNull()
    }
}
