import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取 android/key.properties 中配置的正式签名密钥；缺失时回退到 debug keystore。
val keystorePropertiesFile = rootProject.file("key.properties")
val useReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (useReleaseKeystore) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.netsince.dna"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.netsince.dna"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (useReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有正式密钥时用统一密钥（保证更新时签名一致），否则回退 debug keystore。
            signingConfig = if (useReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
        debug {
            // 让 CI 产出的 debug APK 也使用同一密钥，避免覆盖安装时签名不一致。
            signingConfig = if (useReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    // sherpa_onnx(语音输入) 与 onnxruntime 插件(TTS) 都捆绑 libonnxruntime.so，
    // 但版本不同（sherpa:1.27.0 / onnxruntime 插件:1.15.1），同名 so 合并时冲突。
    // sherpa 的 libsherpa-onnx-c-api.so 编译期绑定 1.27.0，不可替换；而 onnxruntime
    // 插件的 Dart 绑定走标准 onnxruntime C API、向后兼容，可复用 1.27.0。
    // 因此这里在 app 自身 jniLibs 放置 sherpa 的 1.27.0（见 src/main/jniLibs），
    // 并 pickFirst 保留它，丢弃 onnxruntime 插件自带的旧版，让 TTS 复用同一份。
    packaging {
        jniLibs {
            pickFirsts += "**/libonnxruntime.so"
        }
    }
}

flutter {
    source = "../.."
}
