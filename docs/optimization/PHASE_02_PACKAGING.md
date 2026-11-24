# Phase 2: configurable native library compression

Status: implemented and measured locally, **experimental, default OFF**.
Production acceptance is **pending** (no device or emulator was available).

Base: branch `feat/phase-02-native-compression`, created from
`feat/phase-01-downloadable-ocr` (PR #110, not merged into `Main` when this
work was done). Phase 1 is therefore part of the baseline here.

## Changed files

| File | Change |
| --- | --- |
| `android/app/build.gradle.kts` | New `ARCPDF_COMPRESS_NATIVE_LIBS` switch wired to `packaging.jniLibs.useLegacyPackaging`. |
| `tool/apk_packaging_report.py` | Read-only report: sizes, ZIP method, ELF `p_align`, `apksigner verify`, `zipalign -c -P 16`. Runs locally and in CI. |
| `.github/workflows/packaging_compare.yml` | New non-publishing A/B workflow. |
| `docs/optimization/PHASE_02_PACKAGING.md`, `PROGRESS.md` | This document and the tracker. |

`auto_release.yml` is **not** changed. The production release keeps the default
(modern, uncompressed) packaging.

## Packaging configuration

Findings from inspection:

- Native libraries reach the APK through three routes: Flutter engine and
  `libapp.so` (Flutter Gradle plugin), the plugin JNI libs (`libdartjni.so`,
  `libpdfrx_pdfium_gate.so`), and the `buildRustIndexer` task, which copies
  `libarcpdf_indexer.so` and `libpdfium.so` into `build/generated/rustJniLibs/<abi>`
  (registered as a `jniLibs` source dir). All six end up as ordinary `lib/<abi>/*.so`
  entries, so one AGP setting governs all of them (verified in the table below).
- `AndroidManifest.xml` has no `android:extractNativeLibs`. AGP writes it into the
  built manifest from `useLegacyPackaging`: `false` in A, `true` in B (checked with
  `aapt2 dump xmltree`).
- `minSdk` is 24 (from the Flutter Gradle plugin). Modern packaging (uncompressed,
  mapped from the APK) is honoured on API 23 and above, so every supported device
  can use either mode.
- `lib/x86/**` stays excluded. `applicationId`, `versionCode` (2001 in both builds) and
  signing selection are untouched.

Switch semantics:

- Enable with the project property `-PARCPDF_COMPRESS_NATIVE_LIBS=true` or the
  environment variable `ARCPDF_COMPRESS_NATIVE_LIBS=true` (same lookup order as
  `ARCPDF_ABIS`). Anything else, or unset, means modern packaging.
- `flutter build apk` has no direct Gradle `-P` pass-through by default, but Flutter 3.47.9
  lists `-P/--android-project-arg key=value`. Only the environment variable was
  exercised in this phase.
- The switch is ignored when any requested Gradle task name contains `bundle`
  (Flutter runs `bundleRelease`). `useLegacyPackaging` also changes
  `BundleConfig.pb`, so without this guard the AAB would stop using modern packaging.
  Measured: with the guard, AABs built with the switch off and on are byte-identical
  (30,945,894 bytes, `cmp` equal). With the guard temporarily removed, `BundleConfig.pb`
  differed (and the AAB was 30,945,881 bytes), so the guard is needed. Play delivery is unaffected.

## Build commands

Same commit (`dc10c8b`), same toolchain, same flags, both debug-signed
(`ARCPDF_KEYSTORE_PATH` unset, certificate SHA-256 `647b4620...7607` for both).
Environment: `source .tools/env.sh`, Flutter 3.47.9, JDK 17, NDK 28.2.13676358,
build-tools 36.0.0, Rust 1.92.0, offline.

```bash
export ARCPDF_ABIS=arm64-v8a   # local toolchain only has the arm64 Rust target
# A: modern packaging
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --build-name=2.0.0 --build-number=1 --obfuscate --split-debug-info=build/symbols/A
# B: compressed packaging
ARCPDF_COMPRESS_NATIVE_LIBS=true flutter build apk --release --split-per-abi \
  --target-platform android-arm64 --build-name=2.0.0 --build-number=1 \
  --obfuscate --split-debug-info=build/symbols/B
python3 tool/apk_packaging_report.py A.apk B.apk --out report.md
```

Other ABIs and universal APKs use the same switch with `--target-platform
android-arm,android-arm64,android-x64`. They were **not built** locally (only the
arm64 Rust target is installed); `packaging_compare.yml` with `all_abis=true` covers them.

## Results (measured)

Phase 1's earlier local APK (36,093,306 bytes) is not the A baseline. It was built
without `--obfuscate --split-debug-info`, and its `libapp.so` is 13,042,568 bytes versus
11,010,952 here. A and B differ only in the packaging switch.

| | A modern | B compressed | Delta |
| --- | ---: | ---: | ---: |
| Total APK bytes | 34,061,686 | 17,234,914 | -16,826,772 (-49.40%) |
| Native libs, stored | 30,384,800 | 13,589,131 | -16,795,669 |
| Native libs, uncompressed | 30,384,800 | 30,384,800 | 0 |
| Assets, stored | 1,643,961 | 1,643,961 | 0 |
| `classes.dex`, stored | 1,174,941 | 1,174,941 | 0 |
| Resources, stored | 684,038 | 684,038 | 0 |
| Packaging overhead (headers, directory, signing block, padding) | 98,042 | 66,941 | -31,101 |

Per library (ARM64):

| Library | Uncompressed | A stored (method) | B stored (method) | B ratio | ELF `p_align` |
| --- | ---: | ---: | ---: | ---: | --- |
| `libapp.so` | 11,010,952 | 11,010,952 (stored) | 4,328,731 (deflate) | 0.393 | 0x10000 |
| `libflutter.so` | 11,763,360 | 11,763,360 (stored) | 5,485,456 (deflate) | 0.466 | 0x10000 |
| `libpdfium.so` | 6,598,376 | 6,598,376 (stored) | 3,309,476 (deflate) | 0.502 | 0x4000 |
| `libarcpdf_indexer.so` | 882,440 | 882,440 (stored) | 439,951 (deflate) | 0.499 | 0x4000 |
| `libdartjni.so` | 124,592 | 124,592 (stored) | 23,708 (deflate) | 0.190 | 0x4000 |
| `libpdfrx_pdfium_gate.so` | 5,080 | 5,080 (stored) | 1,809 (deflate) | 0.356 | 0x4000 |

Libraries are packaged identically in each build (all six stored in A, all six
deflated in B). All PT_LOAD segments have `p_align` of 16 KB or more.
These are local numbers; the sizes should be re-measured from the
CI workflow before any claim about released assets.

## Validation

| Check | A | B |
| --- | --- | --- |
| `apksigner verify` | passes (v2 scheme, 1 signer) | passes (v2 scheme, 1 signer) |
| `zipalign -c -P 16 -v 4` | passes, 0 BAD entries; every `.so` data offset is a multiple of 16384 | passes, 0 BAD entries; zipalign skips compressed entries, offsets are arbitrary |
| ELF `p_align` (`llvm-readelf -lW`) | 0x4000 or 0x10000 | identical (same binaries) |
| Manifest `extractNativeLibs` | false | true |
| `versionCode` / package | 2001 / `com.arcpdf.app` | 2001 / `com.arcpdf.app` |
| Signing certificate | same debug cert | same debug cert |
| `:app:testDebugUnitTest -PARCPDF_ABIS=arm64-v8a` | BUILD SUCCESSFUL (run after the Gradle change) | n/a |

Alignment reasoning: in A, the system maps libraries directly from the APK, so
zipalign must place them on 16 KB boundaries (it does). In B, the installer
extracts the libraries to disk, so the ZIP offset is irrelevant and the loaded
segments only need ELF `p_align` of 16 KB, which they have. Compression does not
fix alignment; the ELF headers do, and these builds already meet it. Phase 1's
APK shows the same values.

## Not run (no device or emulator)

Installation, upgrade over an existing release with the production key, native
library extraction on a device, 16 KB page-size device or emulator boot, cold and
warm startup, first PDF page render, PDFium and Rust FFI initialization, native PDF
tools, downloadable and offline OCR, installed storage, peak memory, install time,
PDF throughput. No performance claim is made.

The CI workflow was not run either (no GitHub Actions access here); YAML was
reviewed only.

## Trade-offs

- Download size drops 49.4% in this build (A 34.06 MB to B 17.23 MB).
- Installed storage grows: the installer extracts 30,384,800 bytes of libraries in B,
  while A reads them from the APK in place. Expect the installed footprint to be
  larger by about that amount plus the APK. Not measured.
- Install takes longer in B (extraction); first startup may differ. Not measured.
- Only the universal/split APKs published on GitHub are affected. Play (AAB) stays
  modern.

## Risks

- 16 KB page-size devices: B relies on ELF `p_align`. It is satisfied now, but a
  future dependency with 4 KB alignment would be hidden by compression, so the CI
  report (`p_align` column) should be watched.
- Modern packaging has been the default since AGP 3.6 / minSdk 23, and the
  installer extraction path is the legacy, widely used one; still, it has not been
  exercised on a device in this phase.
- Signature: APK signature v2+ is computed after packaging, so no repacking is
  involved. The experimental APKs must be built by Gradle, never by re-zipping.
- Upgrade: switching a user between A and B with the same key is a normal update.
  Not tested on a device.
- The auto-update path in the app downloads the GitHub APK, so extracted-library
  behaviour should be checked there too.

## How to opt in for GitHub APKs

Set `ARCPDF_COMPRESS_NATIVE_LIBS=true` for the APK `flutter build apk` steps only.
Do not set it for `flutter build appbundle` (it would be ignored by the guard
anyway). Not done in `auto_release.yml` while acceptance is pending.

## Recommendation

Keep compression experimental and off by default. The size result is large and the
alignment checks pass, but installation, upgrade, startup, storage and 16 KB-device
behaviour are untested, so production acceptance stays pending. Next step: run
`packaging_compare.yml`, then install A and B on an arm64 device and a 16 KB
emulator image, record the not-run items above, and only then decide.

## Phase 2.1: packaging validation hardening

Native compression stays experimental and disabled by default. Nothing in
`android/app/build.gradle.kts` changed; `ARCPDF_COMPRESS_NATIVE_LIBS` still defaults
to off and is still ignored for bundle tasks. This phase only hardens the checks.

### What changed

- `tool/apk_packaging_validate.py` (new) and the `validate` subcommand of
  `tool/apk_packaging_report.py`. The existing Markdown report is unchanged. The
  strict mode writes a JSON verdict (`ok`, `failures`, every check with id and
  detail, per-library SHA-256, package, versionCode, certificate) and exits 1 on any
  failure.
- `.github/workflows/packaging_compare.yml` runs the strict validation, fails the job
  on any failed check, and uploads `out/validation.json` and `out/report.md`.
- `tool/tests/test_apk_packaging_report.py`: 47 tests on synthetic APKs and AABs.

### CI fix: ARCPDF_ABIS matches the Flutter target platforms

`build.gradle.kts` builds Rust and PDFium for every ABI unless `ARCPDF_ABIS` is set,
so a run with `all_abis` not true (`--target-platform android-arm64`) failed in
`:app:buildRustIndexer` because the armeabi-v7a `libpdfium.so` was never generated.
The workflow now exports `ARCPDF_ABIS` for every `flutter build apk` and
`flutter build appbundle` step: `arm64-v8a` by default and
`armeabi-v7a,arm64-v8a,x86_64` when `all_abis` is true. The AAB step always targets
`android-arm64`, so it uses `ARCPDF_ABIS=arm64-v8a`. `build.gradle.kts` and the
default-off compression are unchanged.

### Checks

| Requirement | Check |
| --- | --- |
| Required tools | `apksigner`, `zipalign`, `aapt2` (build-tools) and `llvm-readelf` (NDK) must exist. A missing tool fails `tools:available`. The workflow also checks them in an earlier step. |
| ELF alignment | PT_LOAD headers are parsed in Python (ELF32 and ELF64, either endianness) and cross-checked with `llvm-readelf -lW`. arm64-v8a and x86_64 need `p_align` as a multiple of 0x4000. armeabi-v7a needs a multiple of 0x1000 (32-bit ARM does not run on 16 KB page kernels). All need `p_vaddr` congruent to `p_offset` modulo `p_align` and an `e_machine` matching the ABI folder. |
| 16 KB ZIP alignment | `zipalign -c -P 16 -v 4` must pass for A and B (it skips compressed libraries). Stored libraries must also have a data offset divisible by 16384. The previous warning-only handling for B is removed. |
| Modern vs compressed | A must have every `lib/*/*.so` stored. B must have every one deflated (`--expect-a`, `--expect-b` override). |
| Content equality | SHA-256 of each uncompressed library is compared between A and B per APK. Names must match too. Signed archives are never compared byte for byte. |
| ABI coverage | Exact ABI set per APK: `app-arm64-v8a`, `app-armeabi-v7a`, `app-x86_64` each have only their ABI, `app-universal` has all three. Exactly the six expected libraries per ABI (`libapp`, `libflutter`, `libpdfium`, `libarcpdf_indexer`, `libdartjni`, `libpdfrx_pdfium_gate`). Any other ABI such as `lib/x86` or any extra library fails. |
| Identity | `aapt2 dump badging` package and versionCode must match between A and B for the same APK (split APKs have different versionCodes per ABI, so they are not compared across ABIs). `apksigner verify --print-certs` must pass with a v2 or newer scheme, show exactly one signer, and A and B must share the certificate SHA-256, as must all APKs. |
| OCR absent | No `libmlkit_google_ocr_pipeline.so` and nothing under `assets/mlkit-google-ocr-models` in any APK or AAB. |
| AAB equivalence | Switch off and on AABs are compared by entry names and (size, CRC), ignoring `META-INF/` (signatures, jar manifest). `BundleConfig.pb` is decoded for `optimizations.uncompress_native_libraries.enabled` and `.alignment` (protobuf field path 2.2.1 and 2.2.2, checked on a real bundletool 1.18.1 AAB: enabled 1, alignment 2 = 16 KB) and compared, then compared byte for byte. |
| Stale outputs | The directories must contain exactly the expected file names (extras and missing files fail). `--not-before` fails files with an older mtime. The workflow deletes `build/app/outputs` and `out`, records the start time, and copies with `cp -p` after each build. |

### Running locally

```
python3 tool/apk_packaging_report.py validate --a-dir out/A --b-dir out/B \
  [--all-abis] [--not-before EPOCH] [--aab-off X.aab --aab-on Y.aab] \
  --json out/validation.json --md out/report.md
python3 -m pytest tool/tests -q        # or: python3 -m unittest discover tool/tests
```

### Verification done

- 47 unit tests pass. They use synthetic APKs and AABs with hand-built tiny ELF32 and
  ELF64 files and a fake tool runner, so ARMv7, x86_64 and universal layouts are
  covered without real builds. Each check has a passing and a failing case.
- The strict validator ran against the real Phase 2 arm64 APKs (A stored, B deflated),
  with the real `apksigner`, `zipalign`, `aapt2` and `llvm-readelf`: 107 checks, all
  passed. The real switch off and on AABs also passed the AAB checks.
- Workflow YAML parsed with PyYAML and linted with actionlint 1.7.7 (shellcheck
  integration disabled because shellcheck is not installed locally).

### Not verified

- The workflow was not executed. GitHub Actions cannot be run from this environment
  and the push is done separately. Its first run on the PR is the real test; expect
  the possibility of failures that only appear on CI (for example if two builds of
  `libapp.so` are not bit identical, which `sha256-equal` would report).
- Real ARMv7, x86_64 and universal APKs were not built (only the aarch64 Rust target
  is installed locally), so those layouts are tested synthetically only.
- No device validation. Compression remains experimental and off by default until
  the physical-device checks listed above are done.
