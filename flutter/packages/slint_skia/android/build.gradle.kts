group = "dev.slint.slint_skia"
version = "1.0"

// No buildscript classpath: the Android Gradle plugin comes from the app that
// includes this plugin (a Flutter app declares it in settings.gradle.kts), so
// this file pins no AGP version of its own. The Flutter embedding is added as
// a compile-only dependency by the Flutter Gradle plugin.
plugins {
    id("com.android.library")
}

android {
    namespace = "dev.slint.slint_skia"
    // Flutter's defaults (FlutterExtension); SurfaceProducer needs nothing newer.
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
