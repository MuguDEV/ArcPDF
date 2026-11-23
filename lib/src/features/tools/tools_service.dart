import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'job_queue.dart';
import '../../core/native/native_job_runtime.dart';
import '../../core/platform/android_job_service.dart';
import 'utils/page_selection.dart';
import 'tool_failure.dart';

const _toolMemoryLimitBytes = 256 * 1024 * 1024;
const _mergeInputLimitBytes = 768 * 1024 * 1024;

typedef _ManagedToolAction = Future<String?> Function(
  void Function(JobProgress progress) report,
  Future<void> Function() checkCancelled,
);

enum _PdfWorkerOperation { merge, rearrange, splitSelection, imagesToPdf }

/// Runs memory-heavy Syncfusion work in a dedicated isolate. Unlike
/// [Isolate.run], this worker can be terminated immediately when the user
/// cancels and can stream useful progress while it is running.
Future<String?> _runPdfWorker({
  required _PdfWorkerOperation operation,
  required List<Object?> arguments,
  void Function(JobProgress progress)? onProgress,
  Future<void> Function()? checkCancelled,
}) async {
  final messages = ReceivePort();
  final errors = ReceivePort();
  final exited = ReceivePort();
  final completer = Completer<String?>();
  Isolate? isolate;
  Timer? cancellationPoll;
  var checkingCancellation = false;
  var receivedResult = false;

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace ?? StackTrace.current);
    }
  }

  late final StreamSubscription<Object?> messageSubscription;
  late final StreamSubscription<Object?> errorSubscription;
  late final StreamSubscription<Object?> exitSubscription;
  messageSubscription = messages.listen((message) {
    if (message is! List || message.isEmpty) return;
    switch (message.first) {
      case 'progress':
        onProgress?.call(JobProgress(
          percentage: (message[1] as num).toDouble().clamp(0, 1),
          stage: message[2] as String,
        ));
      case 'result':
        receivedResult = true;
        if (!completer.isCompleted) completer.complete(message[1] as String?);
      case 'error':
        completeError(ToolFailure(
          ToolFailureCode.values.byName(message[1] as String),
          message[2] as String,
          technicalDetails: message.length > 3 ? message[3] as String? : null,
        ));
    }
  });
  errorSubscription = errors.listen((message) {
    final details = message is List && message.isNotEmpty
        ? message.first.toString()
        : 'PDF worker failed';
    completeError(StateError(details));
  });
  exitSubscription = exited.listen((_) {
    if (!receivedResult && !completer.isCompleted) {
      completeError(StateError('PDF worker stopped before producing output'));
    }
  });

  try {
    isolate = await Isolate.spawn<List<Object?>>(
      _pdfWorkerMain,
      [messages.sendPort, operation.index, ...arguments],
      onError: errors.sendPort,
      onExit: exited.sendPort,
      errorsAreFatal: true,
      debugName: 'ArcPDF-${operation.name}',
    );
    if (checkCancelled != null) {
      cancellationPoll = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (checkingCancellation || completer.isCompleted) return;
        checkingCancellation = true;
        checkCancelled().then((_) {
          checkingCancellation = false;
        }).catchError((Object error, StackTrace stackTrace) {
          checkingCancellation = false;
          isolate?.kill(priority: Isolate.immediate);
          if (error is NativeJobCancelledException) {
            completeError(error, stackTrace);
          } else {
            completeError(const JobCancelledException(), stackTrace);
          }
        });
      });
    }
    return await completer.future;
  } finally {
    cancellationPoll?.cancel();
    isolate?.kill(priority: Isolate.immediate);
    await messageSubscription.cancel();
    await errorSubscription.cancel();
    await exitSubscription.cancel();
    messages.close();
    errors.close();
    exited.close();
  }
}

Future<void> _pdfWorkerMain(List<Object?> request) async {
  final sendPort = request[0] as SendPort;
  final operation = _PdfWorkerOperation.values[request[1] as int];

  void report(double progress, String stage) {
    sendPort.send(['progress', progress, stage]);
  }

  try {
    final String? result;
    switch (operation) {
      case _PdfWorkerOperation.merge:
        result = await _mergePdfsInIsolate(
          (request[2] as List).cast<String>(),
          request[3] as String,
          report,
        );
      case _PdfWorkerOperation.rearrange:
        result = await _rearrangePdfInIsolate(
          request[2] as String,
          request[3] as String,
          (request[4] as List).cast<int>(),
          report,
        );
      case _PdfWorkerOperation.splitSelection:
        result = await _splitPdfSelectionInIsolate(
          request[2] as String,
          request[3] as String,
          request[4] as String,
          report,
        );
      case _PdfWorkerOperation.imagesToPdf:
        result = await _imagesToPdfInIsolate(
          (request[2] as List).cast<String>(),
          request[3] as String,
          ImagePdfPageSize.values[request[4] as int],
          report,
        );
    }
    sendPort.send(['result', result]);
  } catch (error) {
    final failure = ToolFailure.from(error);
    sendPort.send([
      'error',
      failure.code.name,
      failure.message,
      failure.technicalDetails,
    ]);
  }
}

Future<String?> _runManagedToolJob({
  required String operation,
  required String title,
  required String outputPath,
  required _ManagedToolAction action,
  void Function(JobProgress progress)? onProgress,
  Future<void> Function()? checkCancelled,
}) async {
  final runtime = Platform.isAndroid ? NativeJobRuntime.tryOpen() : null;
  if (runtime == null) {
    return action(
      (progress) => onProgress?.call(progress),
      () async => checkCancelled?.call(),
    );
  }
  try {
    var lastPlatformUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    final result = await runtime.executeExternal(
      operation: operation,
      onHandle: (handle) {
        unawaited(AndroidJobService.start(
          jobId: handle.id.toString(),
          title: title,
          stage: 'Preparing…',
          outputPath: outputPath,
        ));
      },
      action: (context) async {
        void report(JobProgress progress) {
          onProgress?.call(progress);
          // Updating the Rust runtime and Android notification for every page
          // adds measurable FFI/Binder overhead on large documents. Keep the
          // in-app UI immediate, but coalesce platform updates.
          final now = DateTime.now();
          if (progress.percentage >= 1 ||
              now.difference(lastPlatformUpdate) >=
                  const Duration(milliseconds: 250)) {
            lastPlatformUpdate = now;
            context.update(
              stage: progress.stage,
              progress: progress.percentage,
            );
            unawaited(AndroidJobService.update(
              stage: progress.stage,
              progress: progress.percentage,
            ));
          }
        }

        Future<void> check() async {
          try {
            await checkCancelled?.call();
          } on JobCancelledException {
            context.handle.cancel();
            throw const NativeJobCancelledException();
          }
          context.checkCancelled();
        }

        final output = await action(report, check);
        if (output == null) throw StateError('$operation produced no output');
        return {'outputPath': output};
      },
    );
    return result['outputPath'] as String?;
  } on NativeJobCancelledException {
    throw const JobCancelledException();
  } on NativeJobException catch (error) {
    throw ToolFailure.from(error);
  } finally {
    await AndroidJobService.finish();
  }
}

Future<Map<String, dynamic>> _runNativePdfJob({
  required NativeJobRuntime runtime,
  required Map<String, dynamic> request,
  required String title,
  required String outputPath,
  void Function(JobProgress progress)? onProgress,
  Future<void> Function()? checkCancelled,
}) async {
  NativeJobHandle? nativeHandle;
  Timer? cancellationPoll;
  var checkingCancellation = false;
  var lastPlatformUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  try {
    final future = runtime.executeNativePdf(
      request: request,
      onHandle: (handle) {
        nativeHandle = handle;
        unawaited(AndroidJobService.start(
          jobId: handle.id.toString(),
          title: title,
          stage: 'Preparing…',
          outputPath: outputPath,
        ));
      },
      onEvent: (event) {
        final progress = event.progress;
        if (progress != null) {
          onProgress?.call(JobProgress(
            percentage: progress.clamp(0, 1),
            stage: event.stage,
          ));
        }
        final now = DateTime.now();
        if (event.state.isTerminal ||
            now.difference(lastPlatformUpdate) >=
                const Duration(milliseconds: 250)) {
          lastPlatformUpdate = now;
          unawaited(AndroidJobService.update(
            stage: event.stage,
            progress: progress,
          ));
        }
      },
    );
    if (checkCancelled != null) {
      cancellationPoll = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (checkingCancellation) return;
        checkingCancellation = true;
        checkCancelled().then((_) {
          checkingCancellation = false;
        }).catchError((Object _) {
          checkingCancellation = false;
          nativeHandle?.cancel();
        });
      });
    }
    return await future;
  } on NativeJobCancelledException {
    throw const JobCancelledException();
  } on NativeJobException catch (error) {
    final code = switch (error.error.code) {
      'missing_input' => ToolFailureCode.missingInput,
      'corrupted_pdf' => ToolFailureCode.corruptedPdf,
      'encrypted_pdf' => ToolFailureCode.encryptedPdf,
      'unsupported_pdf' => ToolFailureCode.unsupportedFile,
      'invalid_selection' => ToolFailureCode.invalidSelection,
      'output_exists' => ToolFailureCode.outputExists,
      'storage_full' => ToolFailureCode.storageFull,
      'permission_denied' => ToolFailureCode.permissionDenied,
      'output_unavailable' => ToolFailureCode.permissionDenied,
      _ => ToolFailureCode.unknown,
    };
    throw ToolFailure(code, error.error.message);
  } finally {
    cancellationPoll?.cancel();
    await AndroidJobService.finish();
  }
}

class PdfMetadataInfo {
  final String title;
  final String author;
  final String subject;
  final String keywords;

  const PdfMetadataInfo({
    this.title = '',
    this.author = '',
    this.subject = '',
    this.keywords = '',
  });
}

enum PdfImageFormat { jpeg, png }

enum ImagePdfPageSize { a4, letter, fitImage }

class ToolsService {
  static Future<int> readPageCount(String inputPath) => Isolate.run(() {
        final document = syncfusion.PdfDocument(
            inputBytes: File(inputPath).readAsBytesSync());
        try {
          return document.pages.count;
        } finally {
          document.dispose();
        }
      });
  // Stage in the destination filesystem so a failed write never truncates the
  // source. Only explicit metadata overwrite may replace an existing file.
  static Future<String> save(List<int> bytes, String outputPath,
      {bool overwrite = false}) async {
    final output = File(outputPath);
    if (!overwrite && await output.exists()) {
      throw FileSystemException('Output already exists', outputPath);
    }
    final staging =
        await Directory(p.dirname(outputPath)).createTemp('.arcpdf_');
    try {
      final temp = File(p.join(staging.path, 'output'));
      await temp.writeAsBytes(bytes, flush: true);
      if (!overwrite && await output.exists()) {
        throw FileSystemException('Output already exists', outputPath);
      }
      await temp.rename(outputPath);
      return outputPath;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static Future<PdfMetadataInfo?> readPdfMetadata(String inputPath) =>
      Isolate.run(() {
        syncfusion.PdfDocument? document;
        try {
          document = syncfusion.PdfDocument(
              inputBytes: File(inputPath).readAsBytesSync());
          final info = document.documentInformation;
          return PdfMetadataInfo(
            title: info.title,
            author: info.author,
            subject: info.subject,
            keywords: info.keywords,
          );
        } catch (_) {
          return null;
        } finally {
          document?.dispose();
        }
      });

  static Future<String?> editPdfMetadata(
          {required String inputPath,
          required String outputPath,
          required String title,
          required String author,
          required String subject,
          required String keywords,
          void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled}) =>
      JobQueue().enqueue(
          _EditMetadataJob(
              inputPath, outputPath, title, author, subject, keywords),
          onProgress: onProgress,
          checkCancelled: checkCancelled);

  static syncfusion.PdfPage addPage(syncfusion.PdfDocument document, Size size,
      {syncfusion.PdfPageRotateAngle rotation =
          syncfusion.PdfPageRotateAngle.rotateAngle0}) {
    // A section owns its settings; changing document-wide settings can resize
    // previously added pages in mixed-size documents.
    final section = document.sections!.add();
    section.pageSettings.orientation = size.width > size.height
        ? syncfusion.PdfPageOrientation.landscape
        : syncfusion.PdfPageOrientation.portrait;
    section.pageSettings.size = size;
    section.pageSettings.margins.all = 0;
    section.pageSettings.rotate = rotation;
    return section.pages.add();
  }

  static void copyPage(
      syncfusion.PdfDocument target, syncfusion.PdfPage source) {
    addPage(target, source.size, rotation: source.rotation)
        .graphics
        .drawPdfTemplate(source.createTemplate(), Offset.zero);
  }

  static Future<String?> mergePdfs(List<String> inputPaths, String outputPath,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          void Function(JobHandle<String?>)? onHandle}) =>
      JobQueue().enqueue(_MergePdfsJob(inputPaths, outputPath),
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);

  static Future<String?> rearrangePdf(
          String inputPath, String outputPath, List<int> pagesToExtract,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          void Function(JobHandle<String?>)? onHandle}) =>
      JobQueue().enqueue(
          _RearrangePdfJob(inputPath, outputPath, pagesToExtract),
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);

  static Future<String?> splitPdf(
          String inputPath, String outputDirPath, List<int> pagesToExtract,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          void Function(JobHandle<String?>)? onHandle}) =>
      rearrangePdf(
          inputPath,
          p.join(outputDirPath,
              'split_${DateTime.now().microsecondsSinceEpoch}.pdf'),
          pagesToExtract,
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);

  /// Splits using the user's raw selection while the document is already
  /// open in the worker, avoiding a separate full parse just to count pages.
  static Future<String?> splitPdfSelection(
          String inputPath, String outputDirPath, String selection,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          void Function(JobHandle<String?>)? onHandle}) =>
      JobQueue().enqueue(
          _SplitPdfSelectionJob(
            inputPath,
            p.join(outputDirPath,
                'Split_${DateTime.now().microsecondsSinceEpoch}'),
            selection,
          ),
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);

  static Future<String?> compressPdf(String inputPath, String outputPath,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          void Function(JobHandle<String?>)? onHandle,
          int quality = 40,
          int maxThreads = 2,
          Future<PdfDocument> Function(String)? openDocument}) =>
      JobQueue().enqueue(
          _CompressPdfJob(
              inputPath, outputPath, quality, maxThreads, openDocument),
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);

  static Future<String?> _compressPdfImpl(String inputPath, String outputPath,
      {int quality = 40,
      int maxThreads = 2,
      Future<PdfDocument> Function(String)? openDocument,
      void Function(JobProgress)? onProgress,
      Future<void> Function()? checkCancelled}) async {
    if (maxThreads < 1 ||
        quality < 1 ||
        quality > 100 ||
        await File(outputPath).exists()) {
      return null;
    }
    PdfDocument? document;
    Directory? compressedPages;
    try {
      if (await File(inputPath).length() > _mergeInputLimitBytes) return null;
      document = await (openDocument ?? PdfDocument.openFile)(inputPath)
          .timeout(const Duration(seconds: 30));
      compressedPages =
          await Directory(p.dirname(outputPath)).createTemp('.arcpdf_pages_');
      final pages = <({String path, double width, double height})>[];
      if (document.pages.isEmpty) return null;
      // Raw page rasters are strictly bounded; compressed pages spill to the
      // destination filesystem instead of accumulating in memory.
      const bytesPerPage = 1200 * 1600 * 4;
      final boundedThreads = maxThreads
          .clamp(1, (_toolMemoryLimitBytes ~/ bytesPerPage).clamp(1, 4))
          .toInt();
      for (var start = 0;
          start < document.pages.length;
          start += boundedThreads) {
        final batch = <({
          Uint8List pixels,
          int width,
          int height,
          double originalWidth,
          double originalHeight
        })>[];
        final end = (start + boundedThreads).clamp(0, document.pages.length);
        if (onProgress != null) {
          onProgress(JobProgress(
              percentage: start / document.pages.length,
              stage: "Compressing pages..."));
        }
        if (checkCancelled != null) await checkCancelled();
        for (var index = start; index < end; index++) {
          final page = document.pages[index];
          final scale = [1.0, 1200 / page.width, 1600 / page.height]
              .reduce((a, b) => a < b ? a : b);
          final image = await page
              .render(
                  fullWidth: page.width * scale,
                  fullHeight: page.height * scale)
              .timeout(const Duration(seconds: 45));
          if (image == null) throw StateError('Page rendering failed');
          late Uint8List pixels;
          final width = image.width;
          final height = image.height;
          try {
            pixels = Uint8List.fromList(image.pixels);
          } finally {
            image.dispose();
          }
          batch.add((
            pixels: pixels,
            width: width,
            height: height,
            originalWidth: page.width,
            originalHeight: page.height
          ));
        }
        pages.addAll(await Future.wait(batch.asMap().entries.map((entry) async {
          final page = entry.value;
          final pixels = TransferableTypedData.fromList([page.pixels]);
          final bytes = await Isolate.run(() => img.encodeJpg(
              img.Image.fromBytes(
                  width: page.width,
                  height: page.height,
                  bytes: pixels.materialize(),
                  numChannels: 4,
                  order: img.ChannelOrder.bgra),
              quality: quality));
          final pagePath =
              p.join(compressedPages!.path, 'page_${start + entry.key}.jpg');
          await File(pagePath).writeAsBytes(bytes, flush: false);
          return (
            path: pagePath,
            width: page.originalWidth,
            height: page.originalHeight
          );
        })));
        onProgress?.call(JobProgress(
          percentage: end / document.pages.length,
          stage: end == document.pages.length
              ? 'Building compressed PDF…'
              : 'Compressed $end of ${document.pages.length} pages',
        ));
      }
      return await Isolate.run(() async {
        final output = syncfusion.PdfDocument();
        try {
          output.compressionLevel = syncfusion.PdfCompressionLevel.best;
          for (final page in pages) {
            addPage(output, Size(page.width, page.height)).graphics.drawImage(
                syncfusion.PdfBitmap(File(page.path).readAsBytesSync()),
                Rect.fromLTWH(0, 0, page.width, page.height));
          }
          return await ToolsService.save(output.saveSync(), outputPath);
        } finally {
          output.dispose();
        }
      });
    } on JobCancelledException {
      rethrow;
    } on NativeJobCancelledException {
      rethrow;
    } catch (error) {
      throw ToolFailure.from(error, path: inputPath);
    } finally {
      await document?.dispose();
      if (compressedPages != null && await compressedPages.exists()) {
        await compressedPages.delete(recursive: true);
      }
    }
  }

  static Future<String?> pdfToImages(String inputPath, String outputParent,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          void Function(JobHandle<String?>)? onHandle,
          int dpi = 144,
          PdfImageFormat format = PdfImageFormat.jpeg,
          int quality = 90,
          Future<PdfDocument> Function(String)? openDocument}) =>
      JobQueue().enqueue(
          _PdfToImagesJob(
              inputPath, outputParent, dpi, format, quality, openDocument),
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);

  static Future<String?> _pdfToImagesImpl(String inputPath, String outputParent,
      {Future<PdfDocument> Function(String)? openDocument,
      int dpi = 144,
      PdfImageFormat format = PdfImageFormat.jpeg,
      int quality = 90,
      void Function(JobProgress)? onProgress,
      Future<void> Function()? checkCancelled}) async {
    if (dpi < 72 || dpi > 300 || quality < 1 || quality > 100) return null;
    PdfDocument? document;
    Directory? output;
    Future<void>? pendingEncode;
    try {
      document = await (openDocument ?? PdfDocument.openFile)(inputPath)
          .timeout(const Duration(seconds: 30));
      if (document.pages.isEmpty) return null;
      output = await Directory(outputParent).createTemp('Extracted_');
      for (var index = 0; index < document.pages.length; index++) {
        if (onProgress != null) {
          onProgress(JobProgress(
              percentage: index / document.pages.length,
              stage: "Extracting pages..."));
        }
        if (checkCancelled != null) await checkCancelled();
        final page = document.pages[index];
        final scale = dpi / 72;
        final targetWidth = (page.width * scale).clamp(1, 5000).toDouble();
        final targetHeight = (page.height * scale).clamp(1, 5000).toDouble();
        final image = await page
            .render(fullWidth: targetWidth, fullHeight: targetHeight)
            .timeout(const Duration(seconds: 45));
        if (image == null) throw StateError('Page rendering failed');
        late Uint8List pixels;
        final width = image.width;
        final height = image.height;
        try {
          pixels = Uint8List.fromList(image.pixels);
        } finally {
          image.dispose();
        }
        final extension = format == PdfImageFormat.png ? 'png' : 'jpg';
        final outputPath = p.join(output.path, 'page_${index + 1}.$extension');
        // Pipeline one background JPEG encode with the next native page render.
        // This keeps memory bounded to two pages while avoiding idle CPU time.
        await pendingEncode;
        final transferable = TransferableTypedData.fromList([pixels]);
        pendingEncode = Isolate.run(() async {
          final bitmap = img.Image.fromBytes(
              width: width,
              height: height,
              bytes: transferable.materialize(),
              numChannels: 4,
              order: img.ChannelOrder.bgra);
          final encoded = format == PdfImageFormat.png
              ? img.encodePng(bitmap)
              : img.encodeJpg(bitmap, quality: quality);
          await File(outputPath).writeAsBytes(encoded, flush: false);
        });
      }
      await pendingEncode;
      onProgress
          ?.call(const JobProgress(percentage: 1, stage: 'Images extracted'));
      return output.path;
    } catch (error) {
      try {
        await pendingEncode;
      } catch (_) {
        // The operation already failed; wait only to release the worker safely.
      }
      if (output != null && await output.exists()) {
        await output.delete(recursive: true);
      }
      throw ToolFailure.from(error, path: inputPath);
    } finally {
      await document?.dispose();
    }
  }

  static Future<String?> imagesToPdf(List<String> imagePaths, String outputPath,
          {void Function(JobProgress)? onProgress,
          Future<void> Function()? checkCancelled,
          ImagePdfPageSize pageSize = ImagePdfPageSize.a4,
          void Function(JobHandle<String?>)? onHandle}) =>
      JobQueue().enqueue(_ImagesToPdfJob(imagePaths, outputPath, pageSize),
          onProgress: onProgress,
          checkCancelled: checkCancelled,
          onHandle: onHandle);
}

class _MergePdfsJob extends Job<String?> {
  final List<String> inputPaths;
  final String outputPath;

  _MergePdfsJob(this.inputPaths, this.outputPath);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) async {
    try {
      if (inputPaths.length < 2) return null;
      var totalBytes = 0;
      for (final path in inputPaths) {
        final file = File(path);
        if (!await file.exists()) {
          throw ToolFailure(
            ToolFailureCode.missingInput,
            'The selected file is no longer available: $path',
          );
        }
        totalBytes += await file.length();
        if (totalBytes > _mergeInputLimitBytes) return null;
      }
      final nativeRuntime =
          Platform.isAndroid ? NativeJobRuntime.tryOpen() : null;
      if (nativeRuntime != null) {
        final result = await _runNativePdfJob(
          runtime: nativeRuntime,
          request: {
            'operation': 'merge',
            'inputPaths': inputPaths,
            'outputPath': outputPath,
          },
          title: 'Merging PDFs',
          outputPath: outputPath,
          onProgress: onProgress,
          checkCancelled: checkCancelled,
        );
        return result['outputPath'] as String?;
      }
      return await _runManagedToolJob(
        operation: 'merge',
        title: 'Merging PDFs',
        outputPath: outputPath,
        onProgress: onProgress,
        checkCancelled: checkCancelled,
        action: (report, check) async {
          report(const JobProgress(percentage: 0, stage: 'Preparing merge…'));
          await check();
          final result = await _runPdfWorker(
            operation: _PdfWorkerOperation.merge,
            arguments: [inputPaths, outputPath],
            onProgress: report,
            checkCancelled: check,
          );
          await check();
          report(const JobProgress(percentage: 1, stage: 'Merge complete'));
          return result;
        },
      );
    } on JobCancelledException {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      rethrow;
    } on ToolFailure {
      rethrow;
    } catch (error) {
      throw ToolFailure.from(error);
    }
  }
}

class _RearrangePdfJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final List<int> pagesToExtract;

  _RearrangePdfJob(this.inputPath, this.outputPath, this.pagesToExtract);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) async {
    try {
      onProgress
          ?.call(const JobProgress(percentage: 0, stage: 'Preparing pages…'));
      if (checkCancelled != null) await checkCancelled();
      final nativeRuntime =
          Platform.isAndroid ? NativeJobRuntime.tryOpen() : null;
      if (nativeRuntime != null) {
        final result = await _runNativePdfJob(
          runtime: nativeRuntime,
          request: {
            'operation': 'organize',
            'inputPath': inputPath,
            'outputPath': outputPath,
            'pages': pagesToExtract,
          },
          title: 'Organizing PDF',
          outputPath: outputPath,
          onProgress: onProgress,
          checkCancelled: checkCancelled,
        );
        return result['outputPath'] as String?;
      }
      final result = await _runPdfWorker(
        operation: _PdfWorkerOperation.rearrange,
        arguments: [inputPath, outputPath, pagesToExtract],
        onProgress: onProgress,
        checkCancelled: checkCancelled,
      );
      if (checkCancelled != null) await checkCancelled();
      onProgress?.call(const JobProgress(percentage: 1, stage: 'Pages saved'));
      return result;
    } on JobCancelledException {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      rethrow;
    } on ToolFailure {
      rethrow;
    } catch (error) {
      throw ToolFailure.from(error, path: inputPath);
    }
  }
}

class _SplitPdfSelectionJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final String selection;

  _SplitPdfSelectionJob(this.inputPath, this.outputPath, this.selection);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) async {
    try {
      onProgress?.call(const JobProgress(percentage: 0, stage: 'Reading PDF…'));
      if (checkCancelled != null) await checkCancelled();
      final nativeRuntime =
          Platform.isAndroid ? NativeJobRuntime.tryOpen() : null;
      if (nativeRuntime != null) {
        final result = await _runNativePdfJob(
          runtime: nativeRuntime,
          request: {
            'operation': 'split',
            'inputPath': inputPath,
            'outputPath': outputPath,
            'selection': selection,
          },
          title: 'Splitting PDF',
          outputPath: outputPath,
          onProgress: onProgress,
          checkCancelled: checkCancelled,
        );
        return result['outputPath'] as String?;
      }
      final result = await _runPdfWorker(
        operation: _PdfWorkerOperation.splitSelection,
        arguments: [inputPath, outputPath, selection],
        onProgress: onProgress,
        checkCancelled: checkCancelled,
      );
      if (checkCancelled != null) await checkCancelled();
      onProgress?.call(const JobProgress(percentage: 1, stage: 'Pages saved'));
      return result;
    } on JobCancelledException {
      final output = Directory(outputPath);
      if (await output.exists()) await output.delete(recursive: true);
      rethrow;
    } on FormatException {
      rethrow;
    } on ToolFailure {
      rethrow;
    } catch (error) {
      throw ToolFailure.from(error, path: inputPath);
    }
  }
}

Future<String?> _mergePdfsInIsolate(List<String> inputPaths, String outputPath,
    [void Function(double progress, String stage)? report]) async {
  final document = syncfusion.PdfDocument();
  try {
    for (var inputIndex = 0; inputIndex < inputPaths.length; inputIndex++) {
      final path = inputPaths[inputIndex];
      final source =
          syncfusion.PdfDocument(inputBytes: File(path).readAsBytesSync());
      try {
        for (var j = 0; j < source.pages.count; j++) {
          ToolsService.copyPage(document, source.pages[j]);
          final withinFile = (j + 1) / source.pages.count;
          report?.call(
            (inputIndex + withinFile) / inputPaths.length * 0.92,
            'Merging file ${inputIndex + 1} of ${inputPaths.length}',
          );
        }
      } finally {
        source.dispose();
      }
    }
    report?.call(0.94, 'Writing merged PDF…');
    return await ToolsService.save(document.saveSync(), outputPath);
  } finally {
    document.dispose();
  }
}

Future<String?> _rearrangePdfInIsolate(
    String inputPath, String outputPath, List<int> pages,
    [void Function(double progress, String stage)? report]) async {
  final source =
      syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
  final document = syncfusion.PdfDocument();
  try {
    if (pages.isEmpty ||
        pages.any((page) => page < 1 || page > source.pages.count)) {
      return null;
    }
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      ToolsService.copyPage(document, source.pages[page - 1]);
      report?.call((index + 1) / pages.length * 0.92,
          'Processing page ${index + 1} of ${pages.length}');
    }
    report?.call(0.94, 'Writing PDF…');
    return await ToolsService.save(document.saveSync(), outputPath);
  } finally {
    document.dispose();
    source.dispose();
  }
}

Future<String?> _splitPdfSelectionInIsolate(
    String inputPath,
    String outputPath,
    String selection,
    void Function(double progress, String stage)? report) async {
  final source =
      syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
  final outputDirectory = Directory(outputPath);
  try {
    final groups =
        parsePageSelectionGroups(selection, pageCount: source.pages.count);
    final totalPages =
        groups.fold<int>(0, (total, group) => total + group.pages.length);
    await outputDirectory.create(recursive: true);
    var processed = 0;
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      final document = syncfusion.PdfDocument();
      try {
        for (final page in group.pages) {
          ToolsService.copyPage(document, source.pages[page - 1]);
          processed++;
          report?.call(processed / totalPages * 0.9,
              'Creating file ${groupIndex + 1} of ${groups.length}');
        }
        final label = group.start == group.end
            ? 'page_${group.start}.pdf'
            : 'pages_${group.start}-${group.end}.pdf';
        await ToolsService.save(
          document.saveSync(),
          p.join(outputDirectory.path, label),
        );
      } finally {
        document.dispose();
      }
    }
    report?.call(1, 'Created ${groups.length} PDF files');
    return outputDirectory.path;
  } catch (_) {
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    rethrow;
  } finally {
    source.dispose();
  }
}

class _ImagesToPdfJob extends Job<String?> {
  final List<String> imagePaths;
  final String outputPath;
  final ImagePdfPageSize pageSize;

  _ImagesToPdfJob(this.imagePaths, this.outputPath, this.pageSize);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) async {
    try {
      if (imagePaths.isEmpty) return null;
      onProgress
          ?.call(const JobProgress(percentage: 0, stage: 'Preparing images…'));
      if (checkCancelled != null) await checkCancelled();
      for (final path in imagePaths) {
        if (!await File(path).exists()) {
          throw ToolFailure(
            ToolFailureCode.missingInput,
            'The selected image is no longer available: $path',
          );
        }
      }
      final result = await _runPdfWorker(
        operation: _PdfWorkerOperation.imagesToPdf,
        arguments: [imagePaths, outputPath, pageSize.index],
        onProgress: onProgress,
        checkCancelled: checkCancelled,
      );
      if (checkCancelled != null) await checkCancelled();
      onProgress?.call(const JobProgress(percentage: 1, stage: 'PDF created'));
      return result;
    } on JobCancelledException {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      rethrow;
    } on ToolFailure {
      rethrow;
    } catch (error) {
      throw ToolFailure.from(error);
    }
  }
}

Future<String?> _imagesToPdfInIsolate(
    List<String> imagePaths, String outputPath, ImagePdfPageSize pageSize,
    [void Function(double progress, String stage)? report]) async {
  final document = syncfusion.PdfDocument();
  try {
    for (var index = 0; index < imagePaths.length; index++) {
      final path = imagePaths[index];
      final bytes = File(path).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const ToolFailure(
          ToolFailureCode.unsupportedFile,
          'One of the selected images could not be decoded.',
        );
      }
      var oriented = img.bakeOrientation(decoded);
      const maxLongEdge = 3000;
      if (oriented.width > maxLongEdge || oriented.height > maxLongEdge) {
        if (oriented.width >= oriented.height) {
          oriented = img.copyResize(oriented, width: maxLongEdge);
        } else {
          oriented = img.copyResize(oriented, height: maxLongEdge);
        }
      }
      final encoded = oriented.hasAlpha
          ? img.encodePng(oriented)
          : img.encodeJpg(oriented, quality: 92);
      final bitmap = syncfusion.PdfBitmap(encoded);
      final portrait = oriented.height >= oriented.width;
      final Size size;
      switch (pageSize) {
        case ImagePdfPageSize.a4:
          size = portrait
              ? const Size(595.28, 841.89)
              : const Size(841.89, 595.28);
        case ImagePdfPageSize.letter:
          size = portrait ? const Size(612, 792) : const Size(792, 612);
        case ImagePdfPageSize.fitImage:
          // Treat source pixels as 144 DPI instead of one pixel per point.
          size = Size(oriented.width * 0.5, oriented.height * 0.5);
      }
      const margin = 24.0;
      final availableWidth = (size.width - margin * 2).clamp(1, size.width);
      final availableHeight = (size.height - margin * 2).clamp(1, size.height);
      final fitScale = [
        availableWidth / bitmap.width,
        availableHeight / bitmap.height,
      ].reduce((a, b) => a < b ? a : b);
      final drawWidth = bitmap.width * fitScale;
      final drawHeight = bitmap.height * fitScale;
      final bounds = Rect.fromLTWH(
        (size.width - drawWidth) / 2,
        (size.height - drawHeight) / 2,
        drawWidth,
        drawHeight,
      );
      ToolsService.addPage(document, size).graphics.drawImage(bitmap, bounds);
      report?.call((index + 1) / imagePaths.length * 0.92,
          'Adding image ${index + 1} of ${imagePaths.length}');
    }
    report?.call(0.94, 'Writing PDF…');
    return await ToolsService.save(document.saveSync(), outputPath);
  } finally {
    document.dispose();
  }
}

class _CompressPdfJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final int quality;
  final int maxThreads;
  final Future<PdfDocument> Function(String)? openDocument;

  _CompressPdfJob(this.inputPath, this.outputPath, this.quality,
      this.maxThreads, this.openDocument);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
          Future<void> Function()? checkCancelled) =>
      _runManagedToolJob(
        operation: 'compression',
        title: 'Compressing PDF',
        outputPath: outputPath,
        onProgress: onProgress,
        checkCancelled: checkCancelled,
        action: (report, check) => ToolsService._compressPdfImpl(
          inputPath,
          outputPath,
          quality: quality,
          maxThreads: maxThreads,
          openDocument: openDocument,
          onProgress: report,
          checkCancelled: check,
        ),
      );
}

class _PdfToImagesJob extends Job<String?> {
  final String inputPath;
  final String outputParent;
  final int dpi;
  final PdfImageFormat format;
  final int quality;
  final Future<PdfDocument> Function(String)? openDocument;

  _PdfToImagesJob(this.inputPath, this.outputParent, this.dpi, this.format,
      this.quality, this.openDocument);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) {
    return ToolsService._pdfToImagesImpl(inputPath, outputParent,
        openDocument: openDocument,
        dpi: dpi,
        format: format,
        quality: quality,
        onProgress: onProgress,
        checkCancelled: checkCancelled);
  }
}

class _EditMetadataJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final String title;
  final String author;
  final String subject;
  final String keywords;

  _EditMetadataJob(this.inputPath, this.outputPath, this.title, this.author,
      this.subject, this.keywords);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) async {
    try {
      onProgress
          ?.call(const JobProgress(percentage: 0, stage: 'Updating metadata…'));
      if (checkCancelled != null) await checkCancelled();
      final result = await Isolate.run(() => _editMetadataInIsolate(
          inputPath, outputPath, title, author, subject, keywords));
      if (checkCancelled != null) await checkCancelled();
      onProgress
          ?.call(const JobProgress(percentage: 1, stage: 'Metadata saved'));
      return result;
    } on JobCancelledException {
      rethrow;
    } on ToolFailure {
      rethrow;
    } catch (error) {
      throw ToolFailure.from(error, path: inputPath);
    }
  }
}

Future<String?> _editMetadataInIsolate(String inputPath, String outputPath,
    String title, String author, String subject, String keywords) async {
  syncfusion.PdfDocument? document;
  try {
    document =
        syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final info = document.documentInformation;
    info.title = title;
    info.author = author;
    info.subject = subject;
    info.keywords = keywords;
    return await ToolsService.save(document.saveSync(), outputPath,
        overwrite: p.equals(p.absolute(inputPath), p.absolute(outputPath)));
  } finally {
    document?.dispose();
  }
}
