// ルート。プラグインの適用はモジュール側で行う。
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    // Firebase（Analytics）。app 側は google-services.json がある時だけ適用するので、
    // ここでは classpath に載せるだけにする。
    alias(libs.plugins.google.services) apply false
}
