# Phase 2.5: build acceleration

Status: implemented, CI and device validation pending. Branch
`feat/phase-02-5-build-speed`. Nothing here was run in CI or on a device, and no
build timing was measured in the authoring environment (see [Measurements](#measurements)).

Companion to [PROGRESS.md](PROGRESS.md), [BASELINE.md](BASELINE.md) and
[PHASE_02_PACKAGING.md](PHASE_02_PACKAGING.md).

## Per-ABI Rust tasks and output layout

The single `buildRustIndexer` task is replaced by one task per ABI, defined in
`android/buildSrc/src/main/kotlin/com/arcpdf/build/` (`RustIndexerTasks.kt`,
`BuildRustAbiTask.kt`, `RustAbi.kt`). `buildRustIndexer` remains as an aggregate
that depends on the selected per-ABI tasks, so existing callers keep working.

- Each task declares the crate sources, `Cargo.toml`, `Cargo.lock`, `build.rs`,
  `.cargo/config*`, the NDK version, the PDFium revision and the resolved PDFium
  library as inputs. Gradle can therefore mark it UP-TO-DATE or run it alone when
  only one ABI is affected.
- Output directory: `build/app/generated/rustJni/<abi>/<abi>/` (relative to
  `android/`), holding `libarcpdf_indexer.so` and `libpdfium.so`. This replaces
  `build/generated/rustJniLibs/<abi>`. The old path still appears in the
  historical sections of BASELINE.md and PHASE_02_PACKAGING.md, each with a note.
- The ABIs are `arm64-v8a`, `armeabi-v7a` and `x86_64`. `x86` is not built.

## ABI synchronization

`AbiSelection.kt` combines `ARCPDF_ABIS` (Gradle property or environment) with
Flutter's `target-platform` property:

| Input | Result |
| --- | --- |
| Neither set | All three ABIs. |
| Only `ARCPDF_ABIS` | Build those ABIs. The root build script sets `target-platform` to the matching Flutter names (`android-arm64`, `android-arm`, `android-x64`) before `:app` applies the Flutter plugin, so engine and Dart AOT libraries match the native libraries. |
| Only `target-platform` | Build the ABIs it names. |
| Both set | Every Flutter platform must be covered by `ARCPDF_ABIS`, otherwise the build fails with an explicit message. `ARCPDF_ABIS` may list more than Flutter packages; only the packaged ones are built. |
| Unknown name in either | Build fails, listing the supported values. |

An incompatible set (Flutter packages an ABI that `ARCPDF_ABIS` does not build)
is rejected, not silently completed. Covered by the 8 `AbiSelection` JUnit tests.

## Cargo target directories and job budget

- Each triple gets a persistent directory `.arc-build/cargo-target/<triple>`
  (override the base with `ARCPDF_RUST_TARGET_DIR`). Separate directories avoid
  Cargo build-lock contention between parallel ABI tasks and keep incremental
  state between builds. `.arc-build` is ignored by git.
- `CARGO_BUILD_JOBS` is budgeted by `CargoSettings.jobs`: `ARCPDF_CARGO_JOBS` or
  `CARGO_BUILD_JOBS` wins; otherwise CPUs are divided evenly by the number of
  selected ABIs, minimum 1.

## PDFium resolution and ELF validation

- `PdfiumResolver.kt` finds `pdfium_dart` through `.dart_tool/package_config.json`
  and reads the pinned `pdfiumRelease` constant from the package source
  (`lib/src/pdfium_archive_integrity.dart`, then `hook/build.dart`). Only the
  directory for that revision under
  `.dart_tool/hooks_runner/shared/pdfium_dart/build` is accepted. A different
  revision in the cache is never used as a fallback, and a missing one fails
  with a message pointing at `flutter pub get` and the Flutter native-assets step.
- `ElfValidator.kt` checks every staged library: ELF magic, class (32 or 64 bit)
  and little-endian, `e_machine` for the ABI, program header table bounds, each
  `PT_LOAD` segment (bounds, `p_filesz <= p_memsz`, alignment, and
  `p_vaddr % p_align == p_offset % p_align`). 64-bit ABIs require 16 KB alignment,
  32-bit require 4 KB. Both `libarcpdf_indexer.so` and
  `libpdfium.so` are validated with 16 KB enforcement for 64-bit ABIs, and a missing
  16 KB alignment fails the build (no warn-only mode). Residual risk: the alignment of
  the PDFium binary at the revision pinned by `pdfium_dart` could not be verified in
  the sandbox (no Flutter cache). If that revision is only 4 KB aligned, the first
  64-bit build fails and the pin must be bumped.

## Gradle defaults and worker policy

`android/gradle.properties`: `-Xmx3g`, metaspace 768m, code cache 256m, parallel,
build cache, daemon and file-system watching on, `org.gradle.workers.max=4`.

`tool/ci_gradle_workers.sh` writes `org.gradle.workers.max` into
`$GRADLE_USER_HOME/gradle.properties` (other keys untouched) and exports
`ARCPDF_CARGO_JOBS` (half the workers, minimum 1) through `GITHUB_ENV` when not
already set:

| RAM | Workers | Always |
| --- | --- | --- |
| below 8 GB | 2 | capped by CPU count, minimum 1 |
| 8 to 16 GB | 4 | |
| above 16 GB | 8 | |

`--print` only prints the number. `ARCPDF_TEST_MEM_GB` and `ARCPDF_TEST_CPUS`
override detection for tests.

### Configuration cache

`org.gradle.configuration-cache=false` is kept. Flutter's Gradle plugin
(`ReleaseMinSdkCheck`) is not compatible with the configuration cache, so
enabling it would fail or be unreliable. This is optional and not adopted.
`sccache` was also not adopted: the Rust build is a small crate and the
per-triple persistent target directories already provide incremental reuse.

## Local scripts

- `tool/setup_android_sdk.sh`: installs only the missing packages (platform
  `android-36`, build-tools `36.0.0`, NDK `28.2.13676358`) in one `sdkmanager`
  call. A package counts as installed only when `package.xml` and key files
  exist. `ARCPDF_SKIP_PRECACHE=1` skips `flutter precache`. Source it to put the
  pinned build-tools on `PATH`.
- `tool/build_android.sh <debug|preview|preview-compressed|full> [flutter args]`
  and the PowerShell twin `tool/build_android.ps1`. `debug` and `preview*` build
  arm64-v8a only; `full` builds all ABIs (override with `ARCPDF_ABIS`).
  `flutter pub get` runs only when the hash of `pubspec.yaml` and `pubspec.lock`
  differs from `.arc-build/pubspec.hash`; `flutter clean` is never run.

## Workflow map

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `ci.yml` | push to `Main`, pull request, manual | `changes` job decides if code jobs run. Then `analyze`, `flutter-test`, `rust-test`, `kotlin-build-logic-test` (buildSrc), `kotlin-app-test`, `python-test`. Docs-only and validator-only changes skip Flutter, Rust and Kotlin jobs; python tests always run. No signing or secrets. |
| `preview.yml` | manual | Non-publishing release-mode APK (arm64 or all ABIs, optional native compression) signed with a throwaway key. Must not be distributed. |
| `auto_release.yml` | push to `Main`, manual | `build` (compile, sign, package, upload artifact), `validate` (checksums, native libraries, signing certificate on the packaged files), `publish` (version bump commit and GitHub Release, needs both). The keystore is decoded only in the job that needs it and never uploaded. |
| `packaging_compare.yml` | manual | ARM64-default switch-on/off packaging comparison, split into `build` and `validate`, with artifacts verified by run id. |
| `packaging_validate.yml` | manual, input `run_id` (optional `expected_sha`) | Re-validates the artifact of an earlier run without rebuilding. No Flutter or Rust setup, read-only permissions. |

### Validation-only change path

When only the validators change (`tool/apk_packaging_*.py`, `tool/tests/**`),
do not rebuild. Run `packaging_validate.yml` with the `run_id` of an earlier
`packaging_compare.yml` run. Runs from fork pull requests are rejected because
their artifacts are untrusted.

## Cache table

One mechanism per category; no category is cached twice.

| Category | Mechanism | Notes |
| --- | --- | --- |
| Flutter SDK and pub | `subosito/flutter-action` (`cache: true`) | |
| Gradle | `gradle/actions/setup-gradle@v4` | Read-only unless the ref is `Main`. |
| Rust | One `Swatinem/rust-cache@v2` step per ABI, shared keys `arcpdf-arm64`, `arcpdf-armv7`, `arcpdf-x64`, each mapped to `.arc-build/cargo-target/<triple>` | Saved only on `Main`. `preview.yml` restores only the key for the selected ABI. `cache-bin: false` limits per-step extras, but each step still stores its own `~/.cargo` registry copy (small, one lockfile). `rust-test` uses the default `target`. |
| Java | `actions/setup-java` | No cache. |
| Local builds | Gradle build cache and `.arc-build/cargo-target` | Persist across runs. |

## Bundletool decision

Retain the Flutter APK builds. Generating APKs from the AAB with bundletool was
not adopted because equivalence with shipped APKs could not be shown or tested
here, and standalone APKs may name and compress native libraries differently,
need explicit keystore and `versionCode` handling, and would need new validators.
Full reasons are in [PHASE_02_PACKAGING.md](PHASE_02_PACKAGING.md) under
"Bundletool decision". The three builds in the release job use identical flags
apart from packaging mode, so Gradle and Cargo outputs are reused on the runner.

## Residual risks

- ABI sync depends on property ordering: `target-platform` is set before `:app`
  applies the Flutter plugin. A Flutter plugin change that reads the property
  earlier or from another place would break the sync.
- `kotlin-app-test` has never been run.
- The new and changed workflows have not run on GitHub. actionlint passes only.
- The Rust pin `1.92.0` is the compiler the lockfile was built with locally. It
  has not been verified that `dtolnay/rust-toolchain` accepts `1.92.0` as a
  toolchain input on GitHub runners.
- `dtolnay/rust-toolchain@master` is used so the toolchain can be passed as an
  input. `@master` is a moving reference, not a pinned release.
- `tool/build_android.ps1` was not run (no PowerShell here). `shellcheck` was
  unavailable.

## Measurements

### Historical timings (NOT current measurements)

The following were recorded in a previous session on a different environment,
before this phase. They are not results of this phase, do not compare like for
like, and must not be read as before and after numbers.

| Scenario | Seconds (previous session) |
| --- | --- |
| Cold build | 518 |
| Unchanged rebuild | 29.6 |
| Dart-only change | 68.9 |
| Kotlin-only change | 28 |
| Rust-only change | 20.6 |
| Asset-only change | 11.2 |

### Unavailable in this environment

No Flutter SDK, Android SDK or NDK, and no JDK 17. Therefore not measured:

- ARM64 release build
- Unchanged rebuild
- Dart-only rebuild
- Rust-only rebuild
- Gradle task-graph dry runs
- UP-TO-DATE verification

### Validations that were run

| Check | Result |
| --- | --- |
| `python3 -m unittest discover -s tool/tests` | 64 tests OK |
| `cargo test` (native/arcpdf_indexer) | 9 tests OK |
| buildSrc JUnit, run standalone with Gradle 9.1.0 | 33 pass (ElfValidator 14, AbiSelection 8, CargoSettings 4, PdfiumResolver 7) |
| `actionlint` | clean on all workflows |
| `bash -n` and stubbed runs of the `tool/*.sh` scripts | pass |
| Worker selection (16 CPUs) | 4 GB gives 2, 12 GB gives 4, 32 GB gives 8 |

### How to run the measurements

On a machine with Flutter, JDK 17 and the Android SDK:

```sh
source tool/setup_android_sdk.sh
flutter pub get
# cold ARM64 release build
time tool/build_android.sh preview
# unchanged rebuild
time tool/build_android.sh preview
# Dart-only: edit a file under lib/, then
time tool/build_android.sh preview
# Rust-only: edit native/arcpdf_indexer/src/lib.rs, then
time tool/build_android.sh preview
# task graph and UP-TO-DATE checks (second run should show UP-TO-DATE)
gradle -p android :app:buildRustIndexer --dry-run
gradle -p android :app:buildRustIndexer --console=plain
```

Restore any temporary edit after each run and record the command, the machine
and the number together.

## Review follow-ups

- `ci.yml` runs buildSrc tests with `gradle -p android/buildSrc test`, which needs no Flutter.
- `sdkmanager` license input uses `< <(yes)` so `yes` cannot trigger SIGPIPE (exit 141) under `pipefail`.
- `target-platform` injection and `kotlin-app-test` gating are not changed. The injection only affects direct Gradle runs and needs a real run with `-PARCPDF_ABIS=arm64-v8a` to confirm an arm64-only APK. `kotlin-app-test` stays informational until it has passed once, then should be made blocking.
