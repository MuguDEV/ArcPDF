import 'dart:io';

import 'package:arcpdf/src/features/pdf/data/native_pdf_scanner.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
        'Usage: dart run tool/benchmark_native_scanner.dart <native-library>');
    exitCode = 64;
    return;
  }
  final root = await Directory('/dev/shm').createTemp('arcpdf_benchmark_');
  try {
    const header = '%PDF-1.7\n';
    for (var group = 0; group < 100; group++) {
      final body = '$header${'d' * (512 + group)}\n%%EOF';
      await File(p.join(root.path, 'duplicate_${group}_a.pdf'))
          .writeAsString(body);
      await File(p.join(root.path, 'duplicate_${group}_b.pdf'))
          .writeAsString(body);
    }
    for (var index = 0; index < 1800; index++) {
      await File(p.join(root.path, 'unique_$index.pdf'))
          .writeAsString('$header${'u' * (2048 + index)}$index\n%%EOF');
    }
    final cacheDir = p.join(root.path, '.cache');
    final cachePath = p.join(cacheDir, 'hashes.json');

    Future<({NativePdfScanResult result, int wallMillis})> run() async {
      final timer = Stopwatch()..start();
      final result = await NativePdfScanner.scan(
        roots: [root.path],
        excludedRoots: [cacheDir],
        cachePath: cachePath,
        libraryPath: p.absolute(arguments.first),
      );
      timer.stop();
      if (result == null) throw StateError('Native scanner did not load');
      return (result: result, wallMillis: timer.elapsedMilliseconds);
    }

    final cold = await run();
    final warm = await run();
    stdout.writeln(
      'cold: ${cold.result.files.length} files, '
      '${cold.result.duplicateGroups.length} groups, '
      '${cold.result.stats.filesHashed} hashes, '
      '${cold.result.stats.elapsedMillis} ms native / ${cold.wallMillis} ms wall',
    );
    stdout.writeln(
      'warm: ${warm.result.files.length} files, '
      '${warm.result.duplicateGroups.length} groups, '
      '${warm.result.stats.cacheHits} cache hits, '
      '${warm.result.stats.elapsedMillis} ms native / ${warm.wallMillis} ms wall',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
