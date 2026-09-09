# リリースビルドの難読化・圧縮（R8）の設定。
# Play Console の「アプリの最適化がしきい値を下回っています（難読化 0%）」への対応で
# 2026-09-09 に有効化した。ここを消すと再生が壊れるものがあるので、内容は必ず読むこと。

# ---------------------------------------------------------------------------
# ⚠️ 最重要: WebView の JavaScript ブリッジ
# ---------------------------------------------------------------------------
# 中継ページ（docs/player.html）は `window.ytAndroid.onState(...)` のように
# **名前で** アプリ側のメソッドを呼ぶ。難読化でメソッド名が変わると呼び出しが届かず、
# 再生状態の通知・再生位置の保存・自動送り（nearEnd）がすべて止まる。
# しかも例外は出ず「なぜか次に進まない」という形で表面化するので、必ず残す。
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
# ブリッジのクラス自体も、addJavascriptInterface に渡す形のまま残す。
-keep class com.deskflowlabs.channeltimelineviewer.ui.**$* {
    @android.webkit.JavascriptInterface <methods>;
}

# ---------------------------------------------------------------------------
# kotlinx.serialization（端末内に保存している視聴済み・進捗・メモなどの読み書き）
# ---------------------------------------------------------------------------
# ライブラリ側にも consumer ルールがあるが、壊れると**利用者の記録が読めなくなる**ため
# 公式が案内している指定を明示しておく。
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}
-if @kotlinx.serialization.Serializable class ** {
    static **$* *;
}
-keepclassmembers class <2>$<3> {
    kotlinx.serialization.KSerializer serializer(...);
}

# 保存するデータのモデル。@Serializable が付いたものをまとめて残す。
-keep,includedescriptorclasses class com.deskflowlabs.channeltimelineviewer.model.** { *; }

# ---------------------------------------------------------------------------
# 覚え書き
# ---------------------------------------------------------------------------
# - Jetpack Compose / OkHttp / Play Billing / Firebase は、各ライブラリが同梱している
#   consumer ルールで足りるため、ここには書かない。
# - アプリ側のコードは反射を使っていない（Class.forName / getIdentifier なし）ので、
#   これ以上の keep は不要。反射を使い始めたらここに追記すること。
# - 難読化後の対応表は app/build/outputs/mapping/release/mapping.txt に出る。
#   Play Console に アップロードすると、クラッシュの行番号が読めるようになる。
