# Phase 1: Inventory Audit

## A. Viewer configuration
- `PdfViewerScreen` in `lib/src/features/pdf/viewer/pdf_viewer_screen.dart` uses `PdfViewer.file`.
- Overridden parameters: `horizontalCacheExtent` (0.25 or 1.0 depending on scroll), `verticalCacheExtent` (1.0 or 0.25).
- `maxImageBytesCachedOnMemory` is hardcoded.
- `initialPageNumber` uses `_initialPage`.

## B. Rendering calls
- `PdfThumbnailCache.getThumbnail` calls `page.render()`. Image is disposed after decoding.
- `PdfViewerScreen` calls `page.render()` for something.
- `ToolsService` calls `page.render()` for image extraction and PDF to image. Calls dispose afterwards.

## C. Document lifecycle
- `PdfThumbnailCache` opens document `PdfDocument.openFile`. Disposed correctly via try/finally.
- `ToolsService` opens documents in operations like PDF to image.

## D. Search
- `PdfTextSearcher` is used in `PdfViewerScreen`. Re-created on viewer ready.

## E. Thumbnails
- `PdfThumbnailCache` uses `LinkedHashMap` for memory cache limit `_maxMemCacheSize = 100`.
- Task queue with `_maxConcurrentTasks = 4`.
- Runs on main isolate for rendering (using pdfrx), image data manipulation on isolates.

## F. PDF operations
- `ToolsService` orchestrates these.
- Uses `syncfusion_flutter_pdf` for some.
- Image to PDF uses `syncfusion_flutter_pdf`.
- Runs using `Isolate.run` in some places.

## G. State and storage
- Hive used for sessions and reading progress.
- Riverpod used for state.

## H. UI cost
- Needs manual check. `PdfCustomCard` uses `RepaintBoundary`.

## I. Dependencies
- Needs manual check for unused dependencies.
