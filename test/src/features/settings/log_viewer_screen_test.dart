import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/features/diagnostics/diagnostic_bundle_builder.dart';
import 'package:arcpdf/src/features/settings/log_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';

const _bugReportTooltip = 'Share bug report (logs, device info, app version)';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_log_colors_');
    Hive.init(directory.path);
    await AppLogger.init();
    await AppLogger.info('Information entry');
    await AppLogger.warning('Warning entry');
    await AppLogger.error('Error entry');
  });

  tearDown(() async {
    await AppLogger.flush();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final brightness in Brightness.values) {
    testWidgets('log severity stays monochrome in ${brightness.name} mode',
        (tester) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.grey,
        brightness: brightness,
      ).copyWith(
        onSurface: brightness == Brightness.light ? Colors.black : Colors.white,
        onSurfaceVariant: Colors.grey,
        outline: Colors.grey,
        outlineVariant: Colors.grey.shade500,
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const LogViewerScreen(),
      ));
      for (final icon in [
        Icons.warning_amber_rounded,
        Icons.error_outline_rounded
      ]) {
        final finder = find.byIcon(icon);
        expect(finder, findsOneWidget);
        expect(tester.widget<Icon>(finder).color, scheme.onSurface);
        final container = tester.widget<Container>(find
            .ancestor(
              of: finder,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container && widget.decoration is BoxDecoration),
            )
            .first);
        final decoration = container.decoration! as BoxDecoration;
        expect((decoration.border! as Border).top.color, scheme.outline);
      }
      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('INFO'), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.info_outline_rounded)).color,
          scheme.onSurfaceVariant);
      expect(tester.takeException(), isNull);
    });
  }

  group('bug report action', () {
    late List<ShareParams> shared;
    Object? shareFailure;
    Completer<Map<String, Object?>>? deviceGate;

    DiagnosticBundleBuilder builderFor(BuildContext _) =>
        DiagnosticBundleBuilder(
          app: () => {'name': 'ArcPDF', 'version': '1.4.4'},
          device: () async {
            final gate = deviceGate;
            if (gate == null) return {'model': 'Test Phone'};
            return gate.future;
          },
          logs: AppLogger.getLogs,
          clock: () => DateTime.utc(2026, 10, 20, 10, 15),
        );

    setUp(() {
      shared = [];
      shareFailure = null;
      deviceGate = null;
    });

    Future<void> mount(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          home: LogViewerScreen(
            bundleBuilder: builderFor,
            share: (params) async {
              shared.add(params);
              if (shareFailure != null) throw shareFailure!;
              return const ShareResult('ok', ShareResultStatus.success);
            },
          ),
        ));

    testWidgets('sits next to export with accessible tooltips', (tester) async {
      await mount(tester);
      expect(find.byTooltip('Export saved logs'), findsOneWidget);
      expect(find.byTooltip(_bugReportTooltip), findsOneWidget);
      expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
    });

    testWidgets('shares one text file anchored to the button', (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip(_bugReportTooltip));
      await tester.pumpAndSettle();

      expect(shared, hasLength(1));
      final params = shared.single;
      final file = params.files!.single;
      expect(params.fileNameOverrides,
          ['arcpdf-diagnostics-1.4.4-20261020T101500Z.txt']);
      expect(file.mimeType, 'text/plain');
      expect(params.sharePositionOrigin, isNotNull);
      expect(params.sharePositionOrigin!.isEmpty, isFalse);
      final text = (await tester.runAsync(file.readAsString))!;
      expect(text, contains('## app'));
      expect(text, contains('model: Test Phone'));
      expect(text, contains('Information entry'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('logs the export without its content', (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip(_bugReportTooltip));
      await tester.pumpAndSettle();

      final event = AppLogger.getLogs()
          .map((entry) => entry.message)
          .firstWhere(
              (message) => message.startsWith('diagnostics.bundle.shared'));
      expect(event, contains('status=success'));
      expect(event, contains('truncated=false'));
      expect(event, isNot(contains('Test Phone')));
      expect(event, isNot(contains('arcpdf-diagnostics')));
    });

    testWidgets('shows progress and blocks other actions while preparing',
        (tester) async {
      deviceGate = Completer();
      await mount(tester);
      await tester.tap(find.byTooltip(_bugReportTooltip));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Preparing bug report'), findsOneWidget);
      await tester.tap(find.byTooltip('Export saved logs'));
      await tester.tap(find.byTooltip('Preparing bug report'));
      await tester.pump();
      expect(shared, isEmpty);

      deviceGate!.complete({'model': 'Slow Phone'});
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip(_bugReportTooltip), findsOneWidget);
    });

    testWidgets('reports failure with a retry action', (tester) async {
      shareFailure = StateError('/storage/emulated/0/secret.pdf');
      await mount(tester);
      await tester.tap(find.byTooltip(_bugReportTooltip));
      await tester.pumpAndSettle();

      expect(find.text('Could not create the bug report.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(AppLogger.getLogs().map((entry) => entry.message),
          contains(startsWith('diagnostics.bundle.failed')));

      shareFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(shared, hasLength(2));
    });
  });
}
