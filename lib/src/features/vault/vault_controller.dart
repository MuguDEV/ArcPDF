import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import '../pdf/domain/pdf_file_item.dart';
import '../pdf/application/pdf_library_controller.dart';
import 'dart:convert';
import 'vault_init_exception.dart';

class VaultState {
  final bool isUnlocked;
  final List<PdfFileItem> vaultFiles;
  final bool isLoading;
  final bool hasError;

  const VaultState({
    this.isUnlocked = false,
    this.vaultFiles = const [],
    this.isLoading = false,
    this.hasError = false,
  });

  VaultState copyWith(
      {bool? isUnlocked,
      List<PdfFileItem>? vaultFiles,
      bool? isLoading,
      bool? hasError}) {
    return VaultState(
      isUnlocked: isUnlocked ?? this.isUnlocked,
      vaultFiles: vaultFiles ?? this.vaultFiles,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
    );
  }
}

class _VaultKey {
  final enc.Encrypter encrypter;
  final enc.IV iv;
  _VaultKey(this.encrypter, this.iv);
}

class VaultController extends StateNotifier<VaultState> {
  VaultController(this._ref) : super(const VaultState());

  final Ref _ref;
  final _storage = const FlutterSecureStorage();

  Future<void>? _initFuture;
  _VaultKey? _vaultKey;
  Directory? _vaultDir;
  Future<void> _operationTail = Future.value();
  int _session = 0;

  // Initialize on demand so failures always have an awaiting caller.
  Future<void> get ready => _initFuture ??= _initVault();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  bool _hasSession(int session) =>
      mounted && state.isUnlocked && _session == session;

  Future<bool> _isVaultFile(File file) async {
    final vaultDir = _vaultDir;
    return vaultDir != null &&
        p.equals(p.dirname(p.absolute(file.path)), p.absolute(vaultDir.path)) &&
        await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.file;
  }

  Future<File> _availableFile(Directory directory, String name) async {
    var file = File(p.join(directory.path, name));
    var counter = 1;
    while (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      file = File(p.join(directory.path,
          '${p.basenameWithoutExtension(name)}_${counter++}${p.extension(name)}'));
    }
    return file;
  }

  Future<_VaultKey> get _readyKey async {
    await ready;
    final k = _vaultKey;
    if (k == null) {
      throw const VaultInitException('Vault key is null after initialization');
    }
    return k;
  }

  Future<void> _initVault() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(appDir.path, 'vault'));
      final hasExistingData = await vaultDir.exists() &&
          !await vaultDir.list(followLinks: false).isEmpty;
      final keyStr = await _storage.read(key: 'vault_key');
      final ivStr = await _storage.read(key: 'vault_iv');

      // Missing credentials are only recoverable for an empty vault. Never
      // replace material needed to decrypt an existing document.
      if (hasExistingData && (keyStr == null || ivStr == null)) {
        throw const VaultInitException(
            'Vault key or IV is missing for existing encrypted data');
      }
      final storedKey = keyStr == null ? null : base64Decode(keyStr);
      final storedIv = ivStr == null ? null : base64Decode(ivStr);
      if (storedKey != null && storedKey.length != 32) {
        throw VaultInitException('Invalid key length: ${storedKey.length}');
      }
      if (storedIv != null && storedIv.length != 16) {
        throw VaultInitException('Invalid IV length: ${storedIv.length}');
      }

      // Validate both stored values before writing either missing value.
      final keyBytes = storedKey ?? enc.Key.fromSecureRandom(32).bytes;
      final ivBytes = storedIv ?? enc.IV.fromSecureRandom(16).bytes;
      if (keyStr == null) {
        await _storage.write(key: 'vault_key', value: base64Encode(keyBytes));
      }
      if (ivStr == null) {
        await _storage.write(key: 'vault_iv', value: base64Encode(ivBytes));
      }
      await vaultDir.create(recursive: true);
      _vaultKey = _VaultKey(
          enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc)),
          enc.IV(ivBytes));
      _vaultDir = vaultDir;
    } catch (e) {
      _vaultKey = null;
      _vaultDir = null;
      _initFuture = null;
      throw VaultInitException('Failed to initialize secure vault: $e');
    }
  }

  Future<void> loadVaultFiles() async {
    final session = _session;
    if (!_hasSession(session)) return;
    state = state.copyWith(isLoading: true, hasError: false);
    try {
      await ready;
      if (!_hasSession(session)) return;
      final files = _vaultDir!.listSync(followLinks: false).whereType<File>();
      final items =
          files.map((f) => PdfFileItem.fromFile(f, isEncrypted: true)).toList();
      state = state.copyWith(vaultFiles: items, isLoading: false);
    } catch (_) {
      if (_hasSession(session)) {
        state =
            state.copyWith(vaultFiles: [], isLoading: false, hasError: true);
      }
    }
  }

  void setUnlocked(bool unlocked) {
    if (!mounted) return;
    _session++;
    state = state.copyWith(
        isUnlocked: unlocked,
        vaultFiles: [],
        isLoading: false,
        hasError: false);
    if (unlocked) loadVaultFiles();
  }

  Future<bool> moveToVault(PdfFileItem item) =>
      _serialize(() => _moveToVault(item));

  Future<bool> _moveToVault(PdfFileItem item) async {
    try {
      final key = await _readyKey;
      final file = File(item.path);
      if (!await file.exists()) return false;

      final vaultDir = _vaultDir;
      if (vaultDir == null ||
          p.isWithin(p.absolute(vaultDir.path), p.absolute(file.path))) {
        return false;
      }
      final newFile = await _availableFile(vaultDir, p.basename(file.path));

      final bytes = await file.readAsBytes();
      final encrypted = key.encrypter.encryptBytes(bytes, iv: key.iv);
      final encryptedBytes = encrypted.bytes;

      await newFile.writeAsBytes(encryptedBytes, flush: true);

      if (await newFile.exists() &&
          (await newFile.length()) == encryptedBytes.length) {
        await file.delete();
      } else {
        return false;
      }

      // Ignore errors updating the ref since we might not be within a widget tree in test
      try {
        _ref.read(pdfLibraryControllerProvider.notifier).refresh();
      } catch (_) {}
      await loadVaultFiles();
      return true;
    } catch (e) {
      if (e is VaultInitException) rethrow;
      return false;
    }
  }

  Future<File?> decryptToTempFile(PdfFileItem vaultItem) async {
    final session = _session;
    if (!_hasSession(session)) return null;
    Directory? previewDir;
    try {
      final key = await _readyKey;
      final vaultFile = File(vaultItem.path);
      if (!await _isVaultFile(vaultFile) || !_hasSession(session)) return null;

      final encryptedBytes = await vaultFile.readAsBytes();
      final decryptedBytes =
          key.encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: key.iv);

      final tempDir = await getTemporaryDirectory();
      if (!_hasSession(session)) return null;
      previewDir = await tempDir.createTemp('arcpdf_vault_');
      final tempFile =
          File(p.join(previewDir.path, p.basename(vaultFile.path)));
      await tempFile.writeAsBytes(decryptedBytes, flush: true);
      if (!_hasSession(session)) {
        await previewDir.delete(recursive: true);
        return null;
      }
      return tempFile;
    } catch (e) {
      if (previewDir != null && await previewDir.exists()) {
        await previewDir.delete(recursive: true);
      }
      if (e is VaultInitException) rethrow;
      return null;
    }
  }

  Future<bool> restoreFromVault(PdfFileItem vaultItem, String restoreDirPath) {
    final session = _session;
    if (!_hasSession(session)) return Future.value(false);
    return _serialize(
        () => _restoreFromVault(vaultItem, restoreDirPath, session));
  }

  Future<bool> _restoreFromVault(
      PdfFileItem vaultItem, String restoreDirPath, int session) async {
    try {
      if (!_hasSession(session)) return false;
      final key = await _readyKey;
      final vaultFile = File(vaultItem.path);
      if (!await _isVaultFile(vaultFile) || !_hasSession(session)) return false;
      final restoreDir = Directory(restoreDirPath);
      final resolvedRestoreDir = await restoreDir.resolveSymbolicLinks();
      final resolvedVaultDir = await _vaultDir!.resolveSymbolicLinks();
      if (p.equals(resolvedVaultDir, resolvedRestoreDir) ||
          p.isWithin(resolvedVaultDir, resolvedRestoreDir)) {
        return false;
      }

      final encryptedBytes = await vaultFile.readAsBytes();
      final decryptedBytes =
          key.encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: key.iv);

      final newFile =
          await _availableFile(restoreDir, p.basename(vaultFile.path));
      if (!_hasSession(session)) return false;
      await newFile.writeAsBytes(decryptedBytes, flush: true);

      if (await newFile.exists() &&
          (await newFile.length()) == decryptedBytes.length) {
        await vaultFile.delete();
      } else {
        return false;
      }

      try {
        _ref.read(pdfLibraryControllerProvider.notifier).refresh();
      } catch (_) {}
      await loadVaultFiles();
      return true;
    } catch (e) {
      if (e is VaultInitException) rethrow;
      return false;
    }
  }
}

final vaultControllerProvider =
    StateNotifierProvider<VaultController, VaultState>((ref) {
  return VaultController(ref);
});
