plugins {
    id("com.android.application")
    // Flutter Gradle 外掛必須在 Android 和 Kotlin Gradle 外掛之後套用。
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "moe.yashi.evernight_seal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: 指定您自己唯一的 Application ID（https://developer.android.com/studio/build/application-id.html）。
        applicationId = "moe.yashi.evernight_seal"
        // 您可以更新以下數值以符合您的應用程式需求。
        // 更多資訊請參閱：https://flutter.dev/to/review-gradle-config。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: 為發行版建置新增您自己的簽署設定。
            // 暫時使用除錯金鑰簽署，以便 `flutter run --release` 能正常運作。
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
