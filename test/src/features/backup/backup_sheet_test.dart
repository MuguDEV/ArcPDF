import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:arcpdf/src/features/backup/backup_service.dart';
import 'package:arcpdf/src/features/backup/backup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService extends Fake implements BackupService {
  Future<BackupArchive> Function(String path)? onRead;
  Future<BackupRestoreResult> Function(BackupArchive, RestoreMode)? onRestore;
  Future<BackupExport> Function()? onExport;
  final restores = <RestoreMode>[];
  var exports = 0;

  @override
  Future<BackupExport> createExport() {
    exports++;
    return onExport != null ? onExport!() : Future.value(_export());
  }

  @override
  Future<BackupArchive> readFile(String path) =>
      onRead != null ? onRead!(path) : Future.value(_archive());

  @override
  Future<BackupRestoreResult> restore(BackupArchive archive,
      {required RestoreMode mode}) {
    restores.add(mode);
    return onRestore != null
        ? onRestore!(archive, mode)
        : Future.value(BackupRestoreResult(
            mode: mode,
            favorites: 2,
            taggedDocuments: 1,
            progress: 3,
            keptLocalProgress: mode == RestoreMode.merge ? 1 : 0,
            skipped: 0,
            securityApplied: true,
          ));
  }
}

class _FakeActions implements BackupFileActions {
  String? pickedPath = '/picked/backup.json';
  bool shareResult = true;
  bool saveResult = true;
  final shared = <String>[];
  final saved = <String>[];

  @override
  Future<String?> pickBackupPath() async => pickedPath;

  @override
  Future<bool> saveAs(BackupExport export) async {
    saved.add(export.fileName);
    return saveResult;
  }

  @override
  Future<bool> share(BackupExport export, {Rect? origin}) async {
    shared.add(export.fileName);
    return shareResult;
  }
}

BackupArchive _archive() => BackupArchive(
      schemaVersion: 1,
      appVersion: '1.4.4',
      createdAt: DateTime.utc(2026, 10, 20, 12),
      favorites: const ['/a.pdf', '/b.pdf'],
      tags: const {
        '/a.pdf': ['x', 'y'],
        '/b.pdf': ['y'],
      },
      progress: const {'/a.pdf': BackupProgress(page: 2)},
      security: const BackupSecurity(lockType: 0, requireLockOnResume: true),
    );

BackupExport _export() {
  final archive = _archive();
  return BackupExport(
    file: File('arcpdf-backup-test.json'),
    fileName: 'arcpdf-backup-test.json',
    bytes: Uint8List(0),
    preview: archive.preview,
  );
}

void main() {
  late _FakeService service;
  late _FakeActions actions;
  late int restoredCalls;

  setUp(() {
    service = _FakeService();
    actions = _FakeActions();
    restoredCalls = 0;
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.grey, brightness: brightness),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showBackupRestoreSheet(
                context,
                service: service,
                actions: actions,
                onRestored: () => restoredCalls++,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the three actions and the privacy statement',
      (tester) async {
    await mount(tester);
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Share backup'), findsOneWidget);
    expect(find.text('Save to device'), findsOneWidget);
    expect(find.text('Restore from backup file'), findsOneWidget);
    expect(find.textContaining('never included'), findsOneWidget);
  });

  testWidgets('action rows keep 48dp targets at 320px width and 3x text',
      (tester) async {
    await mount(tester, width: 320, height: 640, scale: 3);
    expect(tester.takeException(), isNull);
    for (final label in [
      'Share backup',
      'Save to device',
      'Restore from backup file',
    ]) {
      final row =
          find.ancestor(of: find.text(label), matching: find.byType(InkWell));
      await tester.ensureVisible(row);
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(48),
          reason: label);
      expect(tester.getSize(row.first).width, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 3.0]) {
    testWidgets('restore flow fits at 320px width with ${scale}x text',
        (tester) async {
      await mount(tester, width: 320, height: 640, scale: scale);
      await tapText(tester, 'Restore from backup file');
      expect(tester.takeException(), isNull);
      for (final finder in [
        find.widgetWithText(FilledButton, 'Merge backup'),
        find.widgetWithText(TextButton, 'Cancel'),
      ]) {
        await tester.ensureVisible(finder);
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      }
      await tapText(tester, 'Merge backup');
      expect(find.text('Restore complete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('restore preview shows counts and defaults to merge',
      (tester) async {
    await mount(tester);
    await tapText(tester, 'Restore from backup file');

    expect(find.text('Restore backup'), findsOneWidget);
    expect(find.textContaining('ArcPDF 1.4.4'), findsOneWidget);
    // favorites=2, tagged documents=2, progress=1, lock preferences included
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('Merge backup'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(service.restores, isEmpty);
  });

  testWidgets('merge restore completes without a confirmation dialog',
      (tester) async {
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    await tapText(tester, 'Merge backup');

    expect(service.restores, [RestoreMode.merge]);
    expect(restoredCalls, 1);
    expect(find.text('Restore complete'), findsOneWidget);
    expect(
        find.textContaining('already on this device was kept'), findsOneWidget);
    expect(find.textContaining('next time ArcPDF starts'), findsOneWidget);
    await tapText(tester, 'Done');
    expect(find.text('Restore complete'), findsNothing);
  });

  testWidgets('replace needs confirmation and can be cancelled',
      (tester) async {
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    await tapText(tester, 'Replace data on this device');
    expect(find.text('Replace data'), findsOneWidget);
    await tapText(tester, 'Replace data');

    expect(find.text('Replace data on this device?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(service.restores, isEmpty);
    expect(find.text('Restore backup'), findsOneWidget);

    await tapText(tester, 'Replace data');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Replace')));
    await tester.pumpAndSettle();
    expect(service.restores, [RestoreMode.replace]);
    expect(restoredCalls, 1);
    expect(find.text('Restore complete'), findsOneWidget);
  });

  testWidgets('cancel at the preview returns to the start without writing',
      (tester) async {
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    await tapText(tester, 'Cancel');
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(service.restores, isEmpty);
  });

  testWidgets('cancelling the file picker returns quietly', (tester) async {
    actions.pickedPath = null;
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Backup problem'), findsNothing);
  });

  testWidgets('invalid files show a safe message and a way back',
      (tester) async {
    service.onRead = (_) =>
        Future.error(const BackupException(BackupFailure.checksumMismatch));
    await mount(tester);
    await tapText(tester, 'Restore from backup file');

    expect(find.text('Backup problem'), findsOneWidget);
    expect(find.text(BackupFailure.checksumMismatch.message), findsOneWidget);
    expect(find.textContaining('/picked'), findsNothing);
    await tapText(tester, 'Back');
    expect(find.text('Backup & restore'), findsOneWidget);
  });

  testWidgets('a failed restore reports the error and never claims success',
      (tester) async {
    service.onRestore = (_, __) =>
        Future.error(const BackupException(BackupFailure.applyFailed));
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    await tapText(tester, 'Merge backup');

    expect(find.text(BackupFailure.applyFailed.message), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);
    expect(restoredCalls, 0);
  });

  testWidgets('unexpected errors are generic, not leaked', (tester) async {
    service.onRead = (_) => Future.error(StateError('/secret/path.pdf boom'));
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('share creates an export and hands it to the share sheet',
      (tester) async {
    await mount(tester);
    await tapText(tester, 'Share backup');
    expect(service.exports, 1);
    expect(actions.shared, ['arcpdf-backup-test.json']);
    expect(find.textContaining('Backup ready'), findsOneWidget);
  });

  testWidgets('dismissing the share sheet shows no success message',
      (tester) async {
    actions.shareResult = false;
    await mount(tester);
    await tapText(tester, 'Share backup');
    expect(actions.shared, hasLength(1));
    expect(find.textContaining('Backup ready'), findsNothing);
  });

  testWidgets('save to device writes through the file dialog', (tester) async {
    await mount(tester);
    await tapText(tester, 'Save to device');
    expect(actions.saved, ['arcpdf-backup-test.json']);
    expect(find.textContaining('Backup saved'), findsOneWidget);
  });

  testWidgets('export failures are reported', (tester) async {
    service.onExport =
        () => Future.error(const BackupException(BackupFailure.storage));
    await mount(tester);
    await tapText(tester, 'Share backup');
    expect(find.text(BackupFailure.storage.message), findsOneWidget);
    expect(actions.shared, isEmpty);
  });

  testWidgets(
      'while working a progress state replaces actions and blocks '
      'dismissal', (tester) async {
    final gate = Completer<BackupArchive>();
    service.onRead = (_) => gate.future;
    await mount(tester);
    await tester.tap(find.text('Restore from backup file'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Reading backup…'), findsOneWidget);
    expect(find.text('Share backup'), findsNothing);
    final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(popScope.canPop, isFalse);

    gate.complete(_archive());
    await tester.pumpAndSettle();
    expect(find.text('Restore backup'), findsOneWidget);
  });

  testWidgets('light theme renders without errors', (tester) async {
    await mount(tester, brightness: Brightness.light, width: 320, scale: 2);
    await tapText(tester, 'Restore from backup file');
    expect(tester.takeException(), isNull);
    expect(find.text('Restore backup'), findsOneWidget);
  });

  testWidgets('radio rows expose selection state to accessibility',
      (tester) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await tapText(tester, 'Restore from backup file');
    expect(
        tester.getSemantics(find.text('Merge with this device')),
        matchesSemantics(
            label: 'Merge with this device',
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true));
    handle.dispose();
  });
}
