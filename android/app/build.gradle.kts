plugins {
    id("com.android.application")
    // Plugin Flutter phải được áp dụng sau plugin Android và Kotlin để nhận đúng cấu hình build.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.iig.v_monitor.v_monitor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Định danh gói Android; cần đổi sang domain doanh nghiệp trước khi phát hành chính thức.
        applicationId = "com.iig.v_monitor.v_monitor"
        // Các mức SDK và phiên bản lấy từ Flutter tool/pubspec để mọi nền tảng đồng bộ.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Bản release hiện dùng cấu hình ký debug; cần khai báo keystore doanh nghiệp khi phát hành.
            // Khóa debug tạm thời giúp `flutter run --release` chạy trước khi có keystore thật.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
