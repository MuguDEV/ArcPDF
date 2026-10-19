import 'dart:async';
import 'dart:convert';

import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/settings/settings_screen.dart';
import 'package:arcpdf/src/features/updater/updater_service.dart';
import 'package:arcpdf/src/shared/widgets/arc_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockBox extends Mock implements Box {}

void main() {
  late MockBox box;
  late GlobalKey<NavigatorState> navigator;
  late ValueNotifier<bool> showSettings;

  http.Response release(String version) => http.Response(
      jsonEncode({
        'tag_name': version,
        'html_url': 'https://github.com/MuguDEV/ArcPDF/releases/tag/$version',
        'body': 'Release changes',
      }),
      200);

  setUp(() {
    box = MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((invocation) => invocation.namedArguments[#defaultValue]);
    navigator = GlobalKey<NavigatorState>();
    showSettings = ValueNotifier(true);
    PackageInfo.setMockInitialValues(
        appName: 'ArcPDF',
        packageName: 'com.arcpdf',
        version: '1.4.4',
        buildNumber: '1',
        buildSignature: '');
  });

  tearDown(() => showSettings.dispose());

  Future<void> mount(WidgetTester tester, http.Client client) async {
    addTearDown(client.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsControllerProvider
            .overrideWith((ref) => SettingsController(box)),
        securityControllerProvider
            .overrideWith((ref) => SecurityController(box)),
        updaterHttpClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
            body: ValueListenableBuilder<bool>(
          valueListenable: showSettings,
          builder: (_, visible, __) => visible
              ? const SettingsScreen()
              : const Center(child: Text('Replacement page')),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Check for Updates'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<void> tapCheck(WidgetTester tester) async {
    await tester.tap(find.text('Check for Updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('only a successful current-version check says latest',
      (tester) async {
    await mount(tester, MockClient((_) async => release('1.4.4')));
    await tapCheck(tester);
    await tester.pumpAndSettle();
    expect(find.text('You are on the latest version!'), findsOneWidget);
    expect(find.byType(ArcProgressIndicator), findsNothing);
  });

  testWidgets('offline or unavailable check does not say latest',
      (tester) async {
    await mount(
        tester, MockClient((_) async => throw http.ClientException('Offline')));
    await tapCheck(tester);
    await tester.pumpAndSettle();
    expect(find.text('You are on the latest version!'), findsNothing);
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.byType(ArcProgressIndicator), findsNothing);
  });

  testWidgets('malformed release data reports failure instead of latest',
      (tester) async {
    await mount(tester, MockClient((_) async => http.Response('invalid', 200)));
    await tapCheck(tester);
    await tester.pumpAndSettle();
    expect(find.text('You are on the latest version!'), findsNothing);
    expect(find.textContaining('Could not read update information'),
        findsOneWidget);
  });

  testWidgets('a newer release opens its existing release dialog',
      (tester) async {
    await mount(tester, MockClient((_) async => release('v1.5.0')));
    await tapCheck(tester);
    await tester.pumpAndSettle();
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('v1.5.0'), findsOneWidget);
    expect(find.text('Release changes'), findsOneWidget);
    expect(find.byType(ArcProgressIndicator), findsNothing);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets(
      'failed browser launch leaves the release dialog available for retry',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await mount(tester, MockClient((_) async => release('v1.5.0')));
    await tapCheck(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.textContaining('Could not open the download page'),
        findsOneWidget);
  });

  testWidgets(
      'browser launch completion removes its dialog rather than a newer route',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = Completer<bool>();
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (_) {
      calls++;
      return launched.future;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await mount(tester, MockClient((_) async => release('v1.5.0')));
    await tapCheck(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(calls, 1);
    unawaited(navigator.currentState!.push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Other page')),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    launched.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Other page'), findsOneWidget);
    expect(find.text('Update Available', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'back cannot dismiss loading and repeat callbacks cannot start another check',
      (tester) async {
    final response = Completer<http.Response>();
    var requests = 0;
    await mount(tester, MockClient((_) {
      requests++;
      return response.future;
    }));
    final tile = tester.widget<ListTile>(find.ancestor(
        of: find.text('Check for Updates'), matching: find.byType(ListTile)));
    tile.onTap!();
    tile.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ArcProgressIndicator), findsOneWidget);
    expect(requests, 1);
    response.complete(release('1.4.4'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(ArcProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion removes only its own loader, never a newer route',
      (tester) async {
    final response = Completer<http.Response>();
    await mount(tester, MockClient((_) => response.future));
    await tapCheck(tester);
    unawaited(navigator.currentState!.push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Other page')),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    response.complete(release('1.4.4'));
    await tester.pumpAndSettle();
    expect(find.text('Other page'), findsOneWidget);
    expect(
        find.byType(ArcProgressIndicator, skipOffstage: false), findsNothing);
    expect(find.text('You are on the latest version!'), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('externally dismissed loader does not pop settings on completion',
      (tester) async {
    final response = Completer<http.Response>();
    await mount(tester, MockClient((_) => response.future));
    await tapCheck(tester);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    response.complete(release('1.4.4'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('You are on the latest version!'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing settings removes its loader and ignores a late result',
      (tester) async {
    final response = Completer<http.Response>();
    await mount(tester, MockClient((_) => response.future));
    await tapCheck(tester);
    showSettings.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ArcProgressIndicator), findsNothing);
    response.complete(release('v1.5.0'));
    await tester.pumpAndSettle();
    expect(find.text('Replacement page'), findsOneWidget);
    expect(find.text('Update Available'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
