plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arcpdf.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.arcpdf.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePassword = System.getenv("KEYSTORE_PASSWORD")?.trim()?.removeSurrounding("\"")?.removeSurrounding("'")
            if (!keystorePassword.isNullOrEmpty()) {
                storeFile = file("arcpdf.jks")
                storePassword = keystorePassword
                keyAlias = System.getenv("KEY_ALIAS")?.trim()?.removeSurrounding("\"")?.removeSurrounding("'")
                keyPassword = System.getenv("KEY_PASSWORD")?.trim()?.removeSurrounding("\"")?.removeSurrounding("'")
            }
        }
    }

    buildTypes {
        release {
            // Use the release signing config if KEYSTORE_PASSWORD is provided, otherwise fall back to debug.
            signingConfig = if (!System.getenv("KEYSTORE_PASSWORD").isNullOrEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}
