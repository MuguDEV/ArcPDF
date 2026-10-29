1. **Audit & Baseline (Phase 0 & 1)**
   - Add reports to `docs/perf/baseline.md`, `docs/perf/audit.md`, and `docs/perf/decisions.md`. (Done)
   - Downgrade `pdfrx` to make `pub get` work, and fix analyzer errors. (Done)

2. **Phase 3: Job System**
   - Create a reusable job system for PDF operations in `lib/src/features/tools/job_queue.dart` to support concurrency limits, progress reporting, and cancellation.
   - Refactor `ToolsService` to use this job system.
   - For `syncfusion_flutter_pdf`, file I/O unfortunately requires reading the whole file into memory as `List<int>`. Note this limitation.

3. **Phase 5: Riverpod Optimization**
   - Review `PdfLibraryController` and `OpenTabsProvider` to use `select` or finer-grained providers if they cause full-screen rebuilds.

4. **Pre-commit Checks**
   - Ensure proper testing, verification, review, and reflection are done by calling `pre_commit_instructions`.

5. **Submit**
   - Submit the changes.
