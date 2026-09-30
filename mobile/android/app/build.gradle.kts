import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Lab 10 — อ่าน signing config จาก android/key.properties ถ้ามี (Jenkins สร้างไฟล์นี้ชั่วคราวตอน
// build release เท่านั้น แล้วลบทิ้งเสมอใน post { cleanup } — ไม่ commit ไฟล์นี้เข้า git เด็ดขาด)
// ถ้าไม่มีไฟล์ (เช่น build debug ปกติ หรือ dev รันในเครื่องตัวเอง) ก็ fallback ไป sign ด้วย debug
// key ตามเดิม ไม่ทำให้ build ปกติพังเพราะหาไฟล์นี้ไม่เจอ
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.taskflow.taskflow_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.taskflow.taskflow_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
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
            // มี key.properties จริง (Jenkins สร้างให้ตอน build บน main) ถึงจะ sign ด้วย release
            // key จริง ไม่งั้น fallback ไป debug key เหมือนเดิม (local dev / debug build ทุก branch)
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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
