plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val rustOutputDir = layout.buildDirectory.dir("generated/rustJniLibs")
val rustCrateDir = rootProject.file("../native/arcpdf_indexer")
val pdfiumBuildDir = rootProject.file("../.dart_tool/hooks_runner/shared/pdfium_dart/build")
val cargoExecutable = System.getenv("CARGO") ?: "cargo"

data class RustAbi(
    val abi: String,
    val rustTarget: String,
    val clangPrefix: String,
    val pdfiumArch: String,
)

val rustAbis = listOf(
    RustAbi("arm64-v8a", "aarch64-linux-android", "aarch64-linux-android", "arm64"),
    RustAbi("armeabi-v7a", "armv7-linux-androideabi", "armv7a-linux-androideabi", "arm"),
    RustAbi("x86_64", "x86_64-linux-android", "x86_64-linux-android", "x64"),
)

// Optional comma separated ABI restriction, e.g. -PARCPDF_ABIS=arm64-v8a or
// ARCPDF_ABIS=arm64-v8a. Defaults to every supported ABI.
val requestedAbis = ((project.findProperty("ARCPDF_ABIS") as String?) ?: System.getenv("ARCPDF_ABIS"))
    ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }

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
val activeRustAbis = if (requestedAbis.isNullOrEmpty()) {
    rustAbis
} else {
    rustAbis.filter { it.abi in requestedAbis }.also {
        require(it.isNotEmpty()) { "ARCPDF_ABIS=$requestedAbis matches no supported ABI" }
    }
}

// The pdfium_dart build hook stores the binary under
// <release>/android-<arch>/libpdfium.so, where <release> (for example
// chromium_7811) changes between pdfium_dart versions. Resolve it by search.
fun findPdfium(arch: String): File? =
    pdfiumBuildDir.listFiles()
        ?.filter { it.isDirectory }
        ?.sortedByDescending { it.name }
        ?.map { it.resolve("android-$arch/libpdfium.so") }
        ?.firstOrNull { it.exists() }

val buildRustIndexer by tasks.registering {
    val cargoTarget = file(
        System.getenv("ARCPDF_RUST_TARGET_DIR")
            ?: rootProject.file("../build/rust-target").absolutePath
    )
    inputs.files(fileTree(rustCrateDir.resolve("src")), rustCrateDir.resolve("Cargo.toml"), rustCrateDir.resolve("Cargo.lock"))
    inputs.property("abis", activeRustAbis.map { it.abi })
    outputs.dir(rustOutputDir)

    doLast {
        val androidHome = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
            ?: error("ANDROID_HOME or ANDROID_SDK_ROOT is required to build the Rust indexer")
        val ndkBin = file("$androidHome/ndk/${flutter.ndkVersion}/toolchains/llvm/prebuilt/linux-x86_64/bin")
        val llvmAr = ndkBin.resolve("llvm-ar")
        val minSdk = flutter.minSdkVersion

        rustOutputDir.get().asFile.deleteRecursively()

        for (target in activeRustAbis) {
            val pdfium = findPdfium(target.pdfiumArch)
                ?: error(
                    "PDFium Android library for ${target.abi} was not generated under " +
                        "${pdfiumBuildDir.absolutePath}/*/android-${target.pdfiumArch}/libpdfium.so"
                )
            val clang = ndkBin.resolve("${target.clangPrefix}$minSdk-clang")
            require(clang.exists()) { "NDK clang not found at ${clang.absolutePath}" }
            val triple = target.rustTarget
            val envTriple = triple.replace('-', '_')
            val envTripleUpper = envTriple.uppercase()

            val process = ProcessBuilder(cargoExecutable, "build", "--release", "--target", triple, "--locked")
                .directory(rustCrateDir)
                .inheritIO()
                .also {
                    it.environment()["CARGO_TARGET_${envTripleUpper}_LINKER"] = clang.absolutePath
                    it.environment()["CC_$envTriple"] = clang.absolutePath
                    it.environment()["AR_$envTriple"] = llvmAr.absolutePath
                    it.environment()["CARGO_TARGET_DIR"] = cargoTarget.absolutePath
                }
                .start()
            check(process.waitFor() == 0) { "cargo build failed for $triple" }

            val output = rustOutputDir.get().dir(target.abi).asFile
            output.mkdirs()
            copy {
                from(cargoTarget.resolve("$triple/release/libarcpdf_indexer.so"))
                into(output)
            }
            // pdfium_dart's native-assets manifest references libpdfium.so, but
            // Flutter does not place that asset in an Android APK. Package it
            // as a normal JNI library so both pdfrx and the Rust PDF backend can
            // resolve the same bundled PDFium binary at runtime.
            copy {
                from(pdfium)
                into(output)
            }
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
            useLegacyPackaging = compressNativeLibs
            excludes += setOf(
                "lib/x86/**",
            )
        }
    }
}

tasks.named("preBuild").configure { dependsOn(buildRustIndexer) }

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
