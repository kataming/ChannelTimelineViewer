import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

/**
 * Google Analytics for Firebase の設定ファイル。
 * YouTube API キーと同じ扱いで、**リポジトリには入れない**。次のいずれかで置く。
 *   1. android/app/google-services.json（各自の端末用・gitignore 済み）
 *   2. CI は Secrets の GOOGLE_SERVICES_JSON_B64 から同じ場所へ復元する
 *
 * 無くてもビルドは通り、その場合 Firebase は初期化されない＝計測は完全に止まる
 * （ローカルの試し打ちビルドや、公開リポジトリの CI から本番の数字を汚さないため）。
 */
val firebaseConfigFile = file("google-services.json")
val hasFirebaseConfig = firebaseConfigFile.exists()

/**
 * 広告の確認用に、Play 版と**並べて**入れられるデバッグビルド（`-PadsPreview=true`）。
 * パッケージ名に `.adstest` を付けた別アプリになるので、端末の Play 版と保存データには触れない。
 * Firebase は使わない（google-services.json にこのパッケージが無いため）。Pro の購入も引き継がれない。
 */
val adsPreview = (findProperty("adsPreview") as String?) == "true"

if (hasFirebaseConfig && !adsPreview) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
}

/**
 * YouTube Data API v3 のキー。iOS 版の `Resources/Config.plist` と同じ扱いで、
 * **リポジトリには入れない**。次のいずれかで渡す。
 *   1. android/local.properties に `YOUTUBE_API_KEY=...`（各自の端末用・gitignore 済み）
 *   2. 環境変数 YOUTUBE_API_KEY（CI 用）
 * 未設定でもビルドは通り、アプリ側で「APIキーが設定されていません」と表示する。
 */
fun youtubeApiKey(): String {
    val local = rootProject.file("local.properties")
    if (local.exists()) {
        val properties = Properties().apply { local.inputStream().use { load(it) } }
        val value = properties.getProperty("YOUTUBE_API_KEY")
        if (!value.isNullOrBlank()) return value
    }
    return System.getenv("YOUTUBE_API_KEY").orEmpty()
}

/**
 * Google AdMob の本番 ID（アプリ ID・広告ユニット ID）。
 * **秘密情報ではない**（APK に入って誰でも読める値）ので、次のどこに書いてもよい。
 *   1. 環境変数（CI 用）
 *   2. android/local.properties（各自の端末用）
 *   3. android/gradle.properties（リポジトリに入れて共有する場合）
 * 3つとも揃っていないリリースビルドは**広告を一切出さない**（SDK を初期化せず、リクエストもしない）。
 * デバッグビルドは常に Google 公式のテスト広告を使う（本番 ID があっても使わない）。
 */
fun admobSetting(name: String): String {
    System.getenv(name)?.takeIf { it.isNotBlank() }?.let { return it.trim() }
    val local = rootProject.file("local.properties")
    if (local.exists()) {
        val properties = Properties().apply { local.inputStream().use { load(it) } }
        properties.getProperty(name)?.takeIf { it.isNotBlank() }?.let { return it.trim() }
    }
    return (findProperty(name) as String?).orEmpty().trim()
}

/** Google 公式のテスト用アプリ ID（Android）。本番 ID が無いときの置き場所にも使う。 */
val admobTestAppId = "ca-app-pub-3940256099942544~3347511713"

/**
 * アップロード鍵の場所。次の順で探し、無ければ null（＝署名なしのビルドになる）。
 *   1. 環境変数 ANDROID_KEYSTORE_PATH（CI が base64 から復元した鍵）
 *   2. android/keystore/upload.jks（各自の端末用・gitignore 済み）
 */
fun uploadKeystore(): File? {
    System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }?.let { path ->
        val file = File(path)
        if (file.exists()) return file
    }
    val local = rootProject.file("keystore/upload.jks")
    return if (local.exists()) local else null
}

/**
 * アップロード鍵の合言葉。CI は環境変数、各自の端末は android/keystore/password.txt から読む
 * （どちらもリポジトリには入らない）。
 */
fun uploadKeystorePassword(): String? {
    System.getenv("ANDROID_KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }?.let { return it }
    val local = rootProject.file("keystore/password.txt")
    return if (local.exists()) local.readText().trim().ifBlank { null } else null
}

android {
    namespace = "com.deskflowlabs.channeltimelineviewer"
    // Google Play の対象APIレベル要件（2026-08-31 期限）に合わせて 36（Android 16）。
    compileSdk = 36

    signingConfigs {
        // デバッグ用の署名鍵をリポジトリに固定で置く（秘密情報ではない）。
        // これで **どの端末・CI でビルドしても署名の SHA-1 が変わらない**ため、
        // YouTube API キーの「Android アプリ制限（パッケージ名＋SHA-1）」が効かせられる。
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }

        // Google Play へ出すための署名（アップロード鍵）。鍵と合言葉は CI の Secrets から渡す。
        // 鍵そのものはリポジトリに入れない（android/keystore/ は .gitignore 済み）。
        val keystore = uploadKeystore()
        val password = uploadKeystorePassword()
        if (keystore != null && password != null) {
            create("release") {
                storeFile = keystore
                storePassword = password
                keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "upload"
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: password
            }
        }
    }

    defaultConfig {
        applicationId = "com.deskflowlabs.channeltimelineviewer"
        minSdk = 26
        targetSdk = 36
        // Play は versionCode の重複を拒否するので、CI からは実行番号を渡す。
        versionCode = (System.getenv("ANDROID_VERSION_CODE") ?: "1").toInt()
        versionName = System.getenv("ANDROID_VERSION_NAME") ?: "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "YOUTUBE_API_KEY", "\"${youtubeApiKey()}\"")
        // API キーの「Android アプリ制限」に申告するパッケージ名（network/AndroidAppIdentity.kt）。
        // 広告確認用の別アプリ（adsPreview）でも、登録してある本来の名前で申告する。
        buildConfigField("String", "API_IDENTITY_PACKAGE", "\"com.deskflowlabs.channeltimelineviewer\"")
        manifestPlaceholders["appLabel"] = "@string/app_name"
        // 再生に使う中継ページ（iOS 版と共通。GitHub Pages で配信している）
        buildConfigField(
            "String",
            "PLAYER_RELAY_URL",
            "\"https://kataming.github.io/ChannelTimelineViewer/player.html\"",
        )
        // AdMob の本番広告ユニット。空ならリリースでも広告を出さない（ads/AdsConfig.kt）。
        buildConfigField("String", "ADMOB_BANNER_UNIT_ID", "\"${admobSetting("ADMOB_BANNER_UNIT_ID")}\"")
        buildConfigField("String", "ADMOB_MREC_UNIT_ID", "\"${admobSetting("ADMOB_MREC_UNIT_ID")}\"")
        // AndroidManifest の APPLICATION_ID。SDK は起動時にこれが無いと落ちるので、
        // 本番 ID が無いときはテスト用の ID を置く（その場合は広告を読み込まないので表示もされない）。
        manifestPlaceholders["admobAppId"] = admobSetting("ADMOB_APP_ID").ifBlank { admobTestAppId }
        buildConfigField(
            "String",
            "PRIVACY_POLICY_URL",
            "\"https://channeltimeline.jewelrysunflower.com/en/privacy/\"",
        )
    }

    buildTypes {
        debug {
            // 開発中は本番 ID があってもテスト広告だけを使う（自分で本番広告を表示・クリックしない）。
            manifestPlaceholders["admobAppId"] = admobTestAppId
            if (adsPreview) {
                applicationIdSuffix = ".adstest"
                versionNameSuffix = "-adstest"
                manifestPlaceholders["appLabel"] = "CTV 広告確認"
            }
        }
        release {
            // Play Console の「アプリの最適化がしきい値を下回っています（難読化 0%）」対策。
            // ⚠️ 難読化で **WebView の JavaScript ブリッジが壊れると再生と自動送りが止まる**。
            //    残す指定は proguard-rules.pro にあるので、消さないこと。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

dependencies {
    // Play Billing（→ play-services-base）が androidx.fragment 1.1.0（2019年）を連れてくる。
    // このアプリは Fragment を使っていないが、Play Console が「古い SDK バージョン」として
    // 警告するため版だけ引き上げる。constraints なので依存を新たに足すわけではない。
    constraints {
        implementation(libs.androidx.fragment) {
            because("Play Console の「古い SDK バージョン」警告（billing → play-services-base 経由の 1.1.0）")
        }
    }

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.coil.compose)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.billing)

    // Google Analytics for Firebase（Android 版のみ）。
    // google-services.json が無いビルドでも依存だけは入る（実行時に初期化されないだけ）。
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.analytics)

    // Google AdMob（無料版のみ表示）と、広告の同意フォーム（UMP）。
    // 初期化・読み込みは ads/ 配下にまとめてあり、Pro では SDK を初期化しない。
    implementation(libs.play.services.ads)
    implementation(libs.user.messaging.platform)

    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
}
