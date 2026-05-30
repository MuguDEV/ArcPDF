import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';
import '../../data/local_boxes.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

enum LockType { pin, pattern }

class SecurityState {
  const SecurityState({
    required this.isLockEnabled,
    required this.lockType,
    required this.isBiometricEnabled,
    required this.isLocked,
    required this.requireLockOnResume,
  });

  final bool isLockEnabled;
  final LockType lockType;
  final bool isBiometricEnabled;
  final bool isLocked;
  final bool requireLockOnResume;

  SecurityState copyWith({
    bool? isLockEnabled,
    LockType? lockType,
    bool? isBiometricEnabled,
    bool? isLocked,
    bool? requireLockOnResume,
  }) {
    return SecurityState(
      isLockEnabled: isLockEnabled ?? this.isLockEnabled,
      lockType: lockType ?? this.lockType,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isLocked: isLocked ?? this.isLocked,
      requireLockOnResume: requireLockOnResume ?? this.requireLockOnResume,
    );
  }
}

class SecurityController extends StateNotifier<SecurityState> {
  SecurityController(this._settingsBox)
      : super(SecurityState(
          isLockEnabled: _settingsBox.get('isLockEnabled', defaultValue: false) as bool,
          lockType: LockType.values[_settingsBox.get('lockType', defaultValue: 0) as int],
          isBiometricEnabled: _settingsBox.get('isBiometricEnabled', defaultValue: false) as bool,
          isLocked: _settingsBox.get('isLockEnabled', defaultValue: false) as bool,
          requireLockOnResume: _settingsBox.get('requireLockOnResume', defaultValue: true) as bool,
        ));

  final Box _settingsBox;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _auth = LocalAuthentication();

  Future<void> setLockEnabled(bool enabled, {String? pinOrPattern}) async {
    if (enabled && pinOrPattern != null) {
      final hash = _hashString(pinOrPattern);
      await _secureStorage.write(key: 'lock_secret', value: hash);
    } else if (!enabled) {
      await _secureStorage.delete(key: 'lock_secret');
      await setBiometricEnabled(false);
    }

    state = state.copyWith(isLockEnabled: enabled, isLocked: enabled);
    await _settingsBox.put('isLockEnabled', enabled);
  }

  Future<void> setLockType(LockType type) async {
    state = state.copyWith(lockType: type);
    await _settingsBox.put('lockType', type.index);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    state = state.copyWith(isBiometricEnabled: enabled);
    await _settingsBox.put('isBiometricEnabled', enabled);
  }

  Future<void> setRequireLockOnResume(bool enabled) async {
    state = state.copyWith(requireLockOnResume: enabled);
    await _settingsBox.put('requireLockOnResume', enabled);
  }

  Future<bool> verifyPinOrPattern(String input) async {
    final storedHash = await _secureStorage.read(key: 'lock_secret');
    if (storedHash == null) return false;

    final inputHash = _hashString(input);
    final isValid = inputHash == storedHash;

    if (isValid) {
      state = state.copyWith(isLocked: false);
    }
    return isValid;
  }

  Future<bool> authenticateBiometric() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      if (!canAuthenticate) return false;

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to unlock ArcPDF',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        state = state.copyWith(isLocked: false);
      }
      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  void lockApp() {
    if (state.isLockEnabled) {
      state = state.copyWith(isLocked: true);
    }
  }

  void unlockApp() {
    state = state.copyWith(isLocked: false);
  }

  String _hashString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

final securityControllerProvider = StateNotifierProvider<SecurityController, SecurityState>((ref) {
  return SecurityController(Hive.box(LocalBoxes.settings));
});
