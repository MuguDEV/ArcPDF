import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arcpdf/src/features/updater/updater_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('Mocked network error');
  }
}

class TrackingClient extends http.BaseClient {
  TrackingClient(this.inner);
  final http.Client inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

Map<String, dynamic> releaseJson(String version) => {
      'tag_name': version,
      'html_url': 'https://github.com/MuguDEV/ArcPDF/releases/tag/$version',
      'body': 'Changes',
      'assets': [
        {
          'name': 'ArcPDF-universal.apk',
          'browser_download_url':
              'https://github.com/MuguDEV/ArcPDF/releases/download/$version/app.apk',
          'size': 6
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'ArcPDF',
        packageName: 'com.arcpdf',
        version: '1.4.4',
        buildNumber: '1',
        buildSignature: '');
  });
  tearDown(() => HttpOverrides.global = null);

  group('Update checks', () {
    test('legacy checkForUpdates still returns null on network setup error',
        () async {
      HttpOverrides.global = MyHttpOverrides();
      expect(await UpdaterService.checkForUpdates(), isNull);
    });

    final comparisons = <(String, String, UpdateCheckStatus)>[
      ('1.4.5', '1.4.4', UpdateCheckStatus.updateAvailable),
      ('v1.4.5', 'V1.4.4', UpdateCheckStatus.updateAvailable),
      ('  v2.0.0  ', '1.4.4', UpdateCheckStatus.updateAvailable),
      ('1.4.3', '1.4.4', UpdateCheckStatus.upToDate),
      ('1.4.4', '1.4.4', UpdateCheckStatus.upToDate),
      ('1.4', '1.4.0', UpdateCheckStatus.upToDate),
      ('1.4.0', '1.4', UpdateCheckStatus.upToDate),
      ('2', '1.99.99', UpdateCheckStatus.updateAvailable),
      ('1.4.4+99', '1.4.4+1', UpdateCheckStatus.upToDate),
      ('1.4.4-beta.1', '1.4.4', UpdateCheckStatus.upToDate),
      ('1.4.4', '1.4.4-rc.2', UpdateCheckStatus.updateAvailable),
      ('1.4.4-beta.2', '1.4.4-beta.10', UpdateCheckStatus.upToDate),
      ('1.4.4-beta.10', '1.4.4-beta.2', UpdateCheckStatus.updateAvailable),
      ('1.4.4-1', '1.4.4-alpha', UpdateCheckStatus.upToDate),
      ('1.4.4-alpha.1', '1.4.4-alpha', UpdateCheckStatus.updateAvailable),
      ('1.4.4-rc', '1.4.4-beta', UpdateCheckStatus.updateAvailable),
      ('1.4.4--1', '1.4.4-1', UpdateCheckStatus.updateAvailable),
      ('1.4.3+new', '1.4.4+old', UpdateCheckStatus.upToDate),
      ('1.4.3-rc.9', '1.4.4-alpha.1', UpdateCheckStatus.upToDate),
      ('release-9.0.0', '1.4.4', UpdateCheckStatus.failure),
      ('1.4.5.0', '1.4.4', UpdateCheckStatus.failure),
      ('1.04.5', '1.4.4', UpdateCheckStatus.failure),
      ('1.4.5-01', '1.4.4', UpdateCheckStatus.failure),
      ('1.4.5-', '1.4.4', UpdateCheckStatus.failure),
      ('v', '1.4.4', UpdateCheckStatus.failure),
      ('1.4.5', 'unknown', UpdateCheckStatus.failure),
    ];
    for (final (latest, current, expected) in comparisons) {
      test('$latest versus $current is ${expected.name}', () async {
        final client = MockClient(
            (_) async => http.Response(jsonEncode(releaseJson(latest)), 200));
        addTearDown(client.close);
        final result = await UpdaterService.checkForUpdateResult(
            client: client, currentVersion: current);
        expect(result.status, expected);
        expect(result.release?.version,
            expected == UpdateCheckStatus.updateAvailable ? latest : null);
      });
    }

    test('uses the installed package version and retains advertised assets',
        () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode(releaseJson('v1.5.0')), 200));
      addTearDown(client.close);
      final release = await UpdaterService.checkForUpdates(client: client);
      expect(release?.version, 'v1.5.0');
      expect(release?.assets.single.name, 'ArcPDF-universal.apk');
    });

    for (final status in [204, 301, 403, 404, 429, 500]) {
      test('HTTP $status is unavailable, not up to date', () async {
        final client = MockClient((_) async => http.Response('', status));
        addTearDown(client.close);
        final result =
            await UpdaterService.checkForUpdateResult(client: client);
        expect(result.status, UpdateCheckStatus.unavailable);
      });
    }

    for (final body in [
      'invalid JSON',
      'null',
      '[]',
      '{}',
      jsonEncode({...releaseJson('1.5.0'), 'assets': 'invalid'}),
      jsonEncode({...releaseJson('1.5.0'), 'html_url': 'javascript:alert(1)'}),
    ]) {
      test('invalid release data reports failure: $body', () async {
        final client = MockClient((_) async => http.Response(body, 200));
        addTearDown(client.close);
        expect(
            (await UpdaterService.checkForUpdateResult(client: client)).status,
            UpdateCheckStatus.failure);
        expect(await UpdaterService.checkForUpdates(client: client), isNull);
      });
    }

    test('network errors and timeouts report unavailable', () async {
      for (final error in [
        const SocketException('Offline'),
        http.ClientException('Offline')
      ]) {
        final client = MockClient((_) async => throw error);
        addTearDown(client.close);
        expect(
            (await UpdaterService.checkForUpdateResult(client: client)).status,
            UpdateCheckStatus.unavailable);
      }
      final client = MockClient((_) => Completer<http.Response>().future);
      addTearDown(client.close);
      final result = await UpdaterService.checkForUpdateResult(
          client: client, timeout: const Duration(milliseconds: 10));
      expect(result.status, UpdateCheckStatus.unavailable);
    });
  });

  group('APK download', () {
    late Directory directory;
    final apkBytes = [0x50, 0x4b, 0x03, 0x04, 1, 2];
    GitHubRelease release(List<GitHubReleaseAsset> assets) => GitHubRelease(
        version: 'v1.5.0',
        body: '',
        url: 'https://github.com/MuguDEV/ArcPDF',
        assets: assets);
    GitHubReleaseAsset asset(String name, {String? url, int? size = 6}) =>
        GitHubReleaseAsset(
            name: name, size: size, url: url ?? 'https://github.com/$name');

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('arcpdf_updater_');
    });
    tearDown(() => directory.delete(recursive: true));

    test(
        'selects universal APK from the advertised release without refetching latest',
        () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(apkBytes, 200);
      });
      addTearDown(client.close);
      final selected = release([
        asset('arm64.apk'),
        asset('ArcPDF-universal.APK'),
        asset('x86.apk')
      ]);
      final file = await UpdaterService.downloadUpdate(selected,
          client: client, directory: directory);
      expect(requests, [Uri.parse('https://github.com/ArcPDF-universal.APK')]);
      expect(await file.readAsBytes(), apkBytes);
      expect(file.path, endsWith('ArcPDF_Update.apk'));
      expect(await file.parent.list().length, 1);
    });

    test('uses distinct staging paths for repeated downloads', () async {
      final client =
          MockClient((_) async => http.Response.bytes(apkBytes, 200));
      addTearDown(client.close);
      final selected = release([asset('app.apk')]);
      final first = await UpdaterService.downloadUpdate(selected,
          client: client, directory: directory);
      final second = await UpdaterService.downloadUpdate(selected,
          client: client, directory: directory);
      expect(first.path, isNot(second.path));
      expect(await first.readAsBytes(), apkBytes);
      expect(await second.readAsBytes(), apkBytes);
    });

    for (final status in [403, 404, 500]) {
      test('HTTP $status never becomes an APK file', () async {
        final client =
            MockClient((_) async => http.Response.bytes(apkBytes, status));
        addTearDown(client.close);
        await expectLater(
            UpdaterService.downloadUpdate(release([asset('app.apk')]),
                client: client, directory: directory),
            throwsA(isA<HttpException>()));
        expect(await directory.list().toList(), isEmpty);
      });
    }

    test('rejects empty, HTML and truncated downloads without leaving files',
        () async {
      for (final bytes in [
        <int>[],
        utf8.encode('<html>Error</html>'),
        apkBytes.sublist(0, 5)
      ]) {
        final client = MockClient((_) async => http.Response.bytes(bytes, 200));
        addTearDown(client.close);
        await expectLater(
            UpdaterService.downloadUpdate(release([asset('app.apk')]),
                client: client, directory: directory),
            throwsFormatException);
        expect(await directory.list().toList(), isEmpty);
      }
    });

    test(
        'download timeout does not write a file even if response arrives later',
        () async {
      final response = Completer<http.Response>();
      final client = MockClient((_) => response.future);
      addTearDown(client.close);
      await expectLater(
          UpdaterService.downloadUpdate(release([asset('app.apk')]),
              client: client,
              directory: directory,
              timeout: const Duration(milliseconds: 10)),
          throwsA(isA<TimeoutException>()));
      response.complete(http.Response.bytes(apkBytes, 200));
      await Future<void>.delayed(Duration.zero);
      expect(await directory.list().toList(), isEmpty);
    });

    test('rejects non-HTTPS assets and missing APKs before requesting',
        () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response.bytes(apkBytes, 200);
      });
      addTearDown(client.close);
      for (final assets in [
        <GitHubReleaseAsset>[],
        [asset('app.txt')],
        [asset('app.apk', url: 'http://example.com/app.apk')],
        [asset('app.apk', url: 'file:///tmp/app.apk')],
      ]) {
        await expectLater(
            UpdaterService.downloadUpdate(release(assets),
                client: client, directory: directory),
            throwsFormatException);
      }
      expect(requests, 0);
      expect(await directory.list().toList(), isEmpty);
    });

    test('injected clients remain owned by the caller', () async {
      final client = TrackingClient(
          MockClient((_) async => http.Response.bytes(apkBytes, 200)));
      addTearDown(client.close);
      await UpdaterService.downloadUpdate(release([asset('app.apk')]),
          client: client, directory: directory);
      expect(client.closed, isFalse);
      await UpdaterService.checkForUpdateResult(client: client);
      expect(client.closed, isFalse);
    });
  });
}
