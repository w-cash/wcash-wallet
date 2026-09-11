import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../product_identity.dart';

const wardenIosSecureStorageOptions = IOSOptions(
  accountName: WardenProductIdentity.secureStorageScope,
  accessibility: KeychainAccessibility.unlocked_this_device,
  synchronizable: false,
);

const wardenAndroidSecureStorageOptions = AndroidOptions(
  // Losing a mnemonic silently is worse than surfacing a storage failure.
  resetOnError: false,
  migrateOnAlgorithmChange: true,
  sharedPreferencesName: WardenProductIdentity.secureStorageScope,
  preferencesKeyPrefix: WardenProductIdentity.secureStorageKeyPrefix,
);

const wardenMacOsSecureStorageOptions = MacOsOptions(
  accountName: WardenProductIdentity.secureStorageScope,
  accessibility: KeychainAccessibility.unlocked_this_device,
  synchronizable: false,
  usesDataProtectionKeychain: true,
);

/// The small storage boundary used for Warden's only secret.
///
/// Implementations must not log keys or values. The production implementation
/// delegates directly to the operating system secure-storage plugin.
abstract interface class WardenSecureStoreBackend {
  Future<void> write({required String key, required String value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});
}

enum WardenSecureStorageOperation { read, write, verify, delete }

/// Deliberately omits the platform exception and all secret material.
final class WardenSecureStorageException implements Exception {
  const WardenSecureStorageException(this.operation);

  final WardenSecureStorageOperation operation;

  @override
  String toString() => switch (operation) {
    WardenSecureStorageOperation.read =>
      'Secure wallet recovery phrase could not be read.',
    WardenSecureStorageOperation.write =>
      'Secure wallet recovery phrase could not be stored.',
    WardenSecureStorageOperation.verify =>
      'Secure wallet recovery phrase storage could not be verified.',
    WardenSecureStorageOperation.delete =>
      'Secure wallet recovery phrase could not be removed.',
  };
}

final class FlutterWardenSecureStoreBackend
    implements WardenSecureStoreBackend {
  FlutterWardenSecureStoreBackend._(this._storage);

  factory FlutterWardenSecureStoreBackend.production() {
    return FlutterWardenSecureStoreBackend._(
      const FlutterSecureStorage(
        iOptions: wardenIosSecureStorageOptions,
        aOptions: wardenAndroidSecureStorageOptions,
        lOptions: LinuxOptions.defaultOptions,
        mOptions: wardenMacOsSecureStorageOptions,
        wOptions: WindowsOptions.defaultOptions,
      ),
    );
  }

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

/// Owns mnemonic persistence without retaining an in-memory copy.
///
/// Callers should keep the returned mnemonic in the narrowest possible scope
/// and pass it directly to Rust. This class never caches, normalizes, logs, or
/// places the mnemonic on the clipboard.
final class WardenMnemonicStore {
  const WardenMnemonicStore(this._backend);

  static const mnemonicKey = WardenProductIdentity.mnemonicStorageKey;

  final WardenSecureStoreBackend _backend;

  Future<void> writeMnemonic(String mnemonic) async {
    if (mnemonic.isEmpty) {
      throw const WardenSecureStorageException(
        WardenSecureStorageOperation.write,
      );
    }

    try {
      await _backend.write(key: mnemonicKey, value: mnemonic);
    } catch (_) {
      throw const WardenSecureStorageException(
        WardenSecureStorageOperation.write,
      );
    }

    String? stored;
    try {
      stored = await _backend.read(key: mnemonicKey);
    } catch (_) {
      await _bestEffortDelete();
      throw const WardenSecureStorageException(
        WardenSecureStorageOperation.verify,
      );
    }

    if (stored != mnemonic) {
      await _bestEffortDelete();
      throw const WardenSecureStorageException(
        WardenSecureStorageOperation.verify,
      );
    }
  }

  Future<String?> readMnemonic() async {
    try {
      return await _backend.read(key: mnemonicKey);
    } catch (_) {
      throw const WardenSecureStorageException(
        WardenSecureStorageOperation.read,
      );
    }
  }

  Future<void> deleteMnemonic() async {
    try {
      await _backend.delete(key: mnemonicKey);
      if (await _backend.read(key: mnemonicKey) != null) {
        throw StateError('secure delete verification failed');
      }
    } catch (_) {
      throw const WardenSecureStorageException(
        WardenSecureStorageOperation.delete,
      );
    }
  }

  Future<void> _bestEffortDelete() async {
    try {
      await _backend.delete(key: mnemonicKey);
    } catch (_) {
      // The caller still receives a fail-closed, secret-free verification
      // error. There is no safe additional recovery action at this boundary.
    }
  }
}

final wardenSecureStoreBackendProvider = Provider<WardenSecureStoreBackend>(
  (ref) => FlutterWardenSecureStoreBackend.production(),
);

final wardenMnemonicStoreProvider = Provider<WardenMnemonicStore>(
  (ref) => WardenMnemonicStore(ref.watch(wardenSecureStoreBackendProvider)),
);
