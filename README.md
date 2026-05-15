# arcpdf

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

### App Size Optimization

For production builds, the app removes heavy WebAssembly modules shipped by `pdfrx` to reduce Android APK sizes. To do this, run the following commands before building:

```bash
flutter pub get
dart run pdfrx:remove_wasm_modules
flutter build apk --split-per-abi
```
