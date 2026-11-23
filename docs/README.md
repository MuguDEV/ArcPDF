# ArcPDF documentation index

This directory contains the GitHub Pages product site and technical records from
different development stages. Some files are intentionally historical snapshots.
They explain decisions made at that time but do not override current source code.

## Current entry points

- [Project README](../README.md) — current features, architecture, build,
  permissions, limitations, and project status.
- [Contributor guide](../CONTRIBUTING.md) — contributor workflow and quality
  requirements.
- [GitHub Pages source](index.html) — source for the public product site.
- [UI refinement record](UI_REFINEMENT.md) — dated UI implementation and
  validation notes.

## Performance records

The files in [`perf/`](perf/) are measurement and decision records. Read their
dates and test environments before comparing results:

- [Baseline](perf/baseline.md)
- [Architecture decisions](perf/decisions.md)
- [Riverpod and rebuild notes](perf/riverpod.md)
- [Performance audit](perf/audit.md)
- [Recorded results](perf/results.md)

These files do not guarantee a frame rate or processing time on every device.

## Historical audits

- [`CODE_AUDIT.md`](CODE_AUDIT.md) was reviewed on 2026-10-19. Several
  feature-gap statements were subsequently addressed, including reader
  annotations, structured tool errors, native scanning, operation progress, and
  richer conversion controls. Security and document-preservation findings still
  require evaluation against current code.
- `UI_REFINEMENT.md` includes dated test counts and build details. Newer commits
  may have different test counts, version numbers, or known failures.

## Documentation rules

1. Date audits, benchmarks, and validation reports.
2. Separate measured results from goals or design intentions.
3. Do not claim lossless editing, fixed frame rates, complete device support, or
   security guarantees without evidence.
4. Keep historical reports, but add a status note when newer implementation work
   supersedes part of them.
5. Treat `pubspec.yaml`, tests, and the implementation on `Main` as
   authoritative when an older document conflicts with the current project.
