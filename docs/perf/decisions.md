# Phase 3: PDF Operations Pipeline

The task requires fixing the pdf operations pipeline.
The `ToolsService` orchestrates these operations.
Currently, they use `Isolate.run` and `syncfusion_flutter_pdf` in a fairly standard way, but we are asked to improve them:

1. Move all heavy work off the main isolate. Pass file paths, never large byte arrays.
   - Most operations currently use `Isolate.run` and pass paths (e.g. `imagesToPdf`, `mergePdfs`).
   - `compressPdf` extracts pages, runs `img.encodeJpg` in an Isolate, but still passes `Uint8List` pixels across isolate boundaries when returning.
2. Use file-based I/O.
   - Currently, `syncfusion.PdfDocument` is initialized using `inputBytes: File(inputPath).readAsBytesSync()`. We should avoid this if the library supports stream or path-based access, but Syncfusion Flutter PDF *does not* support path-based or stream-based loading (it only accepts `List<int>`).
3. Build one reusable job system.
   - We need a bounded queue with progress reporting and user cancellation.
