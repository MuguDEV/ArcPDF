# Phase 1: downloadable OCR module

Branch `feat/phase-01-downloadable-ocr`. Companion to [BASELINE.md](BASELINE.md)
and [PROGRESS.md](PROGRESS.md). Status: implemented, uncommitted at the time of
writing, device validation pending. Nothing was released or merged, and Phase 2
was not started.

## Summary

The bundled ML Kit text recognizer (`com.google.mlkit:text-recognition`, which
shipped `libmlkit_google_ocr_pipeline.so` and `assets/mlkit-google-ocr-models`,
12,336,869 bytes in the ARM64 baseline) is replaced by the unbundled Google
Play services variant. Google Play services downloads the model once, after
which recognition runs on the device. The OCR code path was also made
cancellable, observable and failure-aware.

## Changed files

Android:

- `android/app/build.gradle.kts`: dependency swap and exclusion.
- `android/app/src/main/kotlin/com/arcpdf/app/OcrModuleManager.kt` (new): state
  machine, gateway and scheduler interfaces.
- `.../OcrModuleChannel.kt` (new): Play services gateway, main-thread
  scheduler, channel `com.arcpdf.app/ocr_module`.
- `.../OcrRequestSupport.kt` (new): error codes, request registry and tokens,
  page loop, resource gate, dimension computation, `OcrRequestRunner` (request
  ownership and reply ordering) and `OcrPageStep` (per-page recognition with
  resource gates), both behind small interfaces so they run in JVM tests.
- `.../ReflowOcrChannel.kt` (rewritten), `.../MainActivity.kt` (registration,
  cleanup, resume recheck).
- `android/app/src/test/kotlin/com/arcpdf/app/` (new): `OcrModuleManagerTest`,
  `OcrRequestSupportTest`, `OcrRequestRunnerTest`.

Dart:

- `lib/src/features/pdf/data/reflow_ocr_service.dart`: typed results, request
  ids, cancellation, progress.
- `lib/src/features/pdf/data/reflow_engine.dart`: `loadWithStatus`, no second
  native pass on OCR failure. `load()` still returns `ReflowDocument`.
- `lib/src/features/pdf/data/ocr_module_controller.dart` (new).
- `lib/src/features/settings/settings_controller.dart`, `settings_screen.dart`:
  `enableOcr`, `ocrBackgroundDownload`, "Text recognition" group.
- `lib/src/features/pdf/viewer/pdf_viewer_screen.dart`: reader prompt card,
  progress text, cancel on dispose.
- `lib/src/app.dart`: background deferred install after onboarding.
- Tests: `test/features/pdf/reflow_ocr_service_test.dart`,
  `ocr_module_controller_test.dart`, `test/src/features/settings/ocr_settings_test.dart`,
  and an OCR group in `test/features/pdf/reflow_engine_test.dart`.

Docs: `BASELINE.md` (native library total corrected), `PROGRESS.md`, this file,
and one README feature bullet that previously said OCR was bundled.

## Dependency changes

| Before | After |
| --- | --- |
| `com.google.mlkit:text-recognition:16.0.1` | `com.google.android.gms:play-services-mlkit-text-recognition:19.0.2` |
| (transitive) | `com.google.android.gms:play-services-base:18.5.0` (for `ModuleInstall`) |
| none | `testImplementation junit:junit:4.13.2` |

`configurations.all` excludes group `com.google.mlkit`, module
`text-recognition`, so a transitive dependency cannot bring back the bundled
library. `./gradlew :app:dependencies --configuration releaseRuntimeClasspath`
shows only the Play services artifacts plus `com.google.mlkit:common`,
`vision-common` and `vision-interfaces`.

The manifest `com.google.mlkit.vision.DEPENDENCIES` meta-data is intentionally
omitted. It makes Google Play download the module at app install time, which
would hide the download from the app and give no chance to respect the user's
OCR and background-download settings. The app requests the module itself.

No pubspec change. Native library compression and signing configuration are
untouched. `minSdk` stays `flutter.minSdkVersion` (24 with Flutter 3.47.9). The
unbundled API needs 23, so no raise is needed; a runtime guard
(`SDK_INT >= 23` and Play services check) maps unsupported cases to
`UNSUPPORTED`.

## OCR module lifecycle

States: `CHECKING`, `NOT_INSTALLED`, `WAITING`, `DOWNLOADING`, `READY`,
`FAILED`, `UNSUPPORTED`. Readiness is never persisted. Every start, resume and
explicit check re-queries Play services (`areModulesAvailable`), so a restart
recovers from the real state.

Transitions:

- `CHECKING` to `READY` if the module is present, `NOT_INSTALLED` if missing,
  `UNSUPPORTED` if Play services or API level is unavailable, `FAILED` if the
  query errors.
- `NOT_INSTALLED` to `WAITING` or `DOWNLOADING` when an install request starts.
  `WAITING` is Play services holding the request (for example waiting for Wi-Fi
  or storage).
- `DOWNLOADING` to `READY` on completion, to `FAILED` on error or cancel.
- `FAILED` to `CHECKING` on retry.

Install paths:

- Deferred (`deferredInstall`): used by the post-onboarding background request.
  Play services chooses timing and network. Never uses `installNow`.
- User (`installModules` with an install status listener): used by "Download
  now" and the reader prompt. Reports progress only when
  `totalBytesToDownload > 0`. Otherwise progress is null and the UI shows an
  indeterminate indicator with no percentage.

Reliability: one in-flight request is shared by duplicate calls. After a
failure the manager retries after 2 s, 4 s, 8 s and 16 s (four retries, five
attempts in total), on a cancellable handler. An explicit retry resets the
budget. The listener is unregistered on terminal states and on dispose.
Restart recovery: a new manager re-queries, so it reaches `READY` or
`DOWNLOADING` from Play's state. Play offers no completion signal for deferred
installs, so after a restart a pending deferred request shows `NOT_INSTALLED`
until Play reports it available; the resume recheck picks up completion.

The resume recheck also covers a user install whose terminal update was lost
(for example after Play services restarts): while an install is in flight the
check runs quietly. It switches to `READY` on a positive answer and otherwise
changes nothing, including on query errors. Rechecks from `WAITING`,
`DOWNLOADING` or `READY` do not pass through `CHECKING`, so the Settings row
does not flicker.

A `WAITING` snapshot carries `deferred: true` when it comes from a deferred
request. In that state the reader prompt and Settings offer "Download now",
which replaces the deferred wait with a user install. A `WAITING` state from a
user install offers no button. Each failure cancels any pending retry timer
before it schedules the next, so there is always at most one timer.

Turning `enableOcr` or `ocrBackgroundDownload` on after onboarding requests the
background install right away (when the module is not installed), without a
restart.

The Dart controller mirrors the native state, returns `unsupported` off Android
or on `MissingPluginException`, refreshes on app resume, deduplicates in-flight
calls, and never calls install when `enableOcr` is off.

## Reliability fixes in recognition

- Request ids, `cancelOcr(requestId)` and `cancelAll` (on document close). A
  queued request for a cancelled id completes with `ocr_cancelled` and does not
  run. Cancellation is checked before each page and after rendering.
- Progress events `{requestId, page, done, total}` only while a request is
  active. Results are never published for a cancelled or closed request.
- Structured errors replace the old empty-list fallback:
  `ocr_invalid_request`, `ocr_unsupported_device`, `ocr_module_missing`,
  `ocr_cancelled`, `ocr_timeout` (45 s per page), `ocr_permission_denied`,
  `ocr_recognition_failed`. A page with no text returns `lines: []` and is not
  an error. The old codes `invalid_ocr_request` and `ocr_failed` are gone.
- Module availability is checked before recognition, so a missing module fails
  with `ocr_module_missing` instead of returning empty text.
- Engine ownership: `ReflowOcrChannel` is a process-wide singleton. `register`
  records the engine's messenger as owner (`OcrOwnerGuard`), and `unregister`
  only tears down when called with the current owner, so a late call from an
  old engine or activity cannot remove a newer registration.
- Resource ownership: one recognizer per request. On timeout the bitmap is not
  recycled and the recognizer not closed until the in-flight task completes.
  `PdfRenderer`, page and file descriptor are closed in the worker. If ML Kit
  never completes a task after a timeout, that bitmap and recognizer stay
  allocated until the process ends, because freeing them while the task may
  still read them is unsafe. The request still fails with `ocr_timeout` and the
  worker moves on. Not measured on a device.
- Reply bookkeeping lives in `OcrRequestRunner`: the reply entry is removed
  before the request id is released, so a request that reuses the id cannot
  lose its reply. Cancellation of a running request takes effect between pages;
  the Dart reply is immediate, but the single worker stays busy until the
  current page ends or times out (45 s at most), so a queued request waits.
- The result map format and the adaptive `maxDimension` rules (1600 low RAM,
  1900 if `memoryClass < 192`, clamp 1200..3200, scale `min(2.5, max/longest)`)
  are unchanged.
- Dart no longer swallows `PlatformException` as empty text. When OCR is needed
  but unavailable, the reader gets the native-text reflow and an `ocrStatus`,
  and shows a prompt instead of "No selectable text". A failed or cancelled OCR
  run does not trigger the second native pass that writes the OCR cache, so a
  failure is not cached as complete. `cacheKey` and `engineVersion` are
  unchanged.

## Privacy and one-time internet requirement

Recognition runs on the device and page images are not uploaded. The first OCR
use needs internet once to download the module. Google Play services controls
the actual delivery: timing, size, network policy (it may defer to Wi-Fi), and
whether a manual download may use mobile data. ArcPDF only requests the module
and reports the state Play services gives it. After the module is present, OCR
works offline until Play services removes the module (for example under storage
pressure), at which point the state returns to not installed and the app can
request it again.

## Compatibility limitations

- Devices without Google Play services (Huawei and other GMS-less devices,
  some custom ROMs, emulator images without Play) get `UNSUPPORTED`. OCR is
  unavailable there. All other PDF features keep working, and the settings and
  reader messages say so.
- Play services disabled or too old behaves the same way.
- `minSdk` is 24, above the API 23 requirement. No change.
- Latin script only, as before.
- Users who relied on first-run offline OCR on a never-connected device lose
  that behavior.

## Optional bundled-OCR build: evaluation

Recommendation only. Not implemented, and the release matrix is not expanded.

- Cost: a second flavor would add about 12.3 MB to the ARM64 APK (the baseline
  library plus models, 12,336,869 bytes) and double the CI builds that already
  run three per release.
- Benefit: OCR for GMS-less and fully offline devices.
- Recommendation: do not add a flavor now. Ship the downloadable build, collect
  how many users hit `UNSUPPORTED` or `ocr_module_missing`, and only then decide
  on a separate bundled flavor or a Play-independent engine (for example Tesseract
  as an optional download) with its own size and accuracy measurement.
  If one is added, keep it as a Gradle product flavor that swaps one dependency
  and keeps the same channel contract, so Dart code is identical.

## Tests executed

Environment: Flutter 3.47.9, JDK 17, Android SDK 36, NDK 28.2.13676358.

- `./gradlew :app:compileDebugKotlin` (with `-x buildRustIndexer`): succeeded.
- `./gradlew :app:testDebugUnitTest`: 48 tests, 0 failures (23 in
  `OcrModuleManagerTest`, 13 in `OcrRequestSupportTest`, 12 in
  `OcrRequestRunnerTest`). Plain JVM tests with a faked Play services gateway,
  executor and ML Kit task. `ReflowOcrChannel` itself (PdfRenderer, Bitmap, ML
  Kit calls) is still not under JVM test; its ownership and reply logic is.
- `flutter analyze`: 13 issues, all pre-existing `deprecated_member_use` infos,
  none new.
- `flutter test --timeout 60s`: all pass except 5 failures that also occur on
  the unmodified tree (baseline run: 521 passed, 4 skipped, 5 failed):
  `pdf_custom_card_test.dart` and `settings_screen_test.dart` (setUpAll needs
  `roboto-regular.ttf`, absent from this Flutter distribution; with a symlink to
  `Roboto-Regular.ttf` outside the repo both pass), `intent_service_test`
  "opens only the first valid PDF in a batch", and two `pdf_viewer_screen_test`
  cases ("fast flings travel farther..." and "leaving before the next frame
  saves page zoom and exact position"). These were not diagnosed.
- New Dart tests: 10 (OCR service), 11 (module controller), 9 (settings flags
  and UI), 7 (engine OCR group). The reader prompt card has no widget test.
- Not run: any device or emulator test, real Play services download, OCR
  accuracy or timing, `cargo test`.

## APK validation

Command (env: `source .tools/env.sh`, `GRADLE_USER_HOME=$HOME/.gradle`,
`ARCPDF_ABIS=arm64-v8a`, a writable `RUSTUP_HOME` and `CARGO_HOME` with the
`aarch64-linux-android` target because `/root/.rustup` is read-only here):

```
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Result: built `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
Signing used the debug fallback (`ARCPDF_KEYSTORE_PATH` unset): `apksigner
verify` reports "Verifies", v2 scheme, signer `CN=Android Debug`. Release
signing config was not touched. `aapt2 dump badging`: package
`com.arcpdf.app`, minSdk 24, targetSdk 36, versionName 1.5.157.

| Check | Result |
| --- | --- |
| APK size | 36,093,306 bytes |
| Baseline ARM64 APK | 46,485,439 bytes |
| Difference | 10,392,133 bytes smaller (22.4%) |
| `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` | absent |
| `assets/mlkit-google-ocr-models` | absent (no entry with that path) |
| `libpdfium.so` | present, 6,598,376, stored |
| `libarcpdf_indexer.so` | present, 882,440, stored |
| `libflutter.so` | present, 11,763,360, stored |
| `libapp.so` | present, 13,042,568, stored |
| Other libs | `libdartjni.so`, `libpdfrx_pdfium_gate.so` present |
| Native libs total (uncompressed) | 32,416,416 bytes |
| `classes.dex` compressed | 1,173,331 bytes |

Lib entries remain stored (uncompressed), the same packaging as the baseline;
native library compression was not enabled. Only `arm64-v8a` libs are present.

Caveats on the size comparison. The 46,485,439 baseline is the CI release
asset; this APK is a local build with the debug signing fallback, so it is not
a like-for-like measurement. Two components differ from the baseline for
reasons not isolated here: `libapp.so` is 13,042,568 bytes versus 11,010,952 in
the baseline (+2,031,616), and `libarcpdf_indexer.so` is 882,440 versus 854,696.
The Phase 1 Dart changes add code, but the full `libapp.so` growth was not
attributed. The reduction therefore is a measured difference between two
different builds. Confirm with the CI procedure below on the same commit
without and with the change. The OCR library and models alone account for
12,336,869 bytes in the baseline; the measured net saving is lower because of
the growth above.

## CI validation procedure

Use `.github/workflows/auto_release.yml` as the reference (Flutter 3.47.9,
Java 17, Rust Android targets, universal and per-ABI APKs). On a branch or
`workflow_dispatch` run that builds the PR head, then also build the merge base
the same way, and compare.

1. `flutter pub get`
2. `flutter build apk --release --split-per-abi` (same flags as the workflow)
3. Run the inspection script on each APK:

```python
import os, sys, zipfile
apk = sys.argv[1]
z = zipfile.ZipFile(apk)
print("size", os.path.getsize(apk))
bad = [i.filename for i in z.infolist()
       if "mlkit_google_ocr" in i.filename or "mlkit-google-ocr-models" in i.filename]
print("OCR bundled entries:", bad or "none")
for abi in sorted({n.split("/")[1] for n in z.namelist() if n.startswith("lib/")}):
    for lib in ("libpdfium.so", "libarcpdf_indexer.so", "libflutter.so", "libapp.so"):
        n = f"lib/{abi}/{lib}"
        try:
            i = z.getinfo(n)
            print(n, i.file_size, i.compress_size, "stored" if i.compress_type == 0 else "deflated")
        except KeyError:
            print("MISSING", n)
```

4. `apksigner verify --print-certs <apk>` with the release keystore secrets set;
   the signer must be the release key, not `CN=Android Debug`.
5. Pass criteria: no OCR entries, the four libs present per ABI and stored,
   release signer, size lower than the merge-base APK of the same ABI.

## Outstanding device validation

None of these were run.

- Fresh install: first OCR use, background deferred download after onboarding.
- Upgrade from the bundled build: OCR prompt appears, download completes, OCR
  then works; cached OCR results remain valid (cache key unchanged).
- Airplane mode: not installed state, clear message, retry succeeds once online.
- Metered network: Play services behavior for deferred and manual downloads.
- Play services disabled or absent: `UNSUPPORTED`, other features unaffected.
- Low RAM device: dimension limits, no OOM, on a large scan.
- Large scanned PDF: cancel mid-run, close the document during OCR, confirm no
  late results, no leaked recognizer, and responsive UI.
- Process death during download, then relaunch: state recovers from Play.
- Release-signed APK installs over the previous release (signature match).
