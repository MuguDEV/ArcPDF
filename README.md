# ArcPDF

ArcPDF is a modern, local-first PDF manager and viewer built with Flutter. It prioritizes privacy, performance, and a sleek user interface, offering a buttery smooth experience across all major platforms.

## Features

- **Local-First & Privacy Focused:** All your files and data stay on your device. No cloud sync, no tracking.
- **Cross-Platform:** Available on Android, iOS, macOS, Windows, and Linux.
- **Modern UI:** Built with standard Flutter ThemeData, featuring a strict monochrome palette (greys, blacks, and whites) and Material 3 expressive design with large, fully rounded pill-shaped elements.
- **Liquid Glass Effect:** Optional 'Blur/Glass' effect for toolbars and floating UI elements.
- **High Performance:** 120Hz display mode supported on Android for global UI smoothness.
- **Snappy Animations:** Uses spring-based animations (like Apple or OnePlus devices) with globally configurable speeds.

## Installation

### Android
Download the latest `.apk` from the [Releases](https://github.com/MuguDEV/ArcPDF/releases) page and install it on your device.

### iOS
Download the `.ipa` file from the [Releases](https://github.com/MuguDEV/ArcPDF/releases) page.
*Note:* The iOS application provided in releases is not codesigned by an Apple Developer account. You will need to use sideloading tools such as [AltStore](https://altstore.io/) or [Sideloadly](https://sideloadly.io/) to install it on your device.

### macOS
Download the `.zip` containing the `arcpdf.app` from the [Releases](https://github.com/MuguDEV/ArcPDF/releases) page. Unzip and drag the app to your Applications folder.

### Windows
Download the Windows `.zip` artifact from the [Releases](https://github.com/MuguDEV/ArcPDF/releases) page. Extract the folder and run `arcpdf.exe`.

### Linux
Download the Linux `.tar.gz` artifact from the [Releases](https://github.com/MuguDEV/ArcPDF/releases) page. Extract the archive and execute the `arcpdf` binary inside.

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

## Design Principles
ArcPDF uses a unique strictly monochrome theme. We avoid `fromSeed` generated color schemes and flex colors to keep true greyscales. We explicitly set `surfaceTint: Colors.transparent` across themes to avoid unwanted Material 3 color artifacts.