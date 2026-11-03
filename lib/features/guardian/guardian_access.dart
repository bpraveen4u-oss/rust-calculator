import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

abstract interface class GuardianAccess {
  Future<bool> hasPin();

  Future<void> setPin(String pin);

  Future<bool> verifyPin(String pin);

  Future<bool> canUseBiometrics();

  Future<bool> authenticateWithBiometrics();
}

class SecureGuardianAccess implements GuardianAccess {
  SecureGuardianAccess({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    LocalAuthentication? localAuthentication,
  }) : _secureStorage = secureStorage,
       _localAuthentication = localAuthentication ?? LocalAuthentication();

  static const _pinKey = 'guardian_pin';

  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> hasPin() async => await _secureStorage.read(key: _pinKey) != null;

  @override
  Future<void> setPin(String pin) async {
    await _secureStorage.write(key: _pinKey, value: pin);
  }

  @override
  Future<bool> verifyPin(String pin) async =>
      await _secureStorage.read(key: _pinKey) == pin;

  @override
  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuthentication.isDeviceSupported() &&
          await _localAuthentication.canCheckBiometrics &&
          (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: 'Unlock guardian controls',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } on PlatformException {
      return false;
    }
  }
}
