plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val rustOutputDir = layout.buildDirectory.dir("generated/rustJniLibs")
val rustCrateDir = rootProject.file("../native/arcpdf_indexer")
val pdfiumLibrary = rootProject.file(
    "../.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/android-arm64/libpdfium.so"
)
val cargoExecutable = System.getenv("CARGO") ?: "cargo"

val buildRustIndexer by tasks.registering(Exec::class) {
    val androidHome = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
        ?: error("ANDROID_HOME or ANDROID_SDK_ROOT is required to build the Rust indexer")
    val ndkRoot = file("$androidHome/ndk/${flutter.ndkVersion}")
    val clang = file("$ndkRoot/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${flutter.minSdkVersion}-clang")
    val llvmAr = file("$ndkRoot/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar")
    val cargoTarget = file(
        System.getenv("ARCPDF_RUST_TARGET_DIR")
            ?: rootProject.file("../build/rust-target").absolutePath
    )
    val output = rustOutputDir.get().dir("arm64-v8a")

    workingDir(rustCrateDir)
    environment("CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER", clang.absolutePath)
    environment("CC_aarch64_linux_android", clang.absolutePath)
    environment("AR_aarch64_linux_android", llvmAr.absolutePath)
    environment("CARGO_TARGET_DIR", cargoTarget.absolutePath)
    commandLine(cargoExecutable, "build", "--release", "--target", "aarch64-linux-android", "--locked")
    inputs.files(fileTree(rustCrateDir.resolve("src")), rustCrateDir.resolve("Cargo.toml"), rustCrateDir.resolve("Cargo.lock"))
    inputs.file(pdfiumLibrary)
    outputs.files(
        output.file("libarcpdf_indexer.so"),
        output.file("libpdfium.so"),
    )
    doFirst {
        require(pdfiumLibrary.exists()) {
            "PDFium Android library was not generated at ${pdfiumLibrary.absolutePath}"
        }
    }
    doLast {
        output.asFile.mkdirs()
        copy {
            from(cargoTarget.resolve("aarch64-linux-android/release/libarcpdf_indexer.so"))
            into(output)
        }
        // pdfium_dart's native-assets manifest references libpdfium.so, but
        // Flutter 3.41 does not place that asset in an Android APK. Package it
        // as a normal JNI library so both pdfrx and the Rust PDF backend can
        // resolve the same bundled PDFium binary at runtime.
        copy {
            from(pdfiumLibrary)
            into(output)
        }
    }
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
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        create("arcpdfRelease") {
            val keyPath = System.getenv("ARCPDF_KEYSTORE_PATH")
            if (!keyPath.isNullOrBlank()) {
                storeFile = file(keyPath)
                storePassword = System.getenv("ARCPDF_STORE_PASSWORD")
                keyAlias = System.getenv("ARCPDF_KEY_ALIAS")
                keyPassword = System.getenv("ARCPDF_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (System.getenv("ARCPDF_KEYSTORE_PATH").isNullOrBlank()) signingConfigs.getByName("debug") else signingConfigs.getByName("arcpdfRelease")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }

    sourceSets.getByName("main").jniLibs.srcDir(rustOutputDir)

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }
}

tasks.named("preBuild").configure { dependsOn(buildRustIndexer) }

flutter {
    source = "../.."
}

dependencies {
    // Bundled Latin recognizer: works fully offline after installation and is
    // invoked only for pages the Rust layout pass identifies as scans.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
