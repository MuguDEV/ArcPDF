import 'dart:convert';
import 'dart:io';

/// A single-writer JSONL archive. All filesystem work is asynchronous.
class RotatingLogFile {
  RotatingLogFile(this.directory,
      {this.maxFileBytes = 256 * 1024, this.fileCount = 4})
      : assert(maxFileBytes > 0),
        assert(fileCount > 0);

  final Directory directory;
  final int maxFileBytes;
  final int fileCount;
  int _size = 0;

  File _file(int index) =>
      File('${directory.path}${Platform.pathSeparator}arcpdf.$index.jsonl');

  Future<void> initialize() async {
    await directory.create(recursive: true);
    final current = _file(0);
    _size = await current.exists() ? await current.length() : 0;
    if (_size > maxFileBytes) {
      // Do not retain an oversized/corrupt segment as an archive.
      await current.delete();
      _size = 0;
    } else if (_size > 0) {
      final bytes = await current.readAsBytes();
      if (bytes.last != 10) {
        // Recover a partial last write after abrupt process termination.
        _size = bytes.lastIndexOf(10) + 1;
        final handle = await current.open(mode: FileMode.append);
        try {
          await handle.truncate(_size);
        } finally {
          await handle.close();
        }
      }
    }
  }

  Future<void> append(Iterable<String> lines) async {
    final buffer = <int>[];
    Future<void> writeBuffer() async {
      if (buffer.isEmpty) return;
      await _file(0).writeAsBytes(buffer, mode: FileMode.append, flush: true);
      buffer.clear();
    }

    for (final line in lines) {
      final bytes = utf8.encode('$line\n');
      // An oversized diagnostic must never violate the archive size limit.
      if (bytes.length > maxFileBytes) continue;
      if (_size + bytes.length > maxFileBytes) {
        await writeBuffer();
        await _rotate();
      }
      buffer.addAll(bytes);
      _size += bytes.length;
    }
    await writeBuffer();
  }

  Future<void> _rotate() async {
    final oldest = _file(fileCount - 1);
    if (await oldest.exists()) await oldest.delete();
    for (var index = fileCount - 2; index >= 0; index--) {
      final source = _file(index);
      if (await source.exists()) await source.rename(_file(index + 1).path);
    }
    _size = 0;
  }

  Future<String> readAll() async {
    final output = StringBuffer();
    for (var index = fileCount - 1; index >= 0; index--) {
      final file = _file(index);
      if (await file.exists()) output.write(await file.readAsString());
    }
    return output.toString();
  }

  Future<void> clear() async {
    for (var index = 0; index < fileCount; index++) {
      final file = _file(index);
      if (await file.exists()) await file.delete();
    }
    _size = 0;
  }
}
