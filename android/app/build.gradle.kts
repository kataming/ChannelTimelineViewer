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
if (hasFirebaseConfig) {
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
        // 再生に使う中継ページ（iOS 版と共通。GitHub Pages で配信している）
        buildConfigField(
            "String",
            "PLAYER_RELAY_URL",
            "\"https://kataming.github.io/ChannelTimelineViewer/player.html\"",
        )
        buildConfigField(
            "String",
            "PRIVACY_POLICY_URL",
            "\"https://channeltimeline.jewelrysunflower.com/en/privacy/\"",
        )
    }

    buildTypes {
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

    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
}
