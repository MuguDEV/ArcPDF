# ArcPDF

ArcPDF is a modern, local-first PDF manager and viewer built with Flutter. It prioritizes privacy, performance, and a sleek user interface, offering a buttery smooth experience.

## Features

- **Local-First & Privacy Focused:** All your files and data stay on your device. No cloud sync, no tracking.
- **Modern UI:** Built with standard Flutter ThemeData, featuring a strict monochrome palette (greys, blacks, and whites) and Material 3 expressive design with large, fully rounded pill-shaped elements.
- **Liquid Glass Effect:** Optional 'Blur/Glass' effect for toolbars and floating UI elements.
- **High Performance:** 120Hz display mode supported on Android for global UI smoothness.
- **Snappy Animations:** Uses spring-based animations with globally configurable speeds.

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
