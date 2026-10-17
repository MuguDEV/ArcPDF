# Phase 0: Audit Report
## Vault initialization race condition
- File: `lib/src/features/vault/vault_controller.dart`
- `_initVault()` is called synchronously in the constructor, meaning `_encrypter` and `_iv` might not be initialized when a method like `loadVaultFiles()` is called. Also handled initialization without throwing.

## BuildContext across async gaps
- Many occurrences. E.g. `lib/src/features/vault/vault_screen.dart`, `lib/src/features/pdf/home/home_screen.dart`, `lib/src/features/tools/tools_screen.dart`, `lib/src/features/tools/pages/merge_pdfs_page.dart`, `lib/src/features/tools/pages/split_pdf_page.dart`, `lib/src/features/pdf/recent/recent_screen.dart`.
- Need to insert `if (!context.mounted) return;` before `Navigator.of(context)` or `ScaffoldMessenger.of(context)` or similar usages after `await`.

## Late/null-assertion audit
- Need to check `vault_controller.dart` specifically for `late enc.Encrypter _encrypter;` and `late enc.IV _iv;`.

## Monochrome design tokens
- Will create `lib/src/shared/theme/arc_colors.dart` providing standard monochrome colors.
- Will update usages in `DynamicIslandNotification`, `GlassSliverAppBar`, `ArcNavBar`, etc. to use tokens instead of direct theme color scheme colors.

## Glass contrast
- In `lib/src/shared/widgets/glass_app_bar.dart`, remove hardcoded 0.7 alpha. Apply adaptive contrast logic and disable blur entirely in eco mode (falling back to opaque surface color).

## Eco mode theming
- Update `lib/src/shared/widgets/glass_app_bar.dart` and `lib/src/features/tools/widgets/in_app_pdf_selector.dart` and others to respect low power mode.

## Responsive layout
- Validate grid and lists in `lib/src/features/tools/tools_screen.dart` to not overflow on tablets. Use `SliverGrid.extent` or similar layout adaptiveness.

## Robustness: Shared PdfErrorHandler
- Create `lib/src/shared/utils/pdf_error_handler.dart`
- Use it to show standard dialogs on error in viewer and tools.

## Robustness: Android document provider hardening
- Improve `lib/src/features/pdf/data/pdf_scanner_service.dart` and `lib/src/features/tools/utils/tools_directory_util.dart` to handle null paths/unauthorized access gracefully without throwing.

## Tests
- Need to generate and run vault tests, UI tests, regression tests.

## Performance instrumentation
- Add `Timeline.startSync` / `Timeline.finishSync` in `pdf_thumbnail_cache.dart` and transition builders.

# Plan
1. *Fix Critical Correctness issues (Phase 1).*
   - Refactor `vault_controller.dart` to use a lazy initializer.
   - Fix all missing `if (!mounted) return;` across async gaps.
   - Fix unsafe `late` modifiers.
2. *Fix UI consistency (Phase 2).*
   - Create `ArcColors`.
   - Update `GlassSliverAppBar`.
   - Update Eco Mode theming.
   - Check responsive layout.
3. *Improve Robustness (Phase 3).*
   - Create and integrate `PdfErrorHandler`.
   - Harden Android directory paths in `pdf_scanner_service.dart` and `tools_directory_util.dart`.
4. *Write Tests (Phase 4).*
   - Create tests for Vault, UI tokens, and Regression.
5. *Add Performance instrumentation (Phase 5).*
   - Add Timeline tracing in hot paths.
6. *Complete pre commit steps.*
   - Follow `pre_commit_instructions` tool to run checks.
7. *Submit.*
