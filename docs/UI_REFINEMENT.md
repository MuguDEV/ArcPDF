# ArcPDF UI refinement

> **Dated implementation record:** This document includes validation and build
> details from the November 2026 UI pass. See [the documentation index](README.md)
> and [the current project overview](../README.md) for current status.

The existing monochrome identity, local storage, navigation destinations and PDF
features are preserved. This pass changes presentation and interaction layout,
and connects reader rendering budgets to the existing performance preferences.

- Search appears immediately below the library header. Compact filters scroll
  horizontally at normal text sizes and wrap at enlarged system text sizes.
- Resume reading is a compact, page-linked card. The document list has a visible
  count. Selection mode prioritizes its toolbar and documents.
- Typography defines every Material text role centrally. Setting labels and
  document titles use 16px semibold; body text uses 14–16px, secondary text 13px,
  and metadata 12px. System text scaling remains enabled.
- Lucide outline icons replace the mixed icon libraries throughout the library,
  reader, tools, security, settings and vault. `ArcIcons` is the shared semantic
  registry; icon fonts are bundled locally and toolbar actions keep tooltips.
  The unused HugeIcons dependency has been removed.
- Cards, fields, dialogs, lists and buttons use shared theme roles and spacing.
  Light mode uses white cards on a soft gray background; dark mode stays neutral.
- Tools use compact two-column tiles on regular phones, three on wide layouts,
  and a single column for enlarged text. Tiles have natural heights, touch
  feedback and keyboard activation. Metadata uses a full-width utility row.
  Settings, Tools, Favorites and Recent no longer delay content with staggered
  entrance animations.
- Large-text document cards stack their preview, details and actions vertically.
  Empty states and operation result dialogs scroll when space is constrained.
- Navigation respects high contrast and reduced motion. Progress uses a standard
  indicator with a static reduced-motion fallback.
- Navigation is an opaque, full-width dock that reserves its own space instead
  of covering the document list. The selected icon has a solid rounded-square
  indicator; all five labels remain visible and reflow at enlarged text sizes.
  Selection positioning follows both LTR and RTL layouts.
- Large page headings, tonal search fields, simplified file metadata and an
  inverse-surface resume card establish a stronger hierarchy. Settings uses
  tonal choices with an explicit selection outline instead of heavy pills.
- Entering selection compensates for removed library headers so the selected
  document stays visible. Reader bars become opaque in high contrast. Compression
  options scroll and their actions wrap on small screens. Result icons no longer
  bounce into view.
- Library loading placeholders match the document layout, shimmer once, and
  stay static in battery or reduced-motion modes. The tab switcher also respects
  battery mode; its footers measure the actual font and allow status text to wrap.
- Reader caching and preloading honor the Smooth, Balanced and Battery settings.
  Changing a preset updates the renderer without reopening the PDF. A saved page
  past the end of a shortened PDF resumes at its last valid page.

## Reusable Android UI skill

`.agents/skills/android-ui/SKILL.md` is a project-authored skill based on Material
3 layout conventions and Android accessibility guidance. `AGENTS.md` directs
future Android UI work to it. This is a repository skill, not a model/system
instruction change or an installed third-party plugin.

## Validation and previews

Use Flutter 3.41 or a compatible newer SDK, then run `flutter pub get`,
`flutter analyze lib` and `flutter test`.

The shell regression tests render all five primary screens with the real shared
theme in light and dark modes. To save previews from those tests:

```sh
flutter test --dart-define=ARC_UI_PREVIEW_DIR=build/ui-previews \
  test/features/navigation/app_shell_test.dart
```

Preview data is synthetic; the library intentionally uses missing-file
placeholders with sample names and metadata. These are Flutter test renders,
not Android device captures. The latest renders are in `build/redesign-previews`.
Large-text tests cover narrow screens, keyboard activation, filters, selection,
settings and tool cards. Android device checks remain necessary for actual
display density, system bars, accessibility services and gesture navigation.

This pass does not change the PDF processing engine or establish processing-speed
or frame-rate claims.

The previous full run passed 550 tests with one reader cache-budget failure.
The follow-up on 2026-11-17 connects the reader to the existing Settings budgets
and fixes clamping of saved pages for shortened documents. Regression coverage
checks live preset changes without reopening the document, custom tab fonts at
300% text size, and loading motion in battery and reduced-motion modes.

Validation on 2026-11-17 with Flutter 3.41.0: all 557 tests passed. Analysis of
application source and the changed reader/loading/tab tests reported no issues.
The original cache-budget assertion remains intact and now passes.

ARM64 Android release build on 2026-11-17: `flutter build apk --release
--target-platform android-arm64 --split-per-abi --no-pub` succeeded with
Flutter 3.41.0 and JDK 21. The app now applies the declared Kotlin Android plugin
so its Kotlin launch activity is compiled. APK v2 signature verification and
16 KB ZIP alignment checks passed; the archive contains only `arm64-v8a`
libraries and includes `MainActivity` in its DEX. Version 1.4.7 (2001), minimum
Android API 24. The existing release configuration signs with a debug/test key;
this build has not been installed or exercised on an Android device.
