import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
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

android {
    namespace = "com.deskflowlabs.channeltimelineviewer"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.deskflowlabs.channeltimelineviewer"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

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
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
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

    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
}
