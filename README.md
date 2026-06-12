# ArcPDF

![ArcPDF](assets/icon.png)

ArcPDF is a modern, local-first PDF manager and viewer built from the ground up using Flutter. It is designed to offer a buttery smooth, premium experience tailored towards productivity, security, and aesthetics.

## Key Features

- **Local-First & Privacy Focused:** All your files, metadata, and history stay strictly on your device. We do not use cloud sync or user tracking.
- **Modern UI & Liquid Glass Effect:** Designed using the Material 3 standard with a strictly monochrome, flat aesthetic, large pill-shaped radii, and edge-to-edge system UI elements. Optional 'Blur/Glass' effect for toolbars.
- **Unrivaled Performance:** Powered by the `pdfrx` rendering engine for lightning-fast scrolling. Supports Android 120Hz high refresh rate modes for a truly native feel.
- **PDF Toolkit:** Includes an entire suite of utilities:
  - **Compress PDF:** Save space by tweaking quality and shrinking PDF sizes.
  - **Merge PDFs:** Stitch multiple PDFs together with simple reordering.
  - **Split PDF:** Extract specific pages (e.g., "1, 3-5").
  - **Rearrange Pages:** Rotate and shuffle pages effortlessly using a visual drag-and-drop board.
  - **Metadata Editor:** Directly modify Title, Author, Subject, and Keywords.
  - **Images to PDF:** Combine multiple JPEGs, PNGs, etc., into a crisp document.
  - **PDF to Images:** Batch export all pages of your PDF into high-quality images.
- **Secure Vault:** AES-encrypted storage using the native Android Keystore and Bio-metrics. Vaulted documents are physically encrypted and safely locked behind your fingerprint or PIN.

## Architecture & Codebase

ArcPDF employs a modular architecture using **Riverpod** for state management and **Hive** for fast local storage.
- `lib/src/features/` contains modular components such as `pdf` (library scanning & viewers), `tools` (PDF manipulation), `vault` (security), and `settings`.
- `lib/src/shared/` hosts the reusable monochrome and glass UI widgets.
- Strict caching policies, including an optimized LRU thumbnail cache, to prevent Out Of Memory errors when viewing massive libraries.

## Building from Source

To build ArcPDF locally, make sure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.

1. Clone the repository:
   ```bash
   git clone https://github.com/MuguDEV/ArcPDF.git
   cd ArcPDF
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Generate Hive local database adapters:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## CHANGELOG

### v1.0.18
* **Performance:** Fixed `PdfThumbnailCache` to use a native Dart Map collection literal for speed improvements.
* **Architecture:** Massive codebase cleanup. Removed unused files, resolved over 4,000 flutter analyzer warnings and errors.
* **UI/UX:** Updated styling to adhere to standard Flutter Material specifications; refined the `Eco Mode` (Low Power Mode) active tracks to correctly follow theme styles.
* **Bug Fixes:**
  * Cleaned up memory leaks in metadata operations.
  * Resolved async gap context issues in `ToolsScreen`.
  * Removed deprecated `withOpacity()` usage globally to prevent alpha channel precision loss.

## Documentation

For a full showcase, visit our [Documentation Site](https://mugudev.github.io/ArcPDF/).
