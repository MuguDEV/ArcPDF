# ArcPDF optimization baseline

Status: baseline audit, no production code changed. Every number in this file
comes from a command or file named next to it. Anything that could not be
measured is listed in [Not measured](#14-not-measured) with the reason.

## 0. Audit base

| Item | Value | Source |
| --- | --- | --- |
| Audited tree | branch `fix/pdfrx-all-apks`, commit `6c9cb1d` (PR #108 head) | `git log --oneline -1` |
| Working branch | `docs/optimization-baseline`, created from `6c9cb1d` | `git branch --show-current` |
| App version | `1.5.157` | `pubspec.yaml` line 4 |
| pdfrx | `^2.13.1`, locked `2.13.1` (engine `pdfrx_engine 0.9.3`, `pdfium_dart 0.4.3`, `pdfium_flutter 0.4.3`) | `pubspec.lock` |

The audit reflects the PR branch, not `Main`. When the audit ran, GitHub reported
PR #108 as merged (`gh api repos/MuguDEV/ArcPDF/pulls/108`: `merged: true`,
merge commit `17665bd`). `origin/Main` is now `583aba0`. The only file that
differs between `6c9cb1d` and `origin/Main` is `.github/workflows/auto_release.yml`
(`git diff --stat 6c9cb1d origin/Main`: 1 file, 88 insertions, 23 deletions). The
later workflow commits harden keystore handling and APK signature verification
(fixed `build-tools/36.0.0/apksigner` path, digest normalization, extra logging).
All Dart, Kotlin, Rust, Gradle and dependency findings below therefore also hold
for `Main`. The workflow findings in section 10 quote the PR branch version and
note where `Main` differs.

The release `v1.5.157-build.117` was built from `Main` commit `583aba0`
(`gh api repos/MuguDEV/ArcPDF/releases/tags/v1.5.157-build.117`, field
`target_commitish`). Its ARM64 APK is the historical baseline used below.

### Documents read

`CONTRIBUTING.md`, `README.md`, `plan.md`, `docs/CODE_AUDIT.md`,
`docs/perf/{baseline,audit,decisions,results,riverpod}.md`,
`.github/workflows/auto_release.yml`, `pubspec.yaml`, `pubspec.lock`,
`analysis_options.yaml`, `android/app/build.gradle.kts`,
`android/gradle.properties`, `android/settings.gradle.kts`, the Android manifest,
the four Kotlin files, `native/arcpdf_indexer/Cargo.toml` and sources, and `tool/`.
The repository has no `AGENTS.md`, no `.kiro/` directory and no project skills
directory. `CONTRIBUTING.md` mentions `AGENTS.md` and an Android UI skill, but
neither file exists in this checkout.

Repository rules that constrain optimization work (`CONTRIBUTING.md`): measure
before claiming an improvement, keep PDF decoding, hashing, OCR and transforms off
the UI isolate, bound workers and memory, dispose native resources on every path,
no analytics or remote processing, and versioned migrations for security format
changes.

## 1. Release asset sizes and APK component breakdown

### 1.1 Release assets

Source: `gh api repos/MuguDEV/ArcPDF/releases` (asset `size` fields, bytes).

| Release | Asset | Bytes |
| --- | --- | --- |
| `v1.5.157-build.117` | arm64-v8a APK | 46,485,439 |
| `v1.5.157-build.117` | armeabi-v7a APK | 37,833,033 |
| `v1.5.157-build.117` | x86_64 APK | 49,221,418 |
| `v1.5.157-build.117` | universal APK | 123,540,338 |
| `v1.5.157-build.117` | AAB | 94,548,167 |
| `v1.4.6` | arm64-v8a APK | 29,874,677 |
| `v1.4.6` | armeabi-v7a APK | 25,665,509 |
| `v1.4.6` | x86_64 APK | 31,698,041 |
| `v1.4.6` | AAB | 72,535,694 |

The `build.117` ARM64 asset is exactly 46,485,439 bytes, matching the historical
baseline in the task. Its SHA-256 (from the release `SHA256SUMS.txt` and
re-computed on the downloaded file) is
`8b4a66c389a434d2d6ca3352ecd5e4a94ad8f3a705cb9c3aeb6c7fb204e1be78`.

ARM64 growth from `v1.4.6` to `v1.5.157-build.117` is
46,485,439 - 29,874,677 = 16,610,762 bytes (+55.6 percent).

### 1.2 ARM64 component breakdown (measured)

Method: downloaded the release asset with
`gh api -H "Accept: application/octet-stream" repos/MuguDEV/ArcPDF/releases/assets/784056591`,
verified the hash and byte size above, then read the ZIP directory with Python
`zipfile` (`file_size` and `compress_size` per entry). Sizes are bytes as stored
in the APK. Native libraries are stored uncompressed (compress type 0), so their
stored size equals their file size.

| Component | Stored bytes | Share of APK |
| --- | --- | --- |
| `lib/arm64-v8a/libflutter.so` (Flutter engine) | 11,763,360 | 25.3% |
| `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` (ML Kit OCR) | 11,064,544 | 23.8% |
| `lib/arm64-v8a/libapp.so` (Dart AOT snapshot) | 11,010,952 | 23.7% |
| `lib/arm64-v8a/libpdfium.so` | 6,598,376 | 14.2% |
| `classes.dex` (compressed; 2,903,504 uncompressed) | 1,255,622 | 2.7% |
| `lib/arm64-v8a/libarcpdf_indexer.so` (Rust) | 854,696 | 1.8% |
| `assets/flutter_assets/**` (19 entries, compressed) | 1,642,149 | 3.5% |
| `assets/mlkit-google-ocr-models/**` (21 entries, compressed; 1,486,803 uncompressed) | 1,272,325 | 2.7% |
| `resources.arsc` | 452,424 | 1.0% |
| `res/**` (388 entries, compressed) | 231,618 | 0.5% |
| `lib/arm64-v8a/libdartjni.so` | 124,592 | 0.3% |
| `org/apache/tika/**` (3 entries) | 52,531 | 0.1% |
| `lib/arm64-v8a/libpdfrx_pdfium_gate.so` | 5,080 | <0.1% |
| `META-INF/**` (58 entries) | 4,618 | <0.1% |
| `AndroidManifest.xml` | 4,167 | <0.1% |

Sum of all 530 entries (compressed): 46,353,562 bytes. The remaining 131,877
bytes of the 46,485,439 file are ZIP headers, alignment padding and the APK
signing block. Uncompressed total of all entries: 50,556,358 bytes.

Native libraries together are 41,421,600 bytes (89.1 percent of the APK):
libflutter 11,763,360 + ML Kit 11,064,544 + libapp 11,010,952 + libpdfium
6,598,376 + indexer 854,696 + dartjni 124,592 + pdfium gate 5,080.

Correction: earlier revisions of this file stated 29,821,204 bytes (64.1
percent). That figure omitted components and was wrong.

`flutter_assets` detail (compressed bytes): six `LucideVariable-w100..w600.ttf`
fonts total 1,457,296; `NOTICES.Z` 133,183; `lucide.ttf` 21,739; two identical
Lottie JSON files (`denied.json`, `splash.json`, `md5 07e6d1f3...`) 4,567 each;
`MaterialIcons-Regular.otf` 1,335; `ink_sparkle.frag` appears twice (5,275 each).

### 1.3 Change from v1.4.6 (measured, same method)

The `v1.4.6` ARM64 APK was downloaded and diffed per entry against `build.117`.

| Entry | Delta (compressed bytes) |
| --- | --- |
| `libmlkit_google_ocr_pipeline.so` (new) | +11,064,544 |
| `libapp.so` | +1,179,648 |
| `libarcpdf_indexer.so` (new) | +854,696 |
| ML Kit model assets (21 new entries) | +1,272,325 |
| `classes.dex` | +292,900 |
| Six Lucide variable fonts (new) | +1,457,296 |
| `libpdfium.so` | +211,680 |
| `resources.arsc` | +134,612 |
| `libflutter.so` | +15,496 |
| `hugeicons-stroke-rounded.ttf` (removed) | -11,055 |
| `MaterialIcons-Regular.otf` | -8,517 |

Of the 16.6 MB growth, the bundled ML Kit OCR library plus models account for
12,336,869 bytes (74.3 percent). The Rust indexer adds 854,696 bytes. The Lucide
variable fonts add 1,457,296 bytes.

### 1.4 Confirmed findings

- **ML Kit is the largest single avoidable cost.** `android/app/build.gradle.kts` line
  170 (`implementation("com.google.mlkit:text-recognition:16.0.1")`) bundles the
  Latin recognizer. It ships in every ABI APK and in the 123.5 MB universal APK.
  It is only used when the Rust layout pass flags scanned pages
  (`ReflowOcrChannel.kt`).
- **Lucide variable fonts are bundled but no code references them.** `grep` for
  `LucideVariable` and weight variants in `lib/` returns nothing; icons are
  referenced through `LucideIcons.<name>` in `lib/src/shared/theme/arc_icons.dart`.
  Whether the package pulls all six weights automatically regardless of use is
  not confirmed here (see Not measured).
- **Unused Lottie assets.** `assets/lottie/denied.json` and `splash.json` are
  byte-identical (56,651 bytes each) and `lottie` is never imported in `lib/`,
  `test/` or `tool/`. They are declared in `pubspec.yaml` (`assets/lottie/`).
- **Duplicate shader** `shaders/ink_sparkle.frag` and
  `packages/material_ui/shaders/ink_sparkle.frag` are both packaged (5,275
  compressed bytes each). Framework-owned, low value.
- **`org/apache/tika` resources** (52,531 bytes) are packaged from a transitive
  Android dependency. The source dependency is not identified.

### 1.5 Existing optimizations

- ARM64, ARMv7 and x86_64 per-ABI APKs exist and `lib/x86/**` is excluded
  (`build.gradle.kts` packaging block).
- R8 and resource shrinking are on for release (`isMinifyEnabled = true`,
  `isShrinkResources = true`).
- Release builds use `--obfuscate --split-debug-info` (workflow).
- The Rust crate builds with `opt-level = 3`, thin LTO, `codegen-units = 1`,
  `panic = "abort"`, `strip = true` (`native/arcpdf_indexer/Cargo.toml`). Result:
  854,696 bytes for ARM64.
- `libpdfium.so` is shared between pdfrx and the Rust indexer
  (`build.gradle.kts` comment and `dlopen("libpdfium.so")` in
  `native/arcpdf_indexer/src/lib.rs` line 852), so PDFium is packaged once per ABI.

### 1.6 Proposed improvements

1. Evaluate making OCR optional: on-demand model through Google Play services
   (`com.google.android.gms:play-services-mlkit-text-recognition`, unbundled)
   instead of the bundled artifact. Trade-offs: needs Play services and network
   for first use, which conflicts with the local-first promise, so this needs a
   product decision. Expected saving is the 12.3 MB above; the real number must be
   measured after the change.
2. Remove the unused `assets/lottie/` directory and the `lottie` dependency
   (about 9 KB compressed, plus Dart AOT code if any is retained).
3. Check which Lucide weights are required and drop unused variable fonts
   (up to 1.46 MB compressed).
4. Build ARM64-only distribution for the updater (see section 10) so users do not
   download the 123.5 MB universal APK.
5. Add `--analyze-size` output to CI as an artifact so size is tracked per release.

## 2. Dependencies

Source: `pubspec.yaml`, `pubspec.lock` parsed with a script.

- `pubspec.lock` has 212 packages: 48 direct main, 8 direct dev, 156 transitive.
- Direct main dependency count in `pubspec.yaml`: 48 (including the Flutter SDK).

### 2.1 Direct dependencies with no import in `lib/`, `test/` or `tool/`

Checked with `grep -rn "package:<name>"`. Result: zero matches for each.

| Package | Locked version | Notes |
| --- | --- | --- |
| `animations` | 2.2.0 | Only the word "animations" appears in a comment in `lib/src/app.dart`. |
| `collection` | 1.19.1 | Matches in `lib/` are the word, not imports. Also a Flutter SDK transitive, so removal from `pubspec.yaml` has no size effect. |
| `watcher` | 1.2.1 | No reference. |
| `flutter_staggered_grid_view` | 0.7.0 | No reference. |
| `scrollable_positioned_list` | 0.3.8 | No reference. |
| `lottie` | 3.3.3 | No reference; assets also unused. |
| `image_picker` | 1.2.2 | Only in generated `GeneratedPluginRegistrant.java`; its Android classes are in the dex. |
| `sensors_plus` | 7.0.0 | Only in the generated plugin registrant. |

`flutter_lints`, `build_runner`, `hive_generator`, `flutter_launcher_icons` are
dev-only or tooling (`hive_generator` has no `part` usage check performed).
The package `hive` adapters in `lib` are written by hand
(`PdfAnnotationAdapter` registered in `lib/src/bootstrap.dart`); whether
`hive_generator` and `build_runner` are still needed is not confirmed.

Effect on APK size of removing these is **not measured** (Flutter tree shakes
unreferenced Dart, so the Dart AOT effect is expected to be small; Android plugin
code for `image_picker` and `sensors_plus` is not tree shaken before R8).

### 2.2 Packages used from a single file

Import counts in `lib/` (`grep -rl "package:<name>/" lib | wc -l`): `printing` 1,
`flutter_markdown` 1, `flutter_svg` 1, `install_plugin` 1, `pattern_lock` 1,
`pinput` 1, `vibration` 1, `local_auth` 1, `encrypt` 1, `image` 1,
`flutter_displaymode` 1, `flutter_slidable` 1, `custom_refresh_indicator` 1,
`lucide_icons_flutter` 1, `device_info_plus` 1, `receive_sharing_intent` 1,
`url_launcher` 1, `google_fonts` 1, `http` 1. Each is a candidate for replacement
by a smaller or platform-native approach, but none has measured cost yet.

### 2.3 Overlapping PDF stacks

The app uses three PDF engines at once:

- **pdfrx/PDFium** for rendering, text search and thumbnails.
- **`syncfusion_flutter_pdf` 33.2.8** (plus `syncfusion_flutter_core`) for
  Dart-side merge, split, rearrange, metadata, image-to-PDF and compression
  (`lib/src/features/tools/tools_service.dart`).
- **Rust over dlopen'd PDFium** for native merge, organize, split and reflow
  (`native/arcpdf_indexer/src/lib.rs`).
- **Android `PdfRenderer`** for OCR page rasterization (`ReflowOcrChannel.kt`).
- **`printing` 5.14.3** brings the `pdf` 3.12.0 package and `barcode`, `qr`,
  `bidi`, `pdf_widget_wrapper` transitively.

The licensing of `syncfusion_flutter_pdf` (community license terms) versus the
project's AGPL-3.0 license has not been reviewed here. Flagged for a human.

### 2.4 Toolchain versions

AGP `8.11.1`, Kotlin `2.2.20`, Gradle wrapper `9.1.0` (`android/settings.gradle.kts`,
`gradle-wrapper.properties`). `docs/CODE_AUDIT.md` records Android Gradle Plugin
and Kotlin support warnings from an earlier build. CI uses Flutter `3.47.9`
(workflow) while the README badge says `3.41+`.

### 2.5 Proposed improvements

1. Remove the eight unreferenced direct dependencies after confirming with a real
   `flutter pub get` plus `flutter analyze` (not possible here).
2. Measure the `syncfusion_flutter_pdf` cost with `--analyze-size`; evaluate
   routing every tool through the Rust/PDFium runtime.
3. Run `flutter pub outdated` and `flutter pub deps --style=compact` in a Flutter
   environment to refresh the transitive tree.

## 3. Dart AOT code size

- `libapp.so` (ARM64, obfuscated) is **11,010,952 bytes** in `build.117`; it was
  9,831,304 bytes in `v1.4.6` (+1,179,648, +12.0 percent). Source: ZIP directory
  of the two APKs.
- Source scale: `lib/` has 108 Dart files and 40,851 lines in `lib/` and `test/`
  combined (`find lib test -name '*.dart' | xargs wc -l`). Largest files:
  `pdf_viewer_screen.dart` 3,423 lines, `home_screen.dart` 1,498,
  `settings_screen.dart` 1,245, `tools_service.dart` 1,227,
  `backup_service.dart` 1,107.
- A per-package or per-library breakdown requires
  `flutter build apk --analyze-size` or `--code-size-directory`. **Not measured**:
  no Flutter SDK here.

Existing optimizations: `--obfuscate --split-debug-info` in release workflow;
Flutter tree-shakes icons (`MaterialIcons-Regular.otf` is 2,264 bytes
uncompressed; `lucide.ttf` is 39,308 bytes).

Proposed: capture `--analyze-size` JSON for the ARM64 build as the Dart AOT
baseline; split `pdf_viewer_screen.dart`; review the Syncfusion and `image`
package footprint; remove unreferenced dependencies from section 2.1.

## 4. Native library packaging

Facts (`android/app/build.gradle.kts`, `native/arcpdf_indexer`, release APK):

- ABIs built: `arm64-v8a`, `armeabi-v7a`, `x86_64` (`rustAbis`). `x86` excluded.
  Restrict with `-PARCPDF_ABIS` or the `ARCPDF_ABIS` env variable.
- Gradle task `buildRustIndexer` runs `cargo build --release --target <triple>
  --locked` per ABI during `preBuild`, copies `libarcpdf_indexer.so` and the
  `libpdfium.so` found under `.dart_tool/hooks_runner/shared/pdfium_dart/build`
  into `build/generated/rustJniLibs/<abi>`. PDFium is therefore packaged as a
  normal JNI library because Flutter native assets are not placed in the APK.
- All native libraries are stored uncompressed in the APK (compress type 0 in the
  ZIP directory). Uncompressed storage is the AGP default for
  `useLegacyPackaging = false` and lets the installer map libraries without
  extracting them; the download size is the same either way for already
  incompressible code, but compression would shrink the download. The trade-off is
  larger on-device size and slower first load, so it is not recommended without
  measurement.
- `libpdfrx_pdfium_gate.so` (5,080 bytes) and `libdartjni.so` (124,592 bytes) are
  also packaged.
- Rust crate dependencies: `blake3 1.8`, `serde 1.0`, `serde_json 1.0`,
  `libloading 0.8`. The crate does not statically link PDFium.
- Per-ABI sizes of the native Rust library and PDFium for ARMv7 and x86_64 are
  **not measured** (only the ARM64 APK was downloaded). Release asset sizes for
  all ABIs are in section 1.1.

Findings:

- The workflow runs `flutter build apk` three times (universal, split-per-abi,
  appbundle), each running the full cargo build for three targets. The Rust cache
  action mitigates the cargo cost; Gradle `org.gradle.caching=true`.
- `findPdfium` picks the lexicographically highest release directory under
  `pdfium_dart/build`. A stale directory could be selected after a version bump on
  a reused build machine. Not confirmed, flagged.
- `gradle.properties` sets `org.gradle.parallel=false` and `workers.max=1`
  (CI memory protection, slows builds).
- The universal APK is 123,540,338 bytes versus 46,485,439 for ARM64 (2.66x),
  but the in-app updater downloads the universal APK (section 10).

Proposed: measure `libpdfium.so` flags and size against a size-optimized PDFium
build; deduplicate the three Flutter builds in CI by deriving the universal APK
and AAB in one invocation where possible; add a CI assertion on per-ABI size
budgets.

## 5. OCR integration

Files: `android/app/src/main/kotlin/com/arcpdf/app/ReflowOcrChannel.kt` (147
lines), `lib/src/features/pdf/data/reflow_ocr_service.dart`,
`lib/src/features/pdf/data/reflow_engine.dart` (lines 24-100),
`native/arcpdf_indexer/src/reflow.rs`, `build.gradle.kts` line 170.

Design (confirmed from source):

1. Rust reflow analysis (`reflow.rs`) identifies pages that look scanned and
   returns `document.ocrPages`.
2. `ReflowEngine` calls `ReflowOcrService.recognizePages` over the
   `com.arcpdf.app/reflow_ocr` MethodChannel only if `settings.enableOcr` is set
   (default `true`) and `ocrPages` is non-empty. Other platforms return empty.
3. Kotlin renders each page with Android `PdfRenderer` (not PDFium) to an
   ARGB_8888 bitmap, longest side at most 2,400 px by default, clamped to
   1,200-3,200, reduced to 1,600 on low-RAM devices and 1,900 when
   `memoryClass < 192`, then runs the bundled Latin ML Kit recognizer with a
   45 second per-page timeout. The bitmap is recycled in `finally` and the
   recognizer is closed in `finally`.
4. A single-thread daemon executor serializes OCR requests.

Findings:

- **Recognizer is created per call**, not reused; model load cost is paid on every
  reflow request. Not measured.
- **Only Latin script is supported**; there is no language selection.
- **OCR is not cancellable.** The channel has no cancel method; a closed document
  keeps the executor busy up to 45 s per page.
- **No progress reporting** from OCR to the reflow UI.
- **Errors are swallowed** into an empty result in Dart (`PlatformException` and
  `MissingPluginException` return `const []`), so a failed OCR looks like "no
  text". Kotlin maps exceptions to `ocr_failed` / `ocr_permission_denied` without
  logging.
- **No automated tests for OCR**: `grep -ril ocr test/` returns no file.
- **PdfRenderer and PDFium differ**: OCR bitmaps come from Android's renderer while
  the reader uses PDFium, so page boxes and rotation handling may differ. Not
  verified.

Measured cost: 11,064,544 + 1,272,325 = 12,336,869 bytes in the ARM64 APK (section
1). OCR accuracy, latency per page and memory: **not measured** (needs a device and
scanned corpus).

Proposed: reuse a recognizer per document session, add cancellation and
per-page progress, surface OCR failure distinctly from empty text, add a Kotlin or
Dart test with a fake channel, and evaluate the unbundled ML Kit option (section
1.6).

## 6. Startup initialization

Files: `lib/main.dart` (166 lines), `lib/src/bootstrap.dart` (69),
`lib/src/app.dart` lines 55-128.

Sequence (confirmed):

1. `main()`: `WidgetsFlutterBinding.ensureInitialized()`,
   `AppDiagnostics.instance.install()`, edge-to-edge system UI, then `runApp`
   immediately with `_BootstrapGate` (comment: avoids a stuck native launch logo).
2. `bootstrap()` (`AppDiagnostics.install()` again, `AppLogger.event`,
   `Hive.initFlutter()`, register `PdfAnnotationAdapter`) then opens **11 Hive
   boxes strictly sequentially** (`favorites`, `recents`, `settings`,
   `thumbnailCache`, `recentsTimestamps`, `tags`, `sessions`, `pdf_annotations`,
   `reading_progress_pages`, `reading_progress_zoom`, `reading_progress_time`).
   `AppLogger.init()` is deliberately not awaited. PDFium initializes lazily.
3. After the first frame of `ArcPdfApp`: `intentServiceProvider.init()` runs in
   `initState`; a post-frame callback calls `AndroidJobService.recover()`, may
   delete `.arcpdf_*` directories next to an interrupted job output, and calls
   `FlutterDisplayMode.setHighRefreshRate()` or low depending on low power mode.

Findings:

- Sequential box opening is intentional (retry safety, comment in
  `bootstrap.dart`) but is the most direct place where cold start time can be
  reduced by opening independent boxes concurrently. Effect **not measured**.
- `AppDiagnostics.instance.install()` is called twice (`main.dart` line 12 and
  `bootstrap.dart` line 19). Whether `install` is idempotent was not checked.
- `FlutterDisplayMode.setHighRefreshRate()` is forced for non-low-power mode on
  every start, regardless of content. Battery effect not measured.
- `docs/perf/baseline.md` lists cold-start metrics, all `[To be measured]`.
- No startup test covers `bootstrap.dart` or `main.dart` by file name
  (`bootstrap.dart` and `main.dart` appear in the list of 34 `lib` files whose name
  is not referenced in `test/`).

Cold start time, time to first frame and time to first PDF page: **not measured**
(no device, no Flutter).

Proposed: add `Timeline`/`Trace` markers around `bootstrap`, record a baseline
with `flutter run --profile --trace-startup` on a device, then try parallel box
opening and deferring non-essential boxes (annotations, reading progress zoom/time)
until first use.

## 7. PDF rendering and memory management

Files: `lib/src/features/pdf/viewer/pdf_viewer_screen.dart` (3,423 lines),
`lib/src/features/pdf/home/widgets/pdf_thumbnail_cache.dart` (197),
`lib/src/features/pdf/application/pdf_library_controller.dart` (793),
`lib/src/features/settings/settings_controller.dart`.

Confirmed configuration (`pdf_viewer_screen.dart` lines 735-850):

- `PdfViewer.file` with `PdfViewerParams`. `maxImageBytesCachedOnMemory` is
  `readerCacheMb * 1024 * 1024` (user setting), `horizontalCacheExtent` and
  `verticalCacheExtent` use a user preload extent for the scroll axis and `0.25`
  for the other, `onePassRenderingSizeThreshold` is 1,200 (low power) or 1,600,
  `sizeDelegateProvider` is `PdfViewerSizeDelegateProviderLegacy(maxScale: 8)`.
- A `surfaceKey` record (line 746) decides when the document surface is rebuilt.
- Thumbnails: LRU map of 100 entries (`_maxMemCacheSize = 100`), 4 concurrent
  render tasks (`_maxConcurrentTasks = 4`), documents opened and disposed in
  `try/finally` (per `docs/perf/audit.md`).
- Reflow and OCR render separately (section 5).
- `docs/perf/results.md` claims viewer cache limits scale with battery saver
  (80 MB to 64 MB to 24 MB); the exact values are in `settings_controller.dart`
  and were not re-verified here.

Findings:

- Rendering runs through pdfrx's own caches; the app adds a second thumbnail
  cache and, for OCR, a third rasterization path through `PdfRenderer`.
- `pdf_viewer_screen.dart` is a 3,423-line single file with many pieces of state;
  rebuild cost has not been profiled. The earlier Riverpod review
  (`docs/perf/riverpod.md`) lists proposed `select` use; the viewer already uses
  `select` for settings (lines 738-745).
- Peak memory, scroll jank and memory after open/close cycles: **not measured**
  (all three are `[To be measured]` in `docs/perf/baseline.md`).
- `docs/perf/baseline.md` lists pdfrx 2.6.5 and Flutter 3.41.2, which no longer
  match `pubspec.lock` (pdfrx 2.13.1). That document is stale.

Proposed: add `PdfViewer` frame timing capture (`SchedulerBinding.addTimingsCallback`)
and native heap sampling in profile builds; define cache budgets as percentages of
`ActivityManager.memoryClass`; split the viewer screen into smaller widgets with
`RepaintBoundary` where profiling shows cost.

## 8. PDF processing tools

Files: `lib/src/features/tools/tools_service.dart` (1,227 lines),
`job_queue.dart`, `lib/src/core/native/native_job_runtime.dart` (343),
`lib/src/core/platform/android_job_service.dart`,
`ArcPdfJobService.kt`, `native/arcpdf_indexer/src/lib.rs`.

Architecture (confirmed):

- `JobQueue` (concurrency limit 2, `job_queue.dart` line 43) schedules every tool.
- **Merge, rearrange, split-selection** prefer the Rust runtime when
  `NativeJobRuntime.tryOpen()` succeeds on Android (calls `FPDF_ImportPages*`
  through dlopen'd PDFium, atomic save via `save_pdf_atomic`) and otherwise fall
  back to a dedicated Syncfusion isolate (`_runPdfWorker`, killable on cancel).
- **Images to PDF, metadata edit, page count** use Syncfusion. Syncfusion loads the
  whole file with `File(path).readAsBytesSync()` into memory (lines 349, 384, 917,
  942, 969, 1216), a limitation recorded in `plan.md` and `docs/perf/decisions.md`.
- **Compress** is a rasterize and re-encode pipeline: each page is rendered at up to
  1,200 x 1,600, copied (`Uint8List.fromList(image.pixels)`), sent to
  `Isolate.run` for JPEG encode, written to a staging directory, then rebuilt as a
  PDF with Syncfusion. Threads are bounded by `_toolMemoryLimitBytes`. Output
  can be larger than the input and text is lost (stated in `docs/CODE_AUDIT.md`).
- **PDF to images** renders with pdfrx at the requested DPI.
- Long operations register an Android foreground service
  (`ArcPdfJobService`, type `dataSync`) and the app recovers interrupted jobs on
  next start (section 6).
- Outputs go to a staging file and are published atomically; the Rust path has a
  unit test only for `split_selection` and duplicate detection
  (`#[test]` count: `lib.rs` 2, `reflow.rs` 7).

Findings:

- Two implementations of merge, rearrange and split exist; behavior can differ
  (outlines, forms, links: `docs/CODE_AUDIT.md` states these are not guaranteed
  to survive).
- Compression does not report before/after size and can increase size.
- Fallback to Syncfusion when `NativeJobRuntime.tryOpen()` returns null
  (`tools_service.dart` lines 183, 755, 818, 870); whether the chosen engine is
  logged was not confirmed.
- No measured time or memory for any tool. Benchmark list in
  `docs/perf/baseline.md` is entirely `[To be measured]`. `tool/benchmark_native_scanner.dart`
  benchmarks only the native scanner and needs a built native library.

Proposed: record which engine handled each job in diagnostics; move compress and
metadata edit to the native runtime or stream-based code; add before/after size
reporting and a "no savings" result; add a benchmark harness under `tool/` that
generates deterministic PDFs and prints time and peak RSS.

## 9. Vault security

Files: `lib/src/features/vault/vault_controller.dart` (372 lines),
`lib/src/features/vault/vault_screen.dart`,
`lib/src/features/security/security_controller.dart`.

State of the code (note: `docs/CODE_AUDIT.md` is a dated snapshot and some of
its vault findings are now partly addressed):

- Key: 32 random bytes in `flutter_secure_storage` under `vault_key`; a legacy IV
  under `vault_iv`. Missing credentials with existing data raise
  `VaultInitException`; credentials are not regenerated over existing files.
- New files use envelope V2: magic `ARCPDF\x02`, random 16-byte IV, AES-256-CBC
  ciphertext, then HMAC-SHA256 over magic, IV and ciphertext. Verification uses a
  constant-time compare before decrypting (`_decryptFromVault`, lines 168-205).
  The MAC key is `SHA-256(key || "ArcPDF vault MAC")`.
- Legacy files (no magic) and V1 envelopes (magic `...\x01`) are still readable
  and are **not authenticated**; V1 and legacy files are not migrated to V2.
- Operations are serialized, session-checked after every await, restricted to files
  directly inside the vault directory, and refuse symlinks.
- Move to vault: write encrypted file, flush, compare length, then delete source.
  Restore: same in reverse, and refuses restoring into the vault directory.

Findings:

- **Key derivation of the MAC key** reuses the encryption key through a plain
  SHA-256 concatenation instead of a separate random key or HKDF. Acceptable
  separation in practice but not standard.
- **PIN and pattern**: `SecurityController._hashString` is unsalted SHA-256, stored
  in secure storage as `lock_secret`; there is **no attempt counter or throttling**
  in `verifyPinOrPattern`, and the hash comparison is a plain string `==`. A
  4-digit PIN hash is trivially brute-forced if secure storage is read. The vault
  key is not derived from or wrapped by the PIN, so the lock is an application
  state gate only (also stated in `docs/CODE_AUDIT.md`).
- **Whole file in memory, on the UI isolate.** `_moveToVault`, `decryptToTempFile`
  and `_restoreFromVault` use `readAsBytes`, then synchronous encrypt or decrypt
  (`encryptBytes`, HMAC) on the main isolate, plus list-spread copies
  (`<int>[...authenticated, ...mac.bytes]`) that duplicate the buffer. Large PDFs
  can cause jank and memory spikes. This also violates the `CONTRIBUTING.md` rule
  to keep hashing and transforms off the UI isolate. Not measured.
- **Plaintext previews**: `decryptToTempFile` writes the decrypted PDF to
  `getTemporaryDirectory()/arcpdf_vault_*`. Cleanup relies on the screen
  (`vault_screen.dart` line 212 caller). A search for startup cleanup of stale
  `arcpdf_vault_` directories found only the creation site, so abnormal
  termination can leave plaintext behind (matches `docs/CODE_AUDIT.md`).
- Moving a file into the vault deletes the source after a length check only; there
  is no decrypt-and-verify round trip before deletion.
- The Android manifest has `android:allowBackup` unset (defaults to true), so
  Auto Backup behavior for the vault directory and secure storage should be
  confirmed. Not verified.
- Test coverage: `test/features/vault/vault_controller_test.dart` (371 lines) and
  `vault_screen_test.dart` (208 lines) exist; `security_settings_dialog.dart` and
  `shared_lock_overlay.dart` have no test referencing them by file name.

Proposed (all need versioning and migration per `CONTRIBUTING.md`): V3 envelope
with a stream-friendly authenticated mode (AES-GCM or chunked AEAD) and separate
keys; PBKDF2/Argon2 or Android Keystore bound secrets for PIN verification with
salt, attempt counter and backoff; move crypto to an isolate with chunked I/O;
cleanup of stale preview directories at startup; verify before deleting sources;
migrate legacy and V1 files on successful unlock with a crash-safe journal.

## 10. Update and release infrastructure

Files: `lib/src/features/updater/updater_service.dart` (253 lines),
`.github/workflows/auto_release.yml`, `android/app/build.gradle.kts`.

### 10.1 In-app updater (confirmed)

- Checks GitHub releases over HTTPS, compares SemVer precedence, selects an asset
  whose name contains `universal` (or has no `arm`/`x86` token), else the first APK
  (lines 148-157). With the current assets the **universal APK (123,540,338 bytes)
  is chosen** instead of the device ABI APK (46,485,439 bytes for ARM64).
- The download uses `connection.get(...)` and `response.bodyBytes`: the whole APK
  is buffered in memory (123.5 MB for universal) before it is written
  (`updater_service.dart` lines 160-177). No progress reporting, no resume, a
  single timeout for the whole body.
- Validation is a ZIP magic check and equality with the API `size`. **No checksum
  verification**, although every release publishes `SHA256SUMS.txt`
  (`ArcPDF-v1.5.157-build.117` contains the sums for APKs and AAB, 519 bytes).
  Android's package installer will still verify the APK signature against the
  installed app.
- Installation uses `install_plugin` and the `REQUEST_INSTALL_PACKAGES` permission.
- Existing optimizations: HTTPS only, no userinfo URLs, staging file with
  `.part` rename, cleanup on failure, stale callback guards (see tests in
  `test/src/features/updater/`).

### 10.2 Release workflow (confirmed on `6c9cb1d`)

- Triggers: push to `Main` and manual dispatch with a version bump input. Push
  builds get tag `v<version>-build.<run>`; manual runs bump `pubspec.yaml` and
  commit it back to `Main`.
- Steps: Java 17, Flutter `3.47.9` (stable), Android packages (platform 36,
  build-tools 36.0.0, NDK `28.2.13676358`), Rust with three Android targets and
  `Swatinem/rust-cache`, then **three separate builds** (universal APK, split
  per-ABI APKs, AAB), all with `--obfuscate --split-debug-info`. Signature and
  native library presence checks run for all four APKs. Release assets: universal
  APK, three ABI APKs, AAB and `SHA256SUMS.txt`. Debug symbols are uploaded as a
  workflow artifact for 30 days (not attached to the release).
- The job requires the signing secrets and fails if missing, so forks and PRs
  cannot build (and the workflow does not run on pull requests at all).
- **No `flutter analyze`, `flutter test` or `cargo test` step** exists in the
  workflow, and there is no other workflow in `.github/workflows/`. Every push to
  `Main` is published as a release without automated test gating.
- Version/`versionCode`: `--build-number` is `github.run_number`; `pubspec.yaml`
  version has no `+build` segment. The README badge shows `1.5.3` while
  `pubspec.yaml` is `1.5.157` (documentation drift).
- Release tags: 89 releases (`gh api repos/MuguDEV/ArcPDF/releases --paginate --jq '.[].tag_name' | wc -l`),
  with irregular naming such as `vtesting1v1`, `v1.23+1d` and `v1.5.157-build.117`.
- `Main` differs only by stricter signature verification and logging in this
  workflow (section 0).
- Release signing in Gradle falls back to the **debug keystore** when
  `ARCPDF_KEYSTORE_PATH` is not set (`build.gradle.kts` signing block), and a stale
  `TODO` comment remains. README states the build is signed with a development key
  until production signing is configured.

### 10.3 Proposed improvements

1. Select the updater asset by `Build.SUPPORTED_ABIS` (through
   `device_info_plus`, already a dependency) and prefer the matching per-ABI APK.
2. Stream the download to the staging file with progress, then verify the SHA-256
   against `SHA256SUMS.txt` from the same release before installing.
3. Add a test workflow (`flutter analyze`, `flutter test`, `cargo test`,
   `git diff --check`) that runs on pull requests and gates the release job.
4. Collapse the three Flutter builds where possible and upload an `--analyze-size`
   artifact per release.
5. Fail release builds that would be signed with the debug key.

## 11. Existing bugs and risks

Static, source-level only. `flutter analyze` could not be run.

- `TODO|FIXME|HACK` search in `lib/`, `native/`, `android/app/src/` and `tool/`:
  no matches. One stale `TODO` exists in `build.gradle.kts` (signing).
- `// ignore` comments in `lib/`: 0.
- `analysis_options.yaml` uses the default `flutter_lints` set with no custom rules.
- Findings recorded earlier in `docs/CODE_AUDIT.md` still open in this tree
  (re-checked in code): unsalted PIN hash without throttling; plaintext vault
  previews can survive process death; structural tools rebuild pages through
  Syncfusion; rename does not migrate every path-keyed cache; updater buffers
  APKs in memory and has no cryptographic verification.
- Newly noted in this audit: updater selects the universal APK; OCR errors are
  swallowed; OCR not cancellable; V1 and legacy vault files remain unauthenticated;
  README version badge `1.5.3` and "Current APK packaging is ARM64-only"
  (README line 357) contradict the release assets; `docs/perf/baseline.md` records
  stale dependency versions and no measurements.
- `ArcPDFProvider` (Storage Access Framework provider) is `exported="true"`
  protected by `android.permission.MANAGE_DOCUMENTS`; this is the standard pattern
  but its content was not audited line by line.
- `MANAGE_EXTERNAL_STORAGE` is requested for whole-device scanning
  (`AndroidManifest.xml`); this is a distribution policy risk for stores, not a
  runtime bug.
- Rust: `panic = "abort"` plus `unsafe extern "C"` entry points
  (`arcpdf_scan_json`, `arcpdf_job_*`); a panic in the native library aborts the
  whole app process. Not reproduced.

## 12. Test coverage

Counted from the tree (static, tests were not run).

- 50 test files under `test/`. `grep` counts: 257 `test(` and 195 `testWidgets(`
  declarations (lines starting with that call, approximate).
- `lib/` has 108 Dart files; **34 of them are never mentioned by file name in
  `test/`**. Largest untested by name: `metadata_editor_page.dart` (434 lines),
  `duplicate_cleanup_page.dart` (295), `images_to_pdf_page.dart` (295),
  `in_app_pdf_selector.dart` (289), `security_settings_dialog.dart` (260),
  `pdf_to_images_page.dart` (241), `split_pdf_page.dart` (236), `main.dart` (166),
  `app.dart` (164), `shared_lock_overlay.dart` (133), `permission_screen.dart`
  (114), `annotation_repository.dart` (76), `android_job_service.dart` (71),
  `bootstrap.dart` (69). Name-based matching can miss tests that exercise a file
  indirectly (for example `tool_pages_test.dart` covers tool pages), so this is an
  upper bound on untested files.
- Rust: 9 `#[test]` functions (`lib.rs` 2, `reflow.rs` 7). **Not run**: `cargo test`
  failed here because the crates.io registry is read-only/unreachable
  (`error: failed to open ... proc-macro2-1.0.107.crate ... Read-only file system`).
- No tests for OCR, the updater asset selection by ABI, startup bootstrap, vault V1
  and legacy migration, or PIN throttling (none exists).
- Kotlin: no unit or instrumentation tests under `android/`.
- Last recorded passing run is the dated snapshot in `docs/CODE_AUDIT.md`
  (`flutter test`: 241 passed, 1 skipped; `flutter analyze`: no issues). That is a
  historical claim, not re-verified.

Proposed: add a CI test workflow (section 10.3), cover the files above in priority
order (bootstrap, updater ABI selection, vault migration, OCR channel fake), and
add Kotlin unit tests for the OCR dimension clamp logic.

## 13. Summary of proposed improvements

See `PROGRESS.md` for the tracking table, with the baseline metric each item must
beat and the verification needed.

## 14. Not measured

| Item | Reason |
| --- | --- |
| Dart AOT per-package size (`--analyze-size`) | Flutter and Dart SDK not installed. |
| Cold start, first frame, first PDF page time | No device, no Flutter. |
| Scroll jank, frame timings, peak and steady memory | No device, no profile build. |
| Tool timings and peak memory (merge, split, rearrange, compress, images, thumbnails) | No device, no benchmark corpus; `docs/perf/baseline.md` values are placeholders. |
| OCR latency, accuracy, memory, model load cost | No device, no scanned corpus. |
| Vault encrypt/decrypt throughput and memory | No Flutter runtime. |
| `flutter analyze` and `flutter test` results | Flutter SDK not installed. |
| `cargo test` results | Crates.io registry unreachable and `~/.cargo` is read-only in this sandbox. |
| ARMv7 and x86_64 per-component sizes | Only ARM64 (and the v1.4.6 ARM64) APKs were downloaded; total asset sizes are in section 1.1. |
| Whether Lucide variable fonts are loaded at runtime | Package source not available offline; only packaging was observed. |
| Effect on size of removing each unused dependency | Needs a build. |
| `hive_generator` / `build_runner` still needed | Not checked for generated `part` files. |
| Source of `org/apache/tika` resources | Dependency graph of Android artifacts not resolvable without Gradle. |
| Play-services OCR alternative size | Needs a build. |
| Real-device behavior of storage permissions, biometrics, installer, process kill | Needs hardware (also stated in `docs/CODE_AUDIT.md`). |
| `docker build` | Repository has no Dockerfile. |

Temporary files used for APK analysis were downloaded outside the repository and
were deleted after the analysis.
