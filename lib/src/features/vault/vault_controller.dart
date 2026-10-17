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

  VaultState({
    this.isUnlocked = false,
    this.vaultFiles = const [],
    this.isLoading = false,
  });

  VaultState copyWith({bool? isUnlocked, List<PdfFileItem>? vaultFiles, bool? isLoading}) {
    return VaultState(
      isUnlocked: isUnlocked ?? this.isUnlocked,
      vaultFiles: vaultFiles ?? this.vaultFiles,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class VaultController extends StateNotifier<VaultState> {
  VaultController(this._ref) : super(VaultState());

  final Ref _ref;
  final _storage = const FlutterSecureStorage();

  enc.Encrypter? _encrypter;
  enc.IV? _iv;
  Future<void>? _initFuture;

  Future<void> get ready {
    _initFuture ??= _initVault();
    return _initFuture!;
  }

  Future<void> _initVault() async {
    try {
      String? keyStr = await _storage.read(key: 'vault_key');
      if (keyStr == null) {
        final key = enc.Key.fromSecureRandom(32);
        keyStr = base64Encode(key.bytes);
        await _storage.write(key: 'vault_key', value: keyStr);
      }

      String? ivStr = await _storage.read(key: 'vault_iv');
      if (ivStr == null) {
        final ivBytes = enc.IV.fromSecureRandom(16);
        ivStr = base64Encode(ivBytes.bytes);
        await _storage.write(key: 'vault_iv', value: ivStr);
      }

      final keyBytes = base64Decode(keyStr);
      _iv = enc.IV(base64Decode(ivStr));
      _encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    } catch (e) {
      _initFuture = null; // Allow retry on failure
      throw VaultInitException('Failed to initialize secure vault: $e');
    }
  }

  Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, 'vault'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  Future<void> loadVaultFiles() async {
    state = state.copyWith(isLoading: true);
    try {
      final vaultDir = await _getVaultDirectory();
      final files = vaultDir.listSync().whereType<File>().toList();
      final items = files.map((f) => PdfFileItem.fromFile(f, isEncrypted: true)).toList();
      state = state.copyWith(vaultFiles: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void setUnlocked(bool unlocked) {
    state = state.copyWith(isUnlocked: unlocked);
    if (unlocked) {
      loadVaultFiles();
    } else {
      state = state.copyWith(vaultFiles: []);
    }
  }

  Future<bool> moveToVault(PdfFileItem item) async {
    try {
      await ready;
      final encrypter = _encrypter;
      final iv = _iv;
      if (encrypter == null || iv == null) throw VaultInitException('Vault not initialized');

      final file = File(item.path);
      if (!await file.exists()) return false;

      final vaultDir = await _getVaultDirectory();

      String newName = item.name;
      int counter = 1;
      while (await File(p.join(vaultDir.path, newName)).exists()) {
        final nameWithoutExt = p.basenameWithoutExtension(item.name);
        newName = '${nameWithoutExt}_$counter.pdf';
        counter++;
      }
      final newPath = p.join(vaultDir.path, newName);
      final newFile = File(newPath);

      final bytes = await file.readAsBytes();
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);
      final encryptedBytes = encrypted.bytes;

      await newFile.writeAsBytes(encryptedBytes, flush: true);

      if (await newFile.exists() && (await newFile.length()) > 0) {
        await file.delete();
      } else {
        return false;
      }

      _ref.read(pdfLibraryControllerProvider.notifier).refresh();
      loadVaultFiles();
      return true;
    } catch (e) {
      if (e is VaultInitException) rethrow;
      return false;
    }
  }

  Future<File?> decryptToTempFile(PdfFileItem vaultItem) async {
    try {
      await ready;
      final encrypter = _encrypter;
      final iv = _iv;
      if (encrypter == null || iv == null) throw VaultInitException('Vault not initialized');

      final vaultFile = File(vaultItem.path);
      if (!await vaultFile.exists()) return null;

      final encryptedBytes = await vaultFile.readAsBytes();
      final decryptedBytes = encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv);

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'temp_decrypted_${vaultItem.name}'));
      await tempFile.writeAsBytes(decryptedBytes, flush: true);
      return tempFile;
    } catch (e) {
      if (e is VaultInitException) rethrow;
      return null;
    }
  }

  Future<bool> restoreFromVault(PdfFileItem vaultItem, String restoreDirPath) async {
    try {
      await ready;
      final encrypter = _encrypter;
      final iv = _iv;
      if (encrypter == null || iv == null) throw VaultInitException('Vault not initialized');

      final vaultFile = File(vaultItem.path);
      if (!await vaultFile.exists()) return false;

      final encryptedBytes = await vaultFile.readAsBytes();
      final decryptedBytes = encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv);

      final newPath = p.join(restoreDirPath, vaultItem.name);
      final newFile = File(newPath);
      await newFile.writeAsBytes(decryptedBytes, flush: true);

      if (await newFile.exists() && (await newFile.length()) > 0) {
        await vaultFile.delete();
      } else {
        return false;
      }

      _ref.read(pdfLibraryControllerProvider.notifier).refresh();
      loadVaultFiles();
      return true;
    } catch (e) {
      if (e is VaultInitException) rethrow;
      return false;
    }
  }
}

final vaultControllerProvider = StateNotifierProvider<VaultController, VaultState>((ref) {
  return VaultController(ref);
});
