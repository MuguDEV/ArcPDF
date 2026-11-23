# Contributing to ArcPDF

Thank you for improving ArcPDF. Contributions should preserve its local-first
behavior, document safety, Android-native interaction model, and restrained
monochrome design.

## Before starting

- Search existing issues and pull requests.
- For a large feature, security migration, storage change, or new dependency,
  open a proposal before implementation.
- Never use real private PDFs in committed tests or screenshots.
- Read `AGENTS.md` and the Android UI skill when working on Flutter/Android UI.

## Development setup

Follow the requirements and setup steps in [README.md](README.md#build-from-source).
Keep Flutter, Dart, Gradle, Kotlin, Android NDK, and Rust lockfiles reproducible.
Do not upgrade the toolchain as part of an unrelated feature.

## Branches and commits

- Branch from `Main`.
- Prefer focused branches such as `fix/reflow-chart-refresh` or
  `feat/duplicate-cleanup`.
- Use concise imperative commits, for example:
  - `fix: refresh reflow charts after page navigation`
  - `feat: add PNG controls to PDF image export`
  - `test: cover duplicate cleanup race`
- Keep formatting-only changes separate when they affect unrelated files.

## Implementation principles

### Document safety

- Never overwrite an input implicitly.
- Write to a staging file and publish atomically after success where possible.
- Verify paths again before destructive actions.
- Preserve originals when an operation may be lossy.
- Return structured, actionable errors instead of swallowing exceptions.

### Performance

- Keep PDF decoding, hashing, OCR, and transformation work off the Flutter UI
  isolate.
- Bound worker counts and memory use.
- Dispose PDF documents, rendered images, streams, isolates, controllers, and
  native resources on success, error, cancellation, and widget disposal.
- Add measurements before claiming an improvement.

### UI and accessibility

- Reuse `ArcTheme`, `ArcTypography`, `ArcIcons`, and shared components.
- Follow Material 3 behavior and Android back/gesture conventions.
- Keep controls usable at 200–300% text scaling and on 320 dp-wide displays.
- Provide semantics and tooltips for icon-only actions.
- Respect high contrast, reduced motion, and low-power settings.
- Avoid animations that delay reading or rebuild expensive PDF surfaces.

### Privacy and security

- Do not add analytics, document upload, or remote processing without an explicit
  product decision and clear user consent.
- Redact paths, filenames, selected text, and document contents from diagnostics.
- Never commit tokens, passwords, keystores, private keys, or user documents.
- Security-format changes require versioning, migration, failure recovery, and
  compatibility tests.

## Tests

Run the checks relevant to your change:

```bash
flutter analyze
flutter test
cargo test --manifest-path native/arcpdf_indexer/Cargo.toml
git diff --check
```

Expected coverage includes success, cancellation, failures, async disposal races,
corrupted/encrypted/unsupported files, permission and storage errors, accessible
layouts, and native cache invalidation.

Do not weaken a meaningful test simply to make a pull request green. Report
pre-existing failures separately.

## Pull requests

Include:

- the user problem and implemented behavior;
- screenshots or recordings for UI changes;
- test commands and results;
- measurements for optimization work;
- permission, storage, security, migration, and compatibility impact;
- known limitations and follow-up work.

Keep generated output, `.dart_tool`, Gradle caches, Rust `target`, APKs, local
configuration, and private signing material out of the pull request.

## Documentation

Update the root README for user-visible capabilities or build changes. Update
`docs/README.md` when adding or superseding a technical document. Dated audits
and benchmarks should remain clearly labeled as snapshots rather than silently
being presented as current guarantees.
