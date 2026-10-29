# Optimization Results

## Phase 2: PDF Job Queue
Implemented a reliable, bounded concurrency model for long-running PDF jobs. The `JobQueue` properly orchestrates isolate workload scheduling and prevents unbounded active isolates on large operations.

## Phase 3: Image to PDF
We are now avoiding explicit PNG encoding where possible. If `syncfusion_flutter_pdf` can natively decode the bytes directly into a `PdfBitmap` (such as JPEG), it bypasses the manual `img.decodeImage` cycle, significantly reducing CPU cycles and memory.

## Phase 4: PDF Operations Pipeline
Implemented progress updates via callbacks during the document-page looping for merging, compressing, etc.

## Phase 8: PDF Viewer Memory
Reduced memory limits on PDF cached data by scaling them appropriately according to the battery-saver mode (from max 80MB to 64MB down to 24MB) preventing long-lived memory consumption which affects scroll janks when reopening files.

## Summary
The performance metrics across heavy loads, specifically Image conversions and concurrent background works, are structurally bounded. We bypassed isolating unsendable callbacks directly.

## Test and Safety Results
All unit and widget tests continue to pass with the introduction of our explicit job queue mapping and Riverpod cache scaling adjustments. The queue behavior has been tested with regression unit tests to assert execution behaviors. Memory usage is expected to be explicitly clamped based on `PdfViewerScreen` limits.
