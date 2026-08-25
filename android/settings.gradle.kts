pluginManagement {
    // local.properties do Flutter tool/máy phát triển cung cấp đường dẫn SDK; fail sớm
    // nếu thiếu để Gradle không tiếp tục với một cấu hình mơ hồ.
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    // Nạp Flutter Gradle plugin trực tiếp từ SDK đang được dự án sử dụng.
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // Loader kích hoạt plugin Flutter; plugin Android/Kotlin chỉ khai báo phiên bản ở cấp gốc.
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// Module app là target Android chính của ứng dụng.
include(":app")
