import 'dart:io';

import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class LocalPathProvider extends PathProviderPlatform {
  LocalPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;
}

void main() {
  late Directory directory;
  const scanner = PdfScannerService();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_scan_');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<File> write(String relative, String content) async {
    final file = File(p.join(directory.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  test('non-Android discovery does not call Android-only external storage APIs',
      () async {
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = LocalPathProvider(directory.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    final file = await write('discovered.pdf', '%PDF-1.7\nbody');
    final result = await scanner.scan();
    expect(result.files.map((item) => item.path), [file.path]);
  }, skip: Platform.isAndroid);

  test('scans nested PDFs once across duplicate and overlapping roots',
      () async {
    final a = await write('a.PDF', '%PDF-1.7\nbody');
    final b = await write(p.join('nested', 'b.pdf'), '%PDF-1.4\nbody');
    final result = await scanner.scanDirectories([
      directory.path,
      directory.path,
      p.join(directory.path, 'nested'),
      p.join(directory.path, 'nested', '..'),
    ]);
    expect(result.permissionStatus, StoragePermissionStatus.granted);
    expect(result.files.map((file) => p.normalize(file.path)),
        unorderedEquals([a.path, b.path]));
  });

  test(
      'ignores non-PDF content, empty files, other extensions and missing roots',
      () async {
    final valid = await write('valid.pdf', '%PDF-1.7\nbody');
    await write('empty.pdf', '');
    await write('short.pdf', '%PDF');
    await write('fake.pdf', 'this is not a PDF');
    await write('other.txt', '%PDF-1.7\nbody');
    final result = await scanner.scanDirectories([
      p.join(directory.path, 'missing'),
      directory.path,
    ]);
    expect(result.files.map((file) => file.path), [valid.path]);
  });

  test('detects encryption markers at either end and sorts newest first',
      () async {
    final old = await write('old.pdf', '%PDF-1.7\n/Encrypt 1 0 R');
    final recent =
        await write('recent.pdf', '%PDF-1.7\n${'x' * 9000}/Encrypt 2 0 R');
    final plain = await write('plain.pdf', '%PDF-1.7\nplain');
    await old.setLastModified(DateTime(2020));
    await plain.setLastModified(DateTime(2021));
    await recent.setLastModified(DateTime(2022));
    final result = await scanner.scanDirectories([directory.path]);
    expect(result.files.map((file) => file.name),
        ['recent.pdf', 'plain.pdf', 'old.pdf']);
    expect(result.files.map((file) => file.isEncrypted), [true, false, true]);
  });

  test('does not follow symlink files, directories or cycles', () async {
    await write('valid.pdf', '%PDF-1.7\nbody');
    final outside = await Directory.systemTemp.createTemp('arcpdf_outside_');
    addTearDown(() => outside.delete(recursive: true));
    final external = await File(p.join(outside.path, 'private.pdf'))
        .writeAsString('%PDF-1.7');
    await Link(p.join(directory.path, 'alias.pdf')).create(external.path);
    await Link(p.join(directory.path, 'external')).create(outside.path);
    await Link(p.join(directory.path, 'cycle')).create(directory.path);
    final result = await scanner.scanDirectories([directory.path]);
    expect(result.files.map((file) => file.name), ['valid.pdf']);
    final linkedRoot =
        await scanner.scanDirectories([p.join(directory.path, 'external')]);
    expect(linkedRoot.files, isEmpty);
  },
      skip: Platform.isWindows
          ? 'Windows symlink creation requires Developer Mode or elevation'
          : false);
}
