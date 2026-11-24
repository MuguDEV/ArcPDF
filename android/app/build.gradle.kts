import com.arcpdf.build.AbiSelection
import com.arcpdf.build.RustIndexerSettings
import com.arcpdf.build.RustIndexerTasks

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Experimental: store native libraries compressed inside the APK
// (useLegacyPackaging = true). Set -PARCPDF_COMPRESS_NATIVE_LIBS=true or the
// environment variable of the same name; the environment variable is the way to
// reach Gradle through `flutter build apk`. Default is off (modern packaging:
// uncompressed, page aligned, mapped directly from the APK). The setting is
// ignored when a bundle task is requested so the AAB keeps modern packaging.
val compressNativeLibsRequested =
    ((project.findProperty("ARCPDF_COMPRESS_NATIVE_LIBS") as String?) ?: System.getenv("ARCPDF_COMPRESS_NATIVE_LIBS"))
        ?.trim()?.equals("true", ignoreCase = true) == true
val bundleTaskRequested = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }
val compressNativeLibs = compressNativeLibsRequested && !bundleTaskRequested
if (compressNativeLibsRequested && bundleTaskRequested) {
    logger.warn("ARCPDF_COMPRESS_NATIVE_LIBS is ignored for bundle tasks; AAB keeps modern packaging.")
}
// ARCPDF_ABIS (property or environment) and Flutter's target-platform decide the ABIs. Unknown
// ABIs and sets that disagree fail the build; unrestricted builds use every supported ABI.
val activeRustAbis = AbiSelection.resolve(project).abis

// One independent, incremental task per selected ABI (buildRustIndexerArm64,
// buildRustIndexerArmV7, buildRustIndexerX64), each with its own output directory.
val rustIndexerTasks = RustIndexerTasks.register(
    project,
    activeRustAbis,
    RustIndexerSettings(minSdk = flutter.minSdkVersion, ndkVersion = flutter.ndkVersion),
)

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

    rustIndexerTasks.values.forEach { task ->
        sourceSets.getByName("main").jniLibs.srcDir(task.flatMap { it.outputDirectory })
    }

    packaging {
        jniLibs {
            useLegacyPackaging = compressNativeLibs
            excludes += setOf(
                "lib/x86/**",
            )
        }
    }
}

// pdfium_dart downloads libpdfium.so from Flutter's native-assets hook inside
// compileFlutterBuild<Variant>. Run that task before the Rust task snapshots its
// PDFium input, then stage the Rust/PDFium output before AGP merges JNI folders.
// Wiring preBuild to buildRustIndexer would run in the opposite order.
val flutterCompileTasks = tasks.matching { it.name.startsWith("compileFlutterBuild") }
rustIndexerTasks.values.forEach { rustTask ->
    rustTask.configure { dependsOn(flutterCompileTasks) }
}
tasks.matching { it.name.matches(Regex("""merge.+JniLibFolders""")) }.configureEach {
    dependsOn(RustIndexerTasks.aggregate(project))
}

flutter {
    source = "../.."
}

// The bundled recognizer (com.google.mlkit:text-recognition) ships
// libmlkit_google_ocr_pipeline.so and assets/mlkit-google-ocr-models. It must not
// come back through any transitive dependency; OCR uses the Google Play Services
// module that is installed on demand.
configurations.all {
    exclude(group = "com.google.mlkit", module = "text-recognition")
}

dependencies {
    // Unbundled Latin recognizer. The native engine and models live in Google Play
    // services and are installed through ModuleInstallClient (see OcrModuleManager).
    // The manifest deliberately has no com.google.mlkit.vision.DEPENDENCIES entry,
    // because that would force an install-time download regardless of user choice.
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.2")
    implementation("com.google.android.gms:play-services-base:18.5.0")

    testImplementation("junit:junit:4.13.2")
}
