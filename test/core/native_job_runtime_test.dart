import 'dart:io';

import 'package:arcpdf/src/core/native/native_job_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final library = p.join(
    Directory.current.path,
    'native',
    'arcpdf_indexer',
    'target',
    'release',
    'libarcpdf_indexer.so',
  );
  final available = File(library).existsSync();

  test(
    'external jobs report structured progress and results',
    () async {
      final runtime = NativeJobRuntime.tryOpen(libraryPath: library)!;
      final events = <NativeJobSnapshot>[];
      final result = await runtime.executeExternal(
        operation: 'merge',
        onEvent: events.add,
        action: (context) async {
          context.update(
            stage: 'Merging document 1 of 2',
            progress: 0.5,
            processed: 1,
            total: 2,
          );
          return {'outputPath': '/tmp/merged.pdf'};
        },
      );
      expect(result['outputPath'], '/tmp/merged.pdf');
      expect(events.last.state, NativeJobState.completed);
      expect(events.last.progress, 1);
    },
    skip: !available,
  );

  test(
    'external running jobs cooperatively cancel',
    () async {
      final runtime = NativeJobRuntime.tryOpen(libraryPath: library)!;
      late NativeJobHandle handle;
      final operation = runtime.executeExternal(
        operation: 'compression',
        onHandle: (value) => handle = value,
        action: (context) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          handle.cancel();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          context.checkCancelled();
          return const {'outputPath': '/tmp/compressed.pdf'};
        },
      );
      await expectLater(
        operation,
        throwsA(isA<NativeJobCancelledException>()),
      );
    },
    skip: !available,
  );
}
