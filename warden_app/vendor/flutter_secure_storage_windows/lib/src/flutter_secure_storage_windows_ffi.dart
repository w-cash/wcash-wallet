// Secure-storage file access stays asynchronous to avoid blocking Flutter.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/src/atomic_file_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// An extension on `Map<String, String>` to add support for specific
/// configuration options related to backward compatibility.
@visibleForTesting
extension OptionsExtension on Map<String, String> {
  /// Checks whether the `useBackwardCompatibility` flag is enabled in the map.
  ///
  /// Returns:
  /// - `true` if the value associated with the `useBackwardCompatibility` key
  ///   is not `'false'`.
  /// - `false` otherwise.
  bool get useBackwardCompatibility =>
      this['useBackwardCompatibility'] != 'false';
}

/// Serialises async critical sections without external dependencies.
///
/// Each [run] call waits for the previous one to finish (including error cases)
/// before starting the next, preventing concurrent read-modify-write races.
class _AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() fn) {
    final next = _last.then((_) => fn());
    // Swallow errors so a failed operation does not poison future callers.
    _last = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}

/// The `FlutterSecureStorageWindows` class provides a Windows-specific
/// implementation of the `FlutterSecureStoragePlatform` interface.
///
/// This implementation uses a combination of a backward-compatible storage
/// mechanism and a platform-specific storage backend.
class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  /// Creates an instance of `FlutterSecureStorageWindows` with default
  /// configurations for both backward compatibility and platform-specific
  /// storage.
  FlutterSecureStorageWindows()
      : this._(MethodChannelFlutterSecureStorage(), DpapiJsonFileMapStorage());

  /// Internal constructor to initialize `FlutterSecureStorageWindows` with
  /// custom implementations for backward compatibility and platform-specific
  /// storage.
  ///
  /// Parameters:
  /// - [_backwardCompatible]: The storage mechanism used for backward
  ///   compatibility.
  /// - [_storage]: The platform-specific storage backend for Windows.
  FlutterSecureStorageWindows._(this._backwardCompatible, this._storage);

  /// The storage implementation used for backward compatibility.
  final FlutterSecureStoragePlatform _backwardCompatible;

  /// The platform-specific storage implementation for Windows, using DPAPI.
  final MapStorage _storage;

  final _lock = _AsyncLock();

  /// Registers this plugin.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        if (map.containsKey(key)) {
          return true;
        }

        if (options.useBackwardCompatibility) {
          return _backwardCompatible.containsKey(key: key, options: options);
        }

        return false;
      });

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        final initialSize = map.length;
        map.remove(key);
        if (map.length != initialSize) {
          await _storage.save(map, options);
        }

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.delete(key: key, options: options);
        }
      });

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _lock.run(() async {
        await _storage.clear(options);

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.deleteAll(options: options);
        }
      });

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);

        var result = map[key];
        if (options.useBackwardCompatibility) {
          if (result == null) {
            final compatible = await _backwardCompatible.read(
              key: key,
              options: options,
            );
            if (compatible != null) {
              // Write back now, so the value should be retrieved from JSON file
              // next.
              result = map[key] = compatible;
              await _storage.save(map, options);
            }
          }

          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }

        return result;
      });

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        if (!options.useBackwardCompatibility) {
          // Just return a map.
          return map;
        }

        final compatible = await _backwardCompatible.readAll(options: options);

        if (compatible.isEmpty) {
          return map;
        }

        for (final entry in compatible.entries) {
          map.putIfAbsent(entry.key, () => entry.value);
        }

        // Write back now, so the value should be retrieved from JSON file next.
        await _storage.save(map, options);

        // Clear old entries.
        await _backwardCompatible.deleteAll(options: options);

        return map;
      });

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        map[key] = value;
        await _storage.save(map, options);

        if (options.useBackwardCompatibility) {
          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }
      });
}

/// Creates a custom instance of `FlutterSecureStorageWindows` for testing.
///
/// This factory function is annotated with `@visibleForTesting` to indicate
/// its intended use in testing scenarios. It allows specifying custom
/// implementations for backward compatibility and platform-specific storage.
///
/// Parameters:
/// - [backwardCompatible]: A custom implementation of
///   `FlutterSecureStoragePlatform` for backward-compatible storage behavior.
/// - [mapStorage]: A custom implementation of `MapStorage` for Windows secure
///   storage functionality.
///
/// Returns:
/// - An instance of `FlutterSecureStorageWindows` configured with the given
///   `backwardCompatible` and `mapStorage` implementations.
@visibleForTesting
FlutterSecureStorageWindows createFlutterSecureStorageWindows(
  FlutterSecureStoragePlatform backwardCompatible,
  MapStorage mapStorage,
) =>
    FlutterSecureStorageWindows._(backwardCompatible, mapStorage);

@visibleForTesting

/// An abstract class that defines the interface for map-based storage
/// implementations.
abstract class MapStorage {
  /// Loads a map of key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the load operation.
  FutureOr<Map<String, String>> load(Map<String, String> options);

  /// Saves a map of key-value pairs to the storage medium.
  ///
  /// Parameters:
  /// - [data]: A map containing the data to save.
  /// - [options]: A map of options to customize the save operation.
  FutureOr<void> save(Map<String, String> data, Map<String, String> options);

  /// Clears all key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the clear operation.
  FutureOr<void> clear(Map<String, String> options);
}

/// The file name used to store encrypted JSON data.
///
/// This constant is exposed for testing purposes.
@visibleForTesting
const String encryptedJsonFileName = 'flutter_secure_storage.dat';

const _atomicReplaceRetryDelay = Duration(milliseconds: 25);
const _atomicReplaceTimeout = Duration(seconds: 2);

// FFI signatures require separate native and Dart function types.
// ignore: avoid_private_typedef_functions
typedef _ReplaceFileNative = Int32 Function(
  Pointer<Utf16> replacedFileName,
  Pointer<Utf16> replacementFileName,
  Pointer<Utf16> backupFileName,
  Uint32 replaceFlags,
  Pointer<Void> exclude,
  Pointer<Void> reserved,
);

// FFI signatures require separate native and Dart function types.
// ignore: avoid_private_typedef_functions
typedef _ReplaceFileDart = int Function(
  Pointer<Utf16> replacedFileName,
  Pointer<Utf16> replacementFileName,
  Pointer<Utf16> backupFileName,
  int replaceFlags,
  Pointer<Void> exclude,
  Pointer<Void> reserved,
);

// Top-level fields are initialized lazily. Keeping this lazy lets host-side
// tests import the FFI library without trying to open kernel32.dll on macOS.
final _ReplaceFileDart _replaceFile = DynamicLibrary.open(
  'kernel32.dll',
).lookupFunction<_ReplaceFileNative, _ReplaceFileDart>('ReplaceFileW');

Future<String> _getJsonFilePath() async {
  final appDataDirectory = await getApplicationSupportDirectory();

  return path.canonicalize(
    path.join(appDataDirectory.path, encryptedJsonFileName),
  );
}

Future<void> _replaceWindowsFileAtomically({
  required String temporaryPath,
  required String destinationPath,
  required String? backupPath,
}) async {
  final deadline = DateTime.now().add(_atomicReplaceTimeout);

  while (true) {
    late final bool succeeded;
    late final WIN32_ERROR error;
    final destinationExists = await File(destinationPath).exists();

    using((alloc) {
      final temporary = temporaryPath.toNativeUtf16(allocator: alloc);
      final destination = destinationPath.toNativeUtf16(allocator: alloc);

      if (!destinationExists) {
        final result = MoveFileEx(
          PCWSTR(temporary),
          PCWSTR(destination),
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        );
        succeeded = result.value;
        error = result.error;
        return;
      }

      final backup = backupPath == null
          ? nullptr.cast<Utf16>()
          : backupPath.toNativeUtf16(allocator: alloc);

      // Resolve GetLastError before the native call so lazy symbol lookup
      // cannot overwrite the error produced by ReplaceFileW.
      GetLastError();
      succeeded =
          _replaceFile(destination, temporary, backup, 0, nullptr, nullptr) !=
              0;
      error = GetLastError();
    });

    if (succeeded) {
      return;
    }

    final isRetriable = error == ERROR_SHARING_VIOLATION ||
        error == ERROR_LOCK_VIOLATION ||
        error == ERROR_FILE_NOT_FOUND;
    if (!isRetriable || DateTime.now().isAfter(deadline)) {
      throw WindowsException(
        error.toHRESULT(),
        message: 'Could not atomically replace Windows secure storage.',
      );
    }
    await Future<void>.delayed(_atomicReplaceRetryDelay);
  }
}

class _DpapiSecureStorageCodec implements SecureStorageCodec {
  const _DpapiSecureStorageCodec();

  @override
  Uint8List protect(Uint8List clearText) => using((alloc) {
        final input = alloc<Uint8>(clearText.length);
        input.asTypedList(clearText.length).setAll(0, clearText);

        final clearTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        clearTextBlob.ref.cbData = clearText.length;
        clearTextBlob.ref.pbData = input;

        final cipherTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        final result = CryptProtectData(
          clearTextBlob,
          null,
          null,
          null,
          0,
          cipherTextBlob,
        );
        if (!result.value) {
          throw const SecureStorageWriteException();
        }
        if (cipherTextBlob.ref.pbData.address == NULL) {
          throw const SecureStorageWriteException();
        }

        try {
          return Uint8List.fromList(
            cipherTextBlob.ref.pbData.asTypedList(cipherTextBlob.ref.cbData),
          );
        } finally {
          if (cipherTextBlob.ref.pbData.address != NULL) {
            final freeResult =
                LocalFree(HLOCAL(cipherTextBlob.ref.pbData.cast()));
            if (!freeResult.value.isNull) {
              debugPrint(
                'save: Failed to release an encrypted DPAPI buffer: '
                '${freeResult.error.toHRESULT().toHexString()}',
              );
            }
          }
        }
      });

  @override
  Uint8List unprotect(Uint8List cipherText) => using((alloc) {
        final input = alloc<Uint8>(cipherText.length);
        input.asTypedList(cipherText.length).setAll(0, cipherText);

        final cipherTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        cipherTextBlob.ref.cbData = cipherText.length;
        cipherTextBlob.ref.pbData = input;

        final clearTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        final result = CryptUnprotectData(
          cipherTextBlob,
          null,
          null,
          null,
          0,
          clearTextBlob,
        );
        if (!result.value) {
          throw const SecureStorageCorruptionException();
        }
        if (clearTextBlob.ref.pbData.address == NULL) {
          throw const SecureStorageCorruptionException();
        }

        try {
          return Uint8List.fromList(
            clearTextBlob.ref.pbData.asTypedList(clearTextBlob.ref.cbData),
          );
        } finally {
          if (clearTextBlob.ref.pbData.address != NULL) {
            final freeResult =
                LocalFree(HLOCAL(clearTextBlob.ref.pbData.cast()));
            if (!freeResult.value.isNull) {
              debugPrint(
                'load: Failed to release a decrypted DPAPI buffer: '
                '${freeResult.error.toHRESULT().toHexString()}',
              );
            }
          }
        }
      });
}

/// A `MapStorage` implementation that uses DPAPI (Data Protection API) for
/// encryption and stores data in a JSON file on disk.
///
/// This implementation is specific to Windows platforms.
@visibleForTesting
class DpapiJsonFileMapStorage extends MapStorage {
  /// Creates an instance of `DpapiJsonFileMapStorage`.
  DpapiJsonFileMapStorage()
      : _storage = AtomicEncryptedFileStorage(
          filePath: _getJsonFilePath,
          codec: const _DpapiSecureStorageCodec(),
          files: IoSecureStorageFileOperations(
            atomicReplace: _replaceWindowsFileAtomically,
          ),
          log: (message) => debugPrint(message),
        );

  final AtomicEncryptedFileStorage _storage;

  @override
  FutureOr<Map<String, String>> load(Map<String, String> options) =>
      _storage.load();

  @override
  FutureOr<void> save(Map<String, String> data, Map<String, String> options) =>
      _storage.save(data);

  @override
  FutureOr<void> clear(Map<String, String> options) => _storage.clear();
}
