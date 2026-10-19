# Code and usability audit

Reviewed: 2026-10-19. Scope: library/scanning, incoming files, reader, tools,
settings/updating, and vault lifecycle. This is a targeted source and regression
review, not a claim that the application is bug-free or a formal security audit.

## Corrected in this pass

### File safety and library state

- Prevent older scans from replacing newer results, clear loading on scan failure,
  cancel delayed work on disposal, and serialize metadata mutations.
- Preserve the selected tag across unrelated library changes.
- Rename without overwriting an occupied destination; migrate favorites, recents,
  timestamps, and tags and update live items immediately.
- Route deletion through the library controller, remove stale document tabs, and
  keep failed operations visible instead of dismissing their error dialog.
- Clean up missing-source metadata after a vault move without deleting a newly
  created replacement at the source path.
- Continue scanning accessible sibling directories after individual traversal
  failures; avoid Android-only root discovery on other platforms.
- Contain incoming-intent errors, deduplicate pending delivery, wait for startup,
  and navigate through the owning NavigatorState.

### Vault

- Never regenerate missing credentials over existing encrypted files.
- Serialize mutations; preserve same-name imports and existing restore targets.
- Require an unlocked session for file listing, decryption, and restoration;
  reject operations whose session was revoked during an await.
- Require fresh route authentication, lock when leaving, and show initialization
  failures instead of a misleading empty vault.
- Correct Windows-specific paths in the original tests. The four original vault
  test failures were path-portability failures, not proof of an initialization
  race; separate regression tests cover the verified production bugs above.

### PDF tools

- Stage outputs and refuse accidental destination overwrite. Metadata replacement
  remains explicit and staged.
- Validate split selections, retain requested order and page dimensions, reject
  missing inputs, and correct reorder callback index handling.
- Dispose documents/rendered images on failure and ignore stale rearrange loads.
- Remove only the operation's own loading route; report actual output counts and
  paths, and contain open/share failures.
- Share generated files rather than a directory or unrelated existing exports.
- Disclose compression's rasterization losses and bound parallel image encoding.

### Reader and other UI

- Replace the oversized two-row reader toolbar and long overflow menu with a
  compact header, direct page-entry dock, and grouped reading-control sheet.
- Preserve the document/page when changing page colors; validate page entry without
  dismissing invalid input; pause auto-scroll while controls cover the document.
- Keep search visible while editing, show result/no-result states, and label the
  single-page sharing action as an image export.
- Make the document-info panel scrollable and thumbnail columns responsive.
- Preserve the list viewport behind the translucent floating navigation bar.
- Add navbar keyboard activation, selected semantics, large-text layouts, and
  low-power/reduced-motion handling.
- Make PDF actions scroll with the keyboard open; wrap action labels and dialog
  buttons rather than overflow at narrow widths.
- Use Material surfaces for settings/security tiles so their ink is visible;
  replace fixed-width trailing sliders with full-width labeled controls.
- Validate stored setting types, enum indices, numeric ranges, and finite values.
- Guard lock-dialog async completion and duplicate submissions.

### Updating

- Compare versions using SemVer precedence rather than treating malformed tags as
  upgrades; distinguish failure/unavailable from a verified up-to-date result.
- Bound requests, check HTTP status, use the advertised release's assets, validate
  HTTPS downloads and basic APK header/size, and stage uniquely named files.
- Own and clean up loading dialogs; prevent stale callbacks from popping an
  unrelated route or starting an installation after the UI is no longer active.

## Remaining work, ordered by risk

| Priority | Finding / missing capability | Recommended next step |
| --- | --- | --- |
| High | Vault encryption uses CBC with a shared IV and no authentication tag. | Design a versioned authenticated-encryption format with fresh per-file nonces, legacy reads, crash-safe migration, and tamper tests. Do not overwrite legacy files or keys as an ad-hoc fix. |
| High | PIN/pattern hashes are unsalted SHA-256 with no attempt throttling. Authentication is an application-state gate, not cryptographic authorization of key use. | Add a versioned password KDF, migration on successful authentication, attempt throttling, and an explicit recovery policy; consider OS authentication-bound keys. |
| Medium | Plaintext vault previews can survive abnormal process termination. | Add startup/background cleanup and exercise process-kill recovery on Android. |
| Medium | Merge/split/rearrange rebuild page graphics; interactive forms, outlines, links, and signatures are not guaranteed to survive. | Define preservation requirements, display operation-specific warnings, and test representative interactive documents before promising lossless structural editing. |
| Medium | Filesystem mutations and multiple Hive writes are not crash-atomic. | Add a recovery journal/reconciliation strategy and fault-injection tests. |
| Medium | Rename migration does not centrally migrate reading progress, annotation keys, thumbnail caches, or open-tab paths. | Add a shared document-identity/move event and migrate all path-keyed state together. |
| Medium | APK header/size validation is not cryptographic verification, and downloads are buffered in memory. | Stream to staging and define signature/checksum verification and trust policy. |
| Feature gap | Annotation models/repository exist but are not connected to reader editing tools. | Define highlight/note creation, editing, deletion, persistence, and export UX before exposing an annotation mode. |
| Feature gap | Unresolved content URIs are rejected; native document-provider import is not implemented by the intent service. | Add a platform-supported persistent import/copy flow and tests for Android document providers. |
| Feature gap | Compression is lossy and does not guarantee a smaller result; richer service errors are still needed. | Add before/after size reporting, a no-savings outcome, and typed actionable failures. |
| Validation gap | Reduced motion is not centrally enforced for every explicit animation across the application. | Consolidate animation policy and test all screens, not just the corrected controls. |

## Validation results and boundaries

Final checks on 2026-10-19:

- `flutter test`: 241 passed, 1 skipped. The Windows symlink test requires
  Developer Mode or elevation.
- `flutter analyze`: no issues found.
- `git diff --check`: passed.
- `flutter build apk --debug --target-platform android-arm64`: succeeded.
  Output: `build/app/outputs/flutter-apk/app-debug.apk`. The APK has not been
  installed or tested on a phone.

The build reported upcoming support warnings for Android Gradle Plugin 8.11.1
(recommending at least 9.0.1) and Kotlin 2.2.20 (recommending at least 2.3.20),
plus an Android SDK command-line tools XML-version mismatch. Build-tool upgrades
remain separate work; existing Gradle-wrapper changes were preserved.

Automated checks cover native PDF opening/search on the Windows test host,
widget layouts/interactions, document-processing service behavior, async lifecycle
races, update workflows, and vault key/file safety. Rendered reader previews were
also inspected using real UI/icon fonts; they are test-host previews, not phone
screenshots. One symlink regression is skipped on Windows without Developer Mode
or elevation.

Hardware validation is still required for Android storage permissions/document
providers, biometrics and secure storage, APK installation, external open/share,
background/resume/process-kill behavior, large-document memory consumption,
TalkBack, and real-device frame timing. README performance claims such as
"120fps flawlessly" have not been established by this audit.
