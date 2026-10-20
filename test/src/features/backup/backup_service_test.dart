import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/data/local_boxes.dart';
import 'package:arcpdf/src/features/backup/backup_service.dart';
import 'package:arcpdf/src/features/pdf/data/reading_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

const _a = '/docs/alpha-secret-title.pdf';
const _b = '/docs/beta.pdf';
const _c = '/docs/gamma.pdf';

void main() {
  late Directory directory;
  late Directory exports;
  late BackupBoxes boxes;
  late BackupService service;

  Future<BackupBoxes> openBoxes() async => BackupBoxes(
        favorites: await Hive.openBox<String>(LocalBoxes.favorites),
        tags: await Hive.openBox<List<String>>(LocalBoxes.tags),
        pages: await Hive.openBox<int>(BackupBoxes.pagesBoxName),
        zoom: await Hive.openBox<double>(BackupBoxes.zoomBoxName),
        readTime: await Hive.openBox<int>(BackupBoxes.timeBoxName),
        sessions: await Hive.openBox<dynamic>(LocalBoxes.sessions),
        settings: await Hive.openBox<dynamic>(LocalBoxes.settings),
      );

  BackupService makeService({String? vault}) => BackupService(
        boxes: boxes,
        vaultDirectory: vault,
        temporaryDirectory: () async => exports,
        appVersion: () async => '1.4.4',
        clock: () => DateTime.utc(2026, 10, 20, 12, 30, 5),
      );

  Map<String, Object> viewportMap(int page, double zoom) => {
        'version': 1,
        'page': page,
        'pageCount': 40,
        'zoom': zoom,
        'x': 0.4,
        'y': 0.7,
      };

  Future<void> seed() async {
    await boxes.favorites.putAll({_a: _a, _b: _b});
    await boxes.tags.put(_a, ['work', 'urgent']);
    await boxes.pages.put(_a, 12);
    await boxes.zoom.put(_a, 1.75);
    await boxes.readTime.put(_a, 600);
    await boxes.sessions.put('readingViewport:$_a', viewportMap(12, 1.75));
    await boxes.pages.put(_b, 3);
    await boxes.settings.putAll({'lockType': 1, 'requireLockOnResume': false});
  }

  Future<void> wipe() async {
    await boxes.favorites.clear();
    await boxes.tags.clear();
    await boxes.pages.clear();
    await boxes.zoom.clear();
    await boxes.readTime.clear();
    await boxes.sessions.clear();
    await boxes.settings.clear();
  }

  Map<String, dynamic> decode(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  Uint8List encodeJson(Object json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  /// Parses [bytes] and returns the failure kind (or null if accepted).
  BackupFailure? failureOf(Uint8List bytes) {
    try {
      BackupArchive.parse(bytes);
      return null;
    } on BackupException catch (e) {
      return e.failure;
    }
  }

  /// Valid-looking container around arbitrary [data].
  Uint8List withData(Map<String, Object?> data) => encodeJson({
        'format': 'arcpdf-backup',
        'schemaVersion': 1,
        'appVersion': '1.4.4',
        'createdAt': '2026-10-20T12:30:05.000Z',
        'checksum': 'sha256:${'0' * 64}',
        'data': data,
      });

  Map<String, Object?> validData() => {
        'favorites': [_a],
        'tags': {
          _a: ['x']
        },
        'progress': {
          _a: {'page': 2, 'zoom': 1.5}
        },
      };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_backup_test');
    exports = Directory(p.join(directory.path, 'exports'));
    Hive.init(directory.path);
    boxes = await openBoxes();
    service = makeService();
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  group('round trip', () {
    test('snapshot -> encode -> parse -> restore reproduces the data',
        () async {
      await seed();
      final before = await service.snapshot();
      final parsed = BackupArchive.parse(before.encode());
      expect(parsed.toJson(), before.toJson());

      await wipe();
      final result = await service.restore(parsed, mode: RestoreMode.replace);

      expect(result.favorites, 2);
      expect(result.taggedDocuments, 1);
      expect(result.progress, 2);
      expect((await service.snapshot()).toJson(), before.toJson());
      expect(boxes.favorites.get(_a), _a);
      expect(boxes.tags.get(_a), ['work', 'urgent']);
      // The reader accepts the restored checkpoint as-is.
      final viewport = ReadingProgressRepository().getLastViewport(_a);
      expect(viewport, isNotNull);
      expect(viewport!.page, 12);
      expect(viewport.pageCount, 40);
      expect(viewport.zoom, 1.75);
      expect(viewport.x, 0.4);
      expect(ReadingProgressRepository().getTotalReadTime(_a), 600);
      expect(ReadingProgressRepository().getLastReadPage(_b), 3);
      expect(ReadingProgressRepository().getLastZoom(_b), isNull);
    });

    test('header carries schema version, app version, date and checksum',
        () async {
      await seed();
      final json = decode((await service.snapshot()).encode());
      expect(json['format'], 'arcpdf-backup');
      expect(json['schemaVersion'], 1);
      expect(json['appVersion'], '1.4.4');
      expect(json['createdAt'], '2026-10-20T12:30:05.000Z');
      expect(json['checksum'], matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    });

    test('createExport writes a named file atomically and prunes old ones',
        () async {
      await seed();
      await exports.create(recursive: true);
      final stale = File(p.join(exports.path, 'arcpdf-backup-old.json'))
        ..writeAsStringSync('{}');
      final unrelated = File(p.join(exports.path, 'keep.txt'))
        ..writeAsStringSync('x');

      final export = await service.createExport();

      expect(export.fileName, 'arcpdf-backup-20261020-123005.json');
      expect(p.basename(export.file.path), export.fileName);
      expect(await export.file.readAsBytes(), export.bytes);
      expect(stale.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
      expect(exports.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
      final archive = await service.readFile(export.file.path);
      expect(archive.preview.favorites, 2);
      expect(export.preview.progress, 2);
    });

    test('invalid local values are omitted instead of exported', () async {
      await boxes.favorites.put('bad\u0000path', 'x');
      await boxes.favorites.put(_a, _a);
      await boxes.pages.put(_a, -4);
      await boxes.zoom.put(_a, double.nan);
      await boxes.zoom.put(_b, 2.0);
      await boxes.sessions.put('readingViewport:$_b', 'not a map');
      await boxes.sessions.put('activeIndex', 1);
      final archive = await service.snapshot();
      expect(archive.favorites, [_a]);
      expect(archive.progress.keys, [_b]);
      expect(archive.progress[_b]!.page, isNull);
      expect(archive.progress[_b]!.viewport, isNull);
    });
  });

  group('privacy', () {
    test('secrets, lock state, tabs and vault data never appear in a backup',
        () async {
      await seed();
      final vaultDir = p.join(directory.path, 'vault');
      final vaultFile = p.join(vaultDir, 'private-scan.pdf.enc');
      service = makeService(vault: vaultDir);
      await boxes.settings.putAll({
        'isLockEnabled': true,
        'isBiometricEnabled': true,
        'lock_secret': 'SECRETHASH123',
        'pin': '4821',
        'vault_key': 'KEYMATERIAL',
        'vault_iv': 'IVMATERIAL',
        'themeMode': 2,
      });
      await boxes.sessions.putAll({
        'paths': ['/open/tab-document.pdf'],
        'activeIndex': 0,
      });
      await boxes.favorites.put(vaultFile, vaultFile);
      await boxes.tags.put(vaultFile, ['hidden']);
      await boxes.pages.put(vaultFile, 9);
      await boxes.sessions
          .put('readingViewport:$vaultFile', viewportMap(9, 1.0));

      final text = utf8.decode((await service.snapshot()).encode());

      for (final forbidden in [
        'SECRETHASH123',
        '4821',
        'lock_secret',
        'KEYMATERIAL',
        'IVMATERIAL',
        'vault_key',
        'isLockEnabled',
        'isBiometricEnabled',
        'biometric',
        'tab-document',
        'activeIndex',
        'private-scan',
        'hidden',
        'themeMode',
        'thumbnail',
      ]) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(
          decode(Uint8List.fromList(utf8.encode(text)))['data'] as Map,
          containsPair('security', {
            'lockType': 'pattern',
            'requireLockOnResume': false,
          }));
    });

    test('logs contain counts only, never paths or titles', () async {
      await seed();
      final export = await service.createExport();
      final archive = await service.readFile(export.file.path);
      await service.restore(archive, mode: RestoreMode.merge);
      final output = AppLogger.getLogs()
          .where((e) => e.message.contains('backup.'))
          .map((e) => e.message)
          .join('\n');
      expect(output, contains('backup.exported'));
      expect(output, contains('backup.restored'));
      expect(output, isNot(contains('alpha-secret-title')));
      expect(output, isNot(contains('/docs')));
      expect(output, isNot(contains('urgent')));
    });
  });

  group('merge and replace', () {
    late BackupArchive archive;

    setUp(() async {
      await seed();
      archive = BackupArchive.parse((await service.snapshot()).encode());
      await wipe();
      // Local state differs from the backup.
      await boxes.favorites.put(_c, _c);
      await boxes.favorites.put(_a, _a);
      await boxes.tags.put(_a, ['local', 'work']);
      await boxes.tags.put(_c, ['only-local']);
      await boxes.pages.put(_a, 30); // newer local position
      await boxes.zoom.put(_a, 1.0);
      await boxes.readTime.put(_a, 5000); // larger than the backup's 600
      await boxes.pages.put(_c, 4);
      await boxes.sessions.put('readingViewport:$_c', viewportMap(4, 1.0));
    });

    test('merge unions favorites and tags and keeps local positions', () async {
      final result = await service.restore(archive, mode: RestoreMode.merge);

      expect(boxes.favorites.keys.toSet(), {_a, _b, _c});
      expect(boxes.tags.get(_a), ['local', 'work', 'urgent']);
      expect(boxes.tags.get(_c), ['only-local']);
      // Local position for A wins, wholly (page, zoom, no stale viewport).
      expect(boxes.pages.get(_a), 30);
      expect(boxes.zoom.get(_a), 1.0);
      expect(boxes.sessions.containsKey('readingViewport:$_a'), isFalse);
      // Missing local progress is filled from the backup.
      expect(boxes.pages.get(_b), 3);
      // Larger read time wins.
      expect(boxes.readTime.get(_a), 5000);
      // Untouched local data stays.
      expect(boxes.pages.get(_c), 4);
      expect(boxes.sessions.containsKey('readingViewport:$_c'), isTrue);
      expect(result.mode, RestoreMode.merge);
      expect(result.keptLocalProgress, 1);
      expect(result.progress, 1);
    });

    test('merge takes the backup read time when it is larger', () async {
      await boxes.readTime.put(_a, 10);
      await service.restore(archive, mode: RestoreMode.merge);
      expect(boxes.readTime.get(_a), 600);
    });

    test('restoring the same backup twice is idempotent', () async {
      await service.restore(archive, mode: RestoreMode.merge);
      final first = (await service.snapshot()).toJson();
      await service.restore(archive, mode: RestoreMode.merge);
      expect((await service.snapshot()).toJson(), first);
    });

    test('replace makes favorites, tags and progress match the backup',
        () async {
      final result = await service.restore(archive, mode: RestoreMode.replace);

      expect(boxes.favorites.keys.toSet(), {_a, _b});
      expect(boxes.tags.keys.toSet(), {_a});
      expect(boxes.tags.get(_a), ['work', 'urgent']);
      expect(boxes.pages.keys.toSet(), {_a, _b});
      expect(boxes.pages.get(_a), 12);
      expect(boxes.zoom.get(_a), 1.75);
      expect(boxes.zoom.containsKey(_b), isFalse);
      expect(boxes.readTime.get(_a), 600);
      expect(boxes.sessions.containsKey('readingViewport:$_c'), isFalse);
      expect(boxes.sessions.containsKey('readingViewport:$_a'), isTrue);
      expect(result.mode, RestoreMode.replace);
      expect(result.keptLocalProgress, 0);
    });

    test('replace leaves open tabs and unrelated session data alone', () async {
      await boxes.sessions.put('paths', ['/x.pdf']);
      await service.restore(archive, mode: RestoreMode.replace);
      expect(boxes.sessions.get('paths'), ['/x.pdf']);
    });

    test('paths are kept even when the PDF no longer exists', () async {
      expect(File(_b).existsSync(), isFalse);
      await service.restore(archive, mode: RestoreMode.merge);
      expect(boxes.favorites.containsKey(_b), isTrue);
    });

    test('a viewport whose storage key would exceed Hive limits is dropped',
        () async {
      final longPath = '/${'d' * 245}.pdf'; // valid path, key + prefix > 255
      expect(longPath.length, lessThanOrEqualTo(BackupLimits.maxPathLength));
      final archive = BackupArchive(
        schemaVersion: 1,
        appVersion: '1',
        createdAt: DateTime.utc(2026),
        favorites: const [],
        tags: const {},
        progress: {
          longPath: const BackupProgress(
            page: 2,
            zoom: 1.5,
            viewport: BackupViewport(
                page: 2, pageCount: 9, zoom: 1.5, x: 0.1, y: 0.2),
          ),
        },
      );
      await service.restore(archive, mode: RestoreMode.merge);
      expect(boxes.pages.get(longPath), 2);
      expect(boxes.sessions.keys.toList(), ['readingViewport:$_c']);
    });

    test('entries pointing into the vault are skipped', () async {
      final vaultDir = p.join(directory.path, 'vault');
      final inVault = p.join(vaultDir, 'x.pdf');
      service = makeService(vault: vaultDir);
      final hostile = BackupArchive(
        schemaVersion: 1,
        appVersion: '1',
        createdAt: DateTime.utc(2026),
        favorites: [inVault, _b],
        tags: {
          inVault: ['a']
        },
        progress: {inVault: const BackupProgress(page: 2)},
      );
      final result = await service.restore(hostile, mode: RestoreMode.merge);
      expect(boxes.favorites.containsKey(inVault), isFalse);
      expect(boxes.tags.containsKey(inVault), isFalse);
      expect(boxes.pages.containsKey(inVault), isFalse);
      expect(result.skipped, 3);
    });
  });

  group('security preferences', () {
    BackupArchive archiveWith({required int type, required bool resume}) =>
        BackupArchive(
          schemaVersion: 1,
          appVersion: '1',
          createdAt: DateTime.utc(2026),
          favorites: const [],
          tags: const {},
          progress: const {},
          security: BackupSecurity(lockType: type, requireLockOnResume: resume),
        );

    test('without a lock, preferences are applied', () async {
      final result = await service.restore(archiveWith(type: 1, resume: false),
          mode: RestoreMode.merge);
      expect(boxes.settings.get('lockType'), 1);
      expect(boxes.settings.get('requireLockOnResume'), false);
      expect(boxes.settings.containsKey('isLockEnabled'), isFalse);
      expect(result.securityApplied, isTrue);
    });

    test('an enabled lock is never changed, weakened or retyped', () async {
      await boxes.settings.putAll({
        'isLockEnabled': true,
        'isBiometricEnabled': false,
        'lockType': 0,
        'requireLockOnResume': true,
      });
      final result = await service.restore(archiveWith(type: 1, resume: false),
          mode: RestoreMode.replace);
      expect(boxes.settings.get('isLockEnabled'), true);
      expect(boxes.settings.get('isBiometricEnabled'), false);
      expect(boxes.settings.get('lockType'), 0);
      expect(boxes.settings.get('requireLockOnResume'), true);
      expect(result.securityApplied, isFalse);
    });

    test('an enabled lock may be made stricter', () async {
      await boxes.settings
          .putAll({'isLockEnabled': true, 'requireLockOnResume': false});
      await service.restore(archiveWith(type: 0, resume: true),
          mode: RestoreMode.merge);
      expect(boxes.settings.get('requireLockOnResume'), true);
    });

    test('a crafted file can never enable a lock or biometrics', () async {
      final json = decode(archiveWith(type: 0, resume: true).encode());
      final data = json['data'] as Map<String, dynamic>;
      (data['security'] as Map<String, dynamic>)
        ..['isLockEnabled'] = true
        ..['isBiometricEnabled'] = true
        ..['lock_secret'] = 'attacker';
      data['lock_secret'] = 'attacker';
      // Checksum covers the known schema only, so extras are inert.
      final archive = BackupArchive.parse(encodeJson(json));
      await service.restore(archive, mode: RestoreMode.replace);
      expect(boxes.settings.get('isLockEnabled'), isNull);
      expect(boxes.settings.get('isBiometricEnabled'), isNull);
      expect(boxes.settings.containsKey('lock_secret'), isFalse);
    });

    test('a backup without security preferences leaves settings alone',
        () async {
      await boxes.settings.put('lockType', 1);
      await service.restore(
          BackupArchive(
            schemaVersion: 1,
            appVersion: '1',
            createdAt: DateTime.utc(2026),
            favorites: const [],
            tags: const {},
            progress: const {},
          ),
          mode: RestoreMode.replace);
      expect(boxes.settings.get('lockType'), 1);
    });
  });

  group('validation', () {
    test('accepts a minimal valid structure up to the checksum', () {
      expect(failureOf(withData(validData())), BackupFailure.checksumMismatch);
    });

    test('garbage, truncated and non-UTF8 bytes are malformed', () async {
      await seed();
      final good = (await service.snapshot()).encode();
      expect(failureOf(Uint8List(0)), BackupFailure.malformed);
      expect(failureOf(Uint8List.fromList(utf8.encode('not json'))),
          BackupFailure.malformed);
      expect(failureOf(Uint8List.sublistView(good, 0, good.length ~/ 2)),
          BackupFailure.malformed);
      expect(failureOf(Uint8List.fromList([0xFF, 0xFE, 0xFD, 0x00])),
          BackupFailure.malformed);
      expect(failureOf(Uint8List.fromList(utf8.encode('[1,2,3]'))),
          BackupFailure.malformed);
      expect(failureOf(Uint8List.fromList(utf8.encode('"str"'))),
          BackupFailure.malformed);
    });

    test('a different JSON document is rejected', () {
      expect(failureOf(encodeJson({'format': 'something-else'})),
          BackupFailure.malformed);
      expect(failureOf(encodeJson({'a': 1})), BackupFailure.malformed);
    });

    test('a flipped value is caught by the checksum', () async {
      await seed();
      final json = decode((await service.snapshot()).encode());
      ((json['data'] as Map)['progress'] as Map)[_a]['readSeconds'] = 601;
      expect(failureOf(encodeJson(json)), BackupFailure.checksumMismatch);
    });

    test('a removed favorite is caught by the checksum', () async {
      await seed();
      final json = decode((await service.snapshot()).encode());
      ((json['data'] as Map)['favorites'] as List).removeLast();
      expect(failureOf(encodeJson(json)), BackupFailure.checksumMismatch);
    });

    test('a UTF-8 BOM is tolerated', () async {
      await seed();
      final good = (await service.snapshot()).encode();
      expect(
          failureOf(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...good])), isNull);
    });

    test('newer or invalid schema versions are rejected', () async {
      await seed();
      final json = decode((await service.snapshot()).encode());
      expect(failureOf(encodeJson({...json, 'schemaVersion': 2})),
          BackupFailure.unsupportedVersion);
      expect(failureOf(encodeJson({...json, 'schemaVersion': 9999})),
          BackupFailure.unsupportedVersion);
      for (final version in [0, -1, '1', 1.5, null]) {
        expect(failureOf(encodeJson({...json, 'schemaVersion': version})),
            BackupFailure.malformed,
            reason: '$version');
      }
    });

    test('bad header fields are rejected', () async {
      await seed();
      final json = decode((await service.snapshot()).encode());
      for (final override in <Map<String, Object?>>[
        {'appVersion': 5},
        {'appVersion': ''},
        {'appVersion': 'x' * 65},
        {'createdAt': 'yesterday'},
        {'createdAt': 3},
        {'checksum': 'md5:abc'},
        {'checksum': 'sha256:${'G' * 64}'},
        {'checksum': null},
        {'data': <Object?>[]},
        {'data': 'x'},
      ]) {
        expect(failureOf(encodeJson({...json, ...override})),
            BackupFailure.malformed,
            reason: '$override');
      }
    });

    test('oversized input is rejected before parsing', () {
      expect(failureOf(Uint8List(BackupLimits.maxFileBytes + 1)),
          BackupFailure.tooLarge);
    });

    test('readFile bounds file size and rejects non-files', () async {
      final big = File(p.join(directory.path, 'big.json'));
      await big.writeAsBytes(Uint8List(BackupLimits.maxFileBytes + 1));
      await expectLater(
          service.readFile(big.path),
          throwsA(isA<BackupException>()
              .having((e) => e.failure, 'failure', BackupFailure.tooLarge)));
      await expectLater(
          service.readFile(p.join(directory.path, 'missing.json')),
          throwsA(isA<BackupException>()
              .having((e) => e.failure, 'failure', BackupFailure.unreadable)));
      await expectLater(
          service.readFile(directory.path),
          throwsA(isA<BackupException>()
              .having((e) => e.failure, 'failure', BackupFailure.unreadable)));
    });

    test('hostile types and values are rejected with invalidData', () {
      final cases = <String, Map<String, Object?>>{
        'favorites not a list': {...validData(), 'favorites': 'x'},
        'favorite not a string': {
          ...validData(),
          'favorites': [1]
        },
        'empty path': {
          ...validData(),
          'favorites': ['']
        },
        'control char in path': {
          ...validData(),
          'favorites': ['/a\nb.pdf']
        },
        'path too long': {
          ...validData(),
          'favorites': ['/${'a' * BackupLimits.maxPathLength}']
        },
        'too many favorites': {
          ...validData(),
          'favorites': List.generate(BackupLimits.maxEntries + 1, (i) => '/$i')
        },
        'tags not a map': {...validData(), 'tags': []},
        'tag list not a list': {
          ...validData(),
          'tags': {_a: 'x'}
        },
        'tag not a string': {
          ...validData(),
          'tags': {
            _a: [1]
          }
        },
        'blank tag': {
          ...validData(),
          'tags': {
            _a: ['  ']
          }
        },
        'tag too long': {
          ...validData(),
          'tags': {
            _a: ['t' * (BackupLimits.maxTagLength + 1)]
          }
        },
        'too many tags': {
          ...validData(),
          'tags': {
            _a: List.generate(BackupLimits.maxTagsPerDocument + 1, (i) => '$i')
          }
        },
        'progress not a map': {...validData(), 'progress': 3},
        'progress entry not a map': {
          ...validData(),
          'progress': {_a: 3}
        },
        'empty progress entry': {
          ...validData(),
          'progress': {_a: <String, Object?>{}}
        },
        'page as string': {
          ...validData(),
          'progress': {
            _a: {'page': '2'}
          }
        },
        'page as double': {
          ...validData(),
          'progress': {
            _a: {'page': 2.5}
          }
        },
        'page zero': {
          ...validData(),
          'progress': {
            _a: {'page': 0}
          }
        },
        'page negative': {
          ...validData(),
          'progress': {
            _a: {'page': -1}
          }
        },
        'page huge': {
          ...validData(),
          'progress': {
            _a: {'page': BackupLimits.maxPage + 1}
          }
        },
        'zoom zero': {
          ...validData(),
          'progress': {
            _a: {'zoom': 0}
          }
        },
        'zoom string': {
          ...validData(),
          'progress': {
            _a: {'zoom': 'big'}
          }
        },
        'zoom huge': {
          ...validData(),
          'progress': {
            _a: {'zoom': 1e9}
          }
        },
        'negative read time': {
          ...validData(),
          'progress': {
            _a: {'readSeconds': -1}
          }
        },
        'huge read time': {
          ...validData(),
          'progress': {
            _a: {'readSeconds': BackupLimits.maxReadSeconds + 1}
          }
        },
        'viewport without page/zoom': {
          ...validData(),
          'progress': {
            _a: {'readSeconds': 3, 'viewport': viewportMap(2, 1.5)}
          }
        },
        'viewport page mismatch': {
          ...validData(),
          'progress': {
            _a: {'page': 3, 'zoom': 1.5, 'viewport': viewportMap(2, 1.5)}
          }
        },
        'viewport zoom mismatch': {
          ...validData(),
          'progress': {
            _a: {'page': 2, 'zoom': 2.0, 'viewport': viewportMap(2, 1.5)}
          }
        },
        'viewport pageCount below page': {
          ...validData(),
          'progress': {
            _a: {
              'page': 2,
              'zoom': 1.5,
              'viewport': {...viewportMap(2, 1.5), 'pageCount': 1}
            }
          }
        },
        'viewport offset string': {
          ...validData(),
          'progress': {
            _a: {
              'page': 2,
              'zoom': 1.5,
              'viewport': {...viewportMap(2, 1.5), 'x': 'left'}
            }
          }
        },
        'security wrong type': {...validData(), 'security': 'on'},
        'security bad lock type': {
          ...validData(),
          'security': {'lockType': 'face', 'requireLockOnResume': true}
        },
        'security bad flag': {
          ...validData(),
          'security': {'lockType': 'pin', 'requireLockOnResume': 'yes'}
        },
      };
      for (final entry in cases.entries) {
        expect(failureOf(withData(entry.value)), BackupFailure.invalidData,
            reason: entry.key);
      }
    });

    test('non-finite numbers from overflowing JSON are rejected', () {
      final text = '{"format":"arcpdf-backup","schemaVersion":1,'
          '"appVersion":"1","createdAt":"2026-01-01T00:00:00Z",'
          '"checksum":"sha256:${'0' * 64}","data":{"favorites":[],"tags":{},'
          '"progress":{"/a.pdf":{"page":1,"zoom":1e999}}}}';
      expect(failureOf(Uint8List.fromList(utf8.encode(text))),
          BackupFailure.invalidData);
    });

    test('deeply nested input does not crash', () {
      final deep = '${'[' * 20000}${']' * 20000}';
      expect(failureOf(Uint8List.fromList(utf8.encode(deep))),
          BackupFailure.malformed);
    });

    test('a rejected file never modifies any box', () async {
      await seed();
      final before = (await service.snapshot()).toJson();
      await expectLater(
          service.parseBytes(withData({...validData(), 'favorites': 3})),
          throwsA(isA<BackupException>()));
      expect((await service.snapshot()).toJson(), before);
    });
  });

  group('atomicity', () {
    late BackupArchive archive;
    late Map<String, dynamic> before;

    setUp(() async {
      await seed();
      archive = BackupArchive.parse((await service.snapshot()).encode());
      await wipe();
      await boxes.favorites.put(_c, _c);
      await boxes.tags.put(_c, ['keep']);
      await boxes.pages.put(_c, 8);
      await boxes.readTime.put(_c, 77);
      await boxes.settings.put('lockType', 0);
      before = (await service.snapshot()).toJson();
    });

    for (final failing in ['tags', 'pages', 'time', 'viewports', 'security']) {
      test('failure while applying "$failing" rolls everything back', () async {
        final failingService = BackupService(
          boxes: boxes,
          appVersion: () async => '1.4.4',
          clock: () => DateTime.utc(2026, 10, 20, 12, 30, 5),
          debugBeforeApply: (stage) async {
            if (stage == failing) throw StateError('disk full');
          },
        );
        await expectLater(
            failingService.restore(archive, mode: RestoreMode.replace),
            throwsA(isA<BackupException>().having(
                (e) => e.failure, 'failure', BackupFailure.applyFailed)));
        expect((await failingService.snapshot()).toJson(), before);
        expect(boxes.favorites.keys.toSet(), {_c});
        expect(boxes.sessions.keys, isEmpty);
        expect(boxes.settings.get('lockType'), 0);
      });
    }

    test('a failure while staging writes nothing', () async {
      await boxes.readTime.close();
      await expectLater(
          service.restore(archive, mode: RestoreMode.replace),
          throwsA(isA<BackupException>()
              .having((e) => e.failure, 'failure', BackupFailure.applyFailed)));
      expect(boxes.favorites.keys.toSet(), {_c});
      expect(boxes.pages.keys.toSet(), {_c});
    });

    test('a real write failure mid-apply is rolled back too', () async {
      // Closing the sessions box after staging cannot happen through the
      // public API, so emulate it from the hook: favorites/tags/pages are
      // already written when it throws.
      final failingService = BackupService(
        boxes: boxes,
        debugBeforeApply: (stage) async {
          if (stage == 'viewports') await boxes.sessions.close();
        },
      );
      await expectLater(
          failingService.restore(archive, mode: RestoreMode.replace),
          throwsA(isA<BackupException>()));
      expect(boxes.favorites.keys.toSet(), {_c});
      expect(boxes.tags.keys.toSet(), {_c});
      expect(boxes.pages.keys.toSet(), {_c});
      expect(boxes.zoom.keys, isEmpty);
      expect(boxes.readTime.get(_c), 77);
    });

    test('concurrent restores are serialized', () async {
      final order = <String>[];
      final slow = BackupService(
        boxes: boxes,
        debugBeforeApply: (stage) async {
          if (stage == 'favorites') {
            order.add('start');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            order.add('end');
          }
        },
      );
      await Future.wait([
        slow.restore(archive, mode: RestoreMode.merge),
        slow.restore(archive, mode: RestoreMode.replace),
      ]);
      // Never interleaved: each restore finishes before the next begins.
      expect(order, ['start', 'end', 'start', 'end']);
    });
  });
}
