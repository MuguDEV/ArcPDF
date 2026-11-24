# Optimization progress tracker

Companion to [BASELINE.md](BASELINE.md). Audit base: branch `fix/pdfrx-all-apks`
at commit `6c9cb1d` (PR head; PR #108 was later merged into `Main`, and `Main`
differs only in `.github/workflows/auto_release.yml`).

Rules for this table:

- "Baseline" is a value that was measured or read from a named source in
  BASELINE.md. "Not measured" means no baseline exists yet and one must be
  captured before the change.
- "Result" stays empty until a real measurement exists. No result is recorded
  without a command or file that produced it.
- Status values: `proposed`, `in progress`, `done`, `rejected`, `blocked`.

## Phase log

| Phase | Description | Status | Notes |
| --- | --- | --- | --- |
| 0 | Baseline audit and documentation | done | `BASELINE.md`, `PROGRESS.md`. No production code changed. |
| 1 | Downloadable OCR module (Play services unbundled ML Kit) | implemented, device validation pending | See [PHASE_01_OCR.md](PHASE_01_OCR.md). Local ARM64 release APK built and inspected; not committed or released. |
| 1b | Measurement tooling (CI size report, startup trace, benchmarks) | proposed | Needed before most size and speed claims. Formerly listed as Phase 1. |
| 2 | Quick wins (dead dependencies and assets, updater ABI selection) | proposed | |
| 3 | Security hardening (vault format, PIN KDF) | proposed | Needs design and migration plan. |
| 4 | Size reduction decisions (OCR packaging, fonts, engines) | proposed | Needs product decisions. |
| 5 | Test and CI gating | proposed | |

## Baseline metrics

| Metric | Baseline | Source |
| --- | --- | --- |
| ARM64 APK (`v1.5.157-build.117`) | 46,485,439 bytes | release asset size, equals the historical baseline |
| ARMv7 APK | 37,833,033 bytes | release asset size |
| x86_64 APK | 49,221,418 bytes | release asset size |
| Universal APK | 123,540,338 bytes | release asset size |
| AAB | 94,548,167 bytes | release asset size |
| ARM64 APK at `v1.4.6` | 29,874,677 bytes | release asset size |
| `libapp.so` (Dart AOT, ARM64) | 11,010,952 bytes | ZIP directory of the ARM64 APK |
| `libflutter.so` (ARM64) | 11,763,360 bytes | same |
| `libmlkit_google_ocr_pipeline.so` (ARM64) | 11,064,544 bytes | same |
| `libpdfium.so` (ARM64) | 6,598,376 bytes | same |
| `libarcpdf_indexer.so` (ARM64) | 854,696 bytes | same |
| `classes.dex` compressed (ARM64) | 1,255,622 bytes | same |
| ML Kit model assets compressed (ARM64) | 1,272,325 bytes | same |
| Lucide variable fonts compressed (ARM64) | 1,457,296 bytes | same |
| Native libraries total (ARM64) | 41,421,600 bytes (89.1% of 46,485,439; corrected from 29,821,204) | sum of the seven `lib/arm64-v8a` entries in BASELINE.md |
| Packages in `pubspec.lock` | 212 (48 direct main, 8 direct dev, 156 transitive) | `pubspec.lock` |
| Direct dependencies with no import | 8 | grep over `lib/`, `test/`, `tool/` |
| Dart files in `lib/` | 108 | file count |
| `lib/` files not named in `test/` | 34 | static name match, upper bound |
| Rust `#[test]` functions | 9 | `grep -c "#\[test\]"` |
| Dart AOT per-package size | not measured | no Flutter SDK |
| Cold start time | not measured | no device |
| Time to first PDF page | not measured | no device |
| Scroll jank and frame timings | not measured | no device |
| Peak memory (large PDF) | not measured | no device |
| Tool timings and memory | not measured | no device |
| OCR latency and accuracy | not measured | no device |
| `flutter test` / `flutter analyze` / `cargo test` today | not run | tools or registry unavailable |

## Improvement tracker

Priority: H high, M medium, L low. Expected effect is a hypothesis, not a result.

| ID | Area | Proposed improvement | Affected files | Pri | Baseline to beat | Verification needed | Status | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OPT-01 | Updater | Choose the APK for the device ABI instead of the universal APK | `lib/src/features/updater/updater_service.dart`, updater tests | H | Universal asset 123,540,338 bytes vs ARM64 46,485,439 bytes | Unit tests with release fixtures for each ABI; manual install on a device | proposed | |
| OPT-02 | Updater | Stream download to disk with progress and verify SHA-256 from `SHA256SUMS.txt` | `updater_service.dart`, `settings_screen.dart` update flow | H | Whole APK buffered via `response.bodyBytes`; no checksum check | Tests for checksum mismatch, truncated stream, missing sums file | proposed | |
| OPT-03 | CI | Add a PR/push workflow with `flutter analyze`, `flutter test`, `cargo test`, `git diff --check`; gate release on it | `.github/workflows/` | H | No test step in `auto_release.yml`; only one workflow | Workflow run on a PR | proposed | |
| OPT-04 | CI | Publish `--analyze-size` and APK component report per release | `.github/workflows/auto_release.yml` | M | No size tracking; component table in BASELINE.md was made by hand | CI artifact present | proposed | |
| OPT-05 | CI | Reduce three full Flutter builds per release | `.github/workflows/auto_release.yml` | L | Three builds (universal, split, AAB), 90 minute timeout | Compare wall time of consecutive runs | proposed | |
| OPT-06 | Size | Remove 8 direct dependencies with no imports (`animations`, `collection`, `watcher`, `flutter_staggered_grid_view`, `scrollable_positioned_list`, `lottie`, `image_picker`, `sensors_plus`) | `pubspec.yaml`, `pubspec.lock` | M | `libapp.so` 11,010,952; dex 1,255,622 | `flutter pub get`, `flutter analyze`, `flutter test`, rebuilt APK size | proposed | |
| OPT-07 | Size | Remove unused `assets/lottie/` (two identical 56,651 byte files) | `assets/lottie/`, `pubspec.yaml` | L | 9,134 compressed bytes | Rebuilt APK size | proposed | |
| OPT-08 | Size | Drop Lucide variable fonts that no code uses | `pubspec.yaml`, `lib/src/shared/theme/arc_icons.dart` | M | 1,457,296 compressed bytes | Confirm usage in package; rebuilt APK; icon golden or widget tests | proposed | |
| OPT-09 | Size | Decide on bundled versus on-demand ML Kit OCR | `android/app/build.gradle.kts`, `ReflowOcrChannel.kt`, README privacy text | H | 12,336,869 bytes (library plus models) | Product decision on offline guarantee; rebuilt APK; OCR on device | implemented, device validation pending | Local ARM64 APK 36,093,306 bytes, 10,392,133 below 46,485,439 (not a like-for-like CI build, see PHASE_01_OCR.md). OCR library and model assets absent. OCR on device not run. |
| OPT-10 | Size | Evaluate Syncfusion removal by moving remaining tools to the Rust/PDFium runtime | `tools_service.dart`, `native/arcpdf_indexer/src/lib.rs`, `pubspec.yaml` | M | Syncfusion cost not measured | `--analyze-size` before and after; tool regression tests | proposed | |
| OPT-11 | OCR | Add cancellation and progress, distinguish OCR failure from empty text | `ReflowOcrChannel.kt`, `reflow_ocr_service.dart`, `reflow_engine.dart` | M | Recognizer created per call; no cancel; errors become empty list | Fake-channel tests; device timing | implemented, device validation pending | Cancellation, progress and structured errors added; recognizer is created per request and closed after its task completes. 48 JVM tests pass; new Dart tests pass. Device timing not measured. |
| OPT-12 | Startup | Open independent Hive boxes concurrently or lazily; make `AppDiagnostics.install()` single-call | `lib/src/bootstrap.dart`, `lib/main.dart` | M | 11 boxes opened sequentially; cold start not measured | Capture cold start before change on a device | proposed | |
| OPT-13 | Startup | Add startup trace markers and record baseline | `bootstrap.dart`, `app.dart`, new doc | H | not measured | `flutter run --profile --trace-startup` on a device | proposed | |
| OPT-14 | Rendering | Add frame timing and memory capture for the reader; scale cache by `memoryClass` | `pdf_viewer_screen.dart`, `settings_controller.dart` | M | Not measured | Profile build on a device with benchmark PDFs | proposed | |
| OPT-15 | Rendering | Split `pdf_viewer_screen.dart` (3,423 lines) after profiling shows rebuild cost | `pdf_viewer_screen.dart` | L | 3,423 lines | Widget tests unchanged, profile compare | proposed | |
| OPT-16 | Tools | Report before and after size for compression; add a no-savings outcome | `tools_service.dart`, `tool_action_dialog.dart` | M | Output can be larger than input (`docs/CODE_AUDIT.md`) | Tests with incompressible input | proposed | |
| OPT-17 | Tools | Log which engine (native or Syncfusion) ran each job | `tools_service.dart`, `native_job_runtime.dart` | L | Unconfirmed | Log assertion test | proposed | |
| OPT-18 | Tools | Deterministic benchmark harness for tools, thumbnails and scanner | `tool/` | H | All values in `docs/perf/baseline.md` are placeholders | Run on a device, record time and peak RSS | proposed | |
| OPT-19 | Vault | Versioned authenticated format (V3) with separate keys and chunked streaming; migrate legacy and V1 files crash-safely | `vault_controller.dart` | H | V2 has HMAC; legacy and V1 unauthenticated; whole file in memory | Tamper, truncation, migration and kill-during-migration tests | proposed | |
| OPT-20 | Vault | Move vault crypto off the UI isolate | `vault_controller.dart` | M | Sync encrypt/HMAC on UI isolate; throughput not measured | Benchmark with a large PDF; jank check | proposed | |
| OPT-21 | Vault | Clean stale `arcpdf_vault_*` preview directories at startup | `vault_controller.dart`, `app.dart` | M | Only created, never swept at startup | Test with seeded stale directory | proposed | |
| OPT-22 | Security | Salted slow KDF and attempt throttling for PIN and pattern | `security_controller.dart` | H | Unsalted SHA-256, no throttle, string `==` | Migration test, throttle test, constant-time compare | proposed | |
| OPT-23 | Security | Confirm `allowBackup` policy for vault and secure storage | `AndroidManifest.xml` | M | `allowBackup` unset | Decide, then manifest test or doc | proposed | |
| OPT-24 | Tests | Cover untested lib files in priority order (bootstrap, updater ABI, vault migration, OCR channel, security dialog) | `test/` | M | 34 of 108 lib files not named in tests; 0 OCR tests | `flutter test` | proposed | |
| OPT-25 | Tests | Kotlin unit tests for OCR dimension clamp and job recovery | `android/app/src/test/` | L | No Kotlin tests | Gradle unit test run | done | 48 tests, 0 failures (`:app:testDebugUnitTest`). |
| OPT-26 | Docs | Fix README drift (badge `1.5.3` vs `1.5.157`, "ARM64-only" claim) and mark `docs/perf/baseline.md` as stale | `README.md`, `docs/perf/baseline.md` | L | README line 357 contradicts release assets | Review | proposed | |
| OPT-27 | Build | Fail release builds signed with the debug key; remove stale TODO | `android/app/build.gradle.kts` | M | Falls back to debug signing when env is unset | Build without secrets fails | proposed | |
| OPT-28 | Native | Evaluate crash isolation for the Rust runtime (`panic = "abort"`) | `native/arcpdf_indexer/Cargo.toml`, `lib.rs` | L | Panic aborts the process; not reproduced | Fault-injection test | proposed | |

## Environment limits for the baseline phase

- No Flutter or Dart SDK: no analyzer, tests, size analysis or profile builds.
- No Android device or emulator: no startup, rendering, memory or OCR numbers.
- `cargo test` failed: crates.io index and registry cache are read-only or
  unreachable here.
- GitHub REST access worked and was used for release asset sizes and for
  downloading the two ARM64 APKs that were inspected.

## Update log

| Date | Entry |
| --- | --- |
| Baseline phase | Created from the audit of commit `6c9cb1d`. No improvement implemented. |
| Phase 1 | Downloadable OCR implemented on `feat/phase-01-downloadable-ocr`. Native library total in this file corrected to 41,421,600 bytes. Not released. |
