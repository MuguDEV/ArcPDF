# ArcPDF

<p align="center">
  <img src="assets/icon.png" width="128" alt="ArcPDF application icon">
</p>

<p align="center">
  A local-first PDF library, reader, reflow engine, and document toolkit for Android.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-242424"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.41%2B-242424">
  <img alt="Android 7.0+" src="https://img.shields.io/badge/Android-7.0%2B-242424">
  <img alt="Current version" src="https://img.shields.io/badge/version-1.5.3-242424">
</p>

ArcPDF keeps document discovery, reading history, annotations, processing, and
security data on the device. It combines a Flutter/Material 3 interface, PDFium
rendering, and a Rust native runtime for concurrent scanning, BLAKE3 duplicate
detection, structural PDF operations, and document reflow analysis.

> [!IMPORTANT]
> ArcPDF is under active development. Back up important documents before using
> editing tools. The current Android release configuration is ARM64-only and is
> signed with a development key until production signing is configured.

## Contents

- [What is new](#what-is-new)
- [Features](#features)
- [Architecture](#architecture)
- [Privacy, permissions, and security](#privacy-permissions-and-security)
- [Build from source](#build-from-source)
- [Testing and performance](#testing-and-performance)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [Known limitations](#known-limitations)

## What is new

The current `Main` branch includes the work completed after the older 1.4.x
documentation and website screenshots:

- Rust job runtime with structured progress, cooperative cancellation, bounded
  workers, typed errors, and atomic output publication.
- Concurrent PDF discovery with persistent scan metadata, BLAKE3 hashes, and
  duplicate groups with reclaimable-space calculations.
- Duplicate cleanup that lets the user keep one copy and remove selected
  duplicates safely.
- Native PDFium merge, split, and organize paths that avoid loading every input
  PDF into Dart memory.
- A structured reflow engine with glyph geometry, reading-order reconstruction,
  headings, paragraphs, lists, tables, figures, charts, equations, footnotes,
  repeated-header removal, source anchors, and versioned caching.
- Selective offline OCR using bundled ML Kit Latin text recognition for scanned
  pages identified by the layout pass.
- Reader layouts for continuous, single-page, and two-page viewing, plus vertical
  or horizontal navigation, fit-width, fit-page, rotation, fullscreen, and
  auto-scroll.
- Text selection, copy/share, search highlights, annotations, notes, freehand
  drawing, read aloud, named bookmarks, thumbnails, outline navigation, and
  automatic reading-position restore.
- Gesture arbitration so selection and pinch zoom take priority over document-tab
  navigation; tab switching is restricted to safe edge gestures.
- Correctly refreshed chart/figure crops in reflow mode and page navigation that
  resets to the start of the selected reflow page.
- Real operation progress UI, cancellation, background-service integration,
  previews, actual before/after sizes, and actionable failure messages.
- Configurable PDF-to-image DPI/format/quality and image-to-PDF page sizing,
  orientation, margins, image fit, and EXIF-aware processing.
- A unified monochrome Material 3 system, Lucide icon vocabulary, adaptive type,
  accessible touch targets, reduced-motion behavior, and a compact navigation
  dock.
- A new ArcPDF monogram used by the launcher and in-app identity surfaces.

## Features

### Local PDF library

- Scans accessible device storage and incrementally publishes discovered PDFs.
- Uses cached file metadata and native concurrent traversal to reduce repeat work.
- Searches filenames with typo-tolerant matching.
- Filters by recent files, downloads, large files, folders, duplicate groups, and
  document categories such as books, receipts, resumes, statements, and tickets.
- Shows favorites, recent history, reading progress, file size, location, modified
  time, encryption state, and generated thumbnails.
- Supports rename, delete, share, open-with, metadata actions, tags, multi-select,
  and incoming Android `VIEW`, `SEND`, and `SEND_MULTIPLE` PDF intents.
- Coalesces thumbnail work, bounds native concurrency, caches rendered previews,
  and disposes evicted native images.

### Duplicate detection and cleanup

- BLAKE3 content hashes distinguish true duplicate files from matching names.
- Hashes are reused while size and modification metadata remain unchanged.
- Duplicate groups report copy count, file locations, and reclaimable bytes.
- Cleanup requires an explicit copy to keep and verifies files again before
  deletion so a changed file is not removed using stale scan data.

### Reader

- Continuous, single-page, and two-page layouts.
- Vertical scrolling and horizontal page-swipe modes.
- Pinch zoom, double-tap smart zoom, fit-width, fit-page, and page rotation.
- Page-number entry, previous/next controls, thumbnails, and document outline.
- Full-text search with highlighted matches and previous/next result navigation.
- Text selection with visible high-contrast handles, copy, share, highlight,
  underline, strikethrough, note, and selection-aware gesture handling.
- Freehand ink with undo/redo history and configurable annotation colors.
- Named bookmarks and a bookmark list.
- Read aloud through Android text-to-speech with completion-state handling.
- Fullscreen, page-color inversion, keep-awake, auto-scroll, and distraction-free
  controls.
- Automatic resume using page, zoom, and normalized viewport coordinates.
- Multiple open documents with a Chrome-like reader tab strip and edge-only tab
  gestures when selection, drawing, and zoom are inactive.
- Share a document, export the current page as an image, print, or open document
  information from the reader.

### Structured reflow

Reflow is not a plain text dump. ArcPDF builds a page-aware block model:

- Extracts glyph text, bounds, font size, baseline, and source coordinates.
- Reconstructs line and column reading order.
- Joins wrapped lines while preserving headings, paragraphs, lists, equations,
  footnotes, and page boundaries.
- Detects aligned table cells and preserves rows and columns.
- Finds image regions and captions.
- Detects vector chart regions while rejecting page borders and decorative paths.
- Removes repeated running headers, footers, and page numbers.
- Runs OCR only on pages that need it and merges recognized elements back into
  page coordinates.
- Keeps a source page and rectangle for every block so readers can return to the
  original page.
- Caches output by file hash, engine version, and analysis settings.

Reflow accuracy depends on the PDF. Complex handwriting, uncommon scripts,
nested tables, multi-layer diagrams, and unusual reading orders may fall back to
a rendered source region.

### PDF tools

All tools work locally and publish output only after the operation succeeds.

| Tool | Current behavior |
| --- | --- |
| Merge PDFs | Reorder inputs and combine them through the native PDF backend. |
| Split PDF | Create separate outputs for comma groups, individual pages, or ranges. |
| Organize pages | Reorder, rotate, duplicate, or remove selected pages. |
| Compress PDF | Choose a quality profile, preview estimated/actual sizes, and process pages with bounded workers. |
| Edit metadata | Update title, author, subject, and keywords using staged replacement. |
| Images to PDF | Choose page size, orientation, margins, fit, and image quality; normalize image orientation. |
| PDF to images | Export JPEG or PNG with configurable DPI and JPEG quality. |

The operation layer distinguishes permission denial, full storage, encrypted or
corrupted PDFs, unsupported input, missing files, invalid page selections,
existing outputs, and timeouts. The progress dialog shows stages and completion
instead of presenting every failure as a generic error.

### Security and data

- Optional app lock with biometrics, PIN, or pattern.
- Encrypted vault for documents separated from the normal library.
- Local backup and restore for ArcPDF application data.
- Sanitized rotating diagnostics with an in-app viewer and export flow.
- No ArcPDF account and no document-upload service.
- Update checks and optional Google Fonts access use the network; PDF processing
  itself is local.

### Interface and accessibility

- Material 3 behavior with ArcPDF's restrained monochrome design language.
- Shared `ArcTheme`, `ArcTypography`, and `ArcIcons` systems.
- Five stable destinations: Home, Favorites, Recent, Tools, and Settings.
- Adaptive layouts for narrow phones, large text, landscape, tablets, RTL, light
  and dark themes, high contrast, reduced motion, and low-power mode.
- Keyboard focus, semantic labels, tooltips, minimum touch targets, and scrollable
  dialogs/sheets where content can grow.
- Performance presets control reader cache, preload extent, thumbnails, effects,
  worker counts, and optional high-refresh-rate behavior.

## Architecture

```text
Flutter UI / Riverpod state / Hive metadata
                    │
          commands, progress, results
                    ▼
             Dart–Rust FFI bridge
                    │
              Rust job runtime
       ┌────────────┼──────────────┐
       │            │              │
 concurrent scan  PDFium tools   reflow analysis
 + BLAKE3         merge/split/   + versioned cache
 duplicates       organize       + selective OCR
```

Important modules:

| Path | Responsibility |
| --- | --- |
| `lib/src/features/pdf/` | Library, scanner integration, reader, tabs, annotations, reflow, favorites, and history. |
| `lib/src/features/tools/` | Tool screens, validation, job queue, progress, typed failures, and Dart processing fallbacks. |
| `lib/src/core/native/` | Dart API for the shared native job runtime. |
| `lib/src/core/platform/` | Android storage and foreground-job channels. |
| `lib/src/features/security/` | App lock and authentication UI. |
| `lib/src/features/vault/` | Encrypted document vault lifecycle. |
| `lib/src/features/settings/` | Appearance, accessibility, performance, backup, diagnostics, and update settings. |
| `lib/src/shared/` | ArcPDF design tokens, icon registry, and shared widgets. |
| `native/arcpdf_indexer/` | Rust scanner, BLAKE3 cache, scheduler, PDFium operations, and reflow engine. |
| `android/app/src/main/kotlin/` | Android activity, OCR channel, file provider, and foreground job service. |
| `test/` | Unit, widget, lifecycle, regression, layout, scanner, reader, and tool tests. |
| `tool/` | Developer benchmarks and maintenance utilities. |

State is kept locally with Hive and platform storage. Riverpod coordinates
application state. `pdfrx` renders interactive pages, while the native engine
uses the packaged PDFium library for structural operations and extraction.

## Privacy, permissions, and security

ArcPDF requests permissions used by current Android features:

| Permission | Why it is requested |
| --- | --- |
| Storage access | Discover and manage PDFs in user-accessible storage. |
| All-files access on Android 11+ | Required by the current whole-device PDF scanner. This permission has Play policy implications. |
| Biometrics | Unlock app-lock and vault flows. |
| Notifications and foreground data service | Keep long document jobs visible when Android requires a foreground service. |
| Internet | Update checks and optional remote font retrieval. Documents are not uploaded by ArcPDF. |
| Vibration | Optional haptic feedback. |
| Install packages | Hand an explicitly downloaded update APK to Android's installer. |

Security-sensitive code should be reviewed independently before high-risk use.
The repository's older audit documents are snapshots, not a current security
certification. Known security work is listed under [Known limitations](#known-limitations).

## Build from source

### Requirements

- Flutter 3.41 or a compatible newer stable SDK.
- Dart supported by `pubspec.yaml` (`>=3.3.0 <4.0.0`).
- JDK 17 or newer supported by the selected Flutter/Gradle combination.
- Android SDK, platform tools, and the NDK version selected by Flutter.
- Rust stable with the `aarch64-linux-android` target.
- A Linux x86-64 build host for the current native Android task. The Gradle task
  currently resolves the Linux NDK toolchain directly.

### Clone and prepare

```bash
git clone https://github.com/MuguDEV/arcpdf.git
cd arcpdf
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
rustup target add aarch64-linux-android
```

### Run during development

```bash
flutter run
```

### Build the current ARM64 release

```bash
flutter build apk --release --target-platform android-arm64
```

The Android Gradle task builds `native/arcpdf_indexer`, copies its shared
library, and packages the matching PDFium library. `ANDROID_HOME` or
`ANDROID_SDK_ROOT` must be defined. Set `CARGO` to a non-default Cargo
executable or `ARCPDF_RUST_TARGET_DIR` to move Rust build output when needed.

> [!WARNING]
> `android/app/build.gradle.kts` currently uses the debug signing configuration
> for release builds. Configure a private upload keystore outside the repository
> before distributing through Google Play. Never commit keystores, passwords,
> `key.properties`, access tokens, or `local.properties`.

## Testing and performance

Run the standard checks before opening a pull request:

```bash
flutter analyze
flutter test
cargo test --manifest-path native/arcpdf_indexer/Cargo.toml
git diff --check
```

Run the native scanner benchmark with:

```bash
dart run tool/benchmark_native_scanner.dart <pdf-directory>
```

Performance work includes lazy lists, coalesced thumbnail work, bounded image
decoding, native concurrent traversal, cached BLAKE3 hashes, memory-aware worker
settings, reader cache presets, reduced-motion paths, and native image disposal.
These are engineering measures—not a guarantee of a fixed frame rate on every
device.

Validate significant changes on a low-memory device, Android API 24 and a current
Android version, 320 dp and tablet layouts, 200–300% text scaling, accessibility
settings, large/scanned/encrypted/malformed PDFs, and low-storage conditions.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
starting substantial work.

Short workflow:

1. Open or choose an issue and describe the user problem.
2. Create a focused branch from `Main`.
3. Preserve local-first behavior and avoid unrelated refactors.
4. Add tests for behavior, lifecycle, accessibility, and failure paths.
5. Run Flutter analysis/tests and Rust tests when native code changes.
6. Document user-visible behavior and migration, permission, or security impact.
7. Open a pull request with screenshots for UI work and measured evidence for
   performance claims.

Do not commit generated output, personal configuration, private PDFs,
credentials, signing material, or diagnostics containing user data.

## Documentation

- [Documentation index](docs/README.md) — current documents and historical status.
- [Contributor guide](CONTRIBUTING.md) — style, testing, commits, and pull requests.
- [UI refinement notes](docs/UI_REFINEMENT.md) — dated implementation record.
- [Code audit](docs/CODE_AUDIT.md) — dated audit snapshot; some findings changed.
- [Performance documentation](docs/perf/) — baseline, decisions, and results.
- [GitHub Pages source](docs/index.html) and the
  [published site](https://mugudev.github.io/ArcPDF/).

When documentation conflicts with source code, `pubspec.yaml`, current tests,
and the implementation on `Main` are authoritative. Historical documents are
kept because they explain earlier decisions and should not be silently rewritten
as if they were current validation.

## Known limitations

- Android is the supported product platform.
- Current APK packaging is ARM64-only and requires Android 7.0/API 24 or newer.
- Whole-device discovery uses `MANAGE_EXTERNAL_STORAGE`, which requires careful
  user explanation and Google Play policy review.
- Reflow and OCR are heuristic. Complex layouts and non-Latin scanned text may
  need source-page fallback.
- Compression is lossy and cannot guarantee a smaller output for every PDF.
- Structural editing may not preserve every interactive form, signature, outline,
  link, or unusual PDF object. Keep the original.
- Vault/authentication code has not received an independent security audit. The
  historical audit identified authenticated-encryption, credential KDF,
  throttling, and crash-recovery work that still needs migration design.
- Production release signing, Play distribution, and broad physical-device
  compatibility testing are not complete.

## License

ArcPDF is licensed under the [GNU Affero General Public License v3.0](LICENSE).
If you distribute a modified version or provide it as a network service, review
the license obligations for providing corresponding source code.
