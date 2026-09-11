// Storage I/O stays asynchronous so secure-storage operations do not block the
// Flutter isolate.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

/// Encrypts and decrypts the complete secure-storage payload.
///
/// Implementations must not include payload bytes in thrown errors.
abstract interface class SecureStorageCodec {
  /// Encrypts [clearText].
  FutureOr<Uint8List> protect(Uint8List clearText);

  /// Decrypts [cipherText].
  FutureOr<Uint8List> unprotect(Uint8List cipherText);
}

/// File primitives used by [AtomicEncryptedFileStorage].
///
/// Keeping replacement behind this interface makes all crash-recovery paths
/// testable on hosts where Windows DPAPI and `ReplaceFileW` are unavailable.
abstract interface class SecureStorageFileOperations {
  /// Returns whether [filePath] exists.
  Future<bool> exists(String filePath);

  /// Reads all bytes from [filePath].
  Future<Uint8List> read(String filePath);

  /// Creates a unique, empty file in the same directory as [destinationPath].
  Future<String> createTemporaryFile(String destinationPath);

  /// Replaces [filePath] with [bytes], flushing them before this returns.
  Future<void> writeAndFlush(String filePath, Uint8List bytes);

  /// Atomically installs [temporaryPath] as [destinationPath].
  ///
  /// When the destination exists and [backupPath] is non-null, the old
  /// destination is retained at [backupPath].
  Future<void> replaceAtomically({
    required String temporaryPath,
    required String destinationPath,
    required String? backupPath,
  });

  /// Deletes [filePath].
  Future<void> delete(String filePath);
}

/// Callback used by [IoSecureStorageFileOperations] for the platform-specific
/// atomic replacement primitive.
typedef AtomicReplace = FutureOr<void> Function({
  required String temporaryPath,
  required String destinationPath,
  required String? backupPath,
});

/// `dart:io` implementation of the portable file operations.
///
/// Atomic replacement is injected because Windows needs `ReplaceFileW` when a
/// destination exists, while tests can supply a host-native implementation.
class IoSecureStorageFileOperations implements SecureStorageFileOperations {
  /// Creates file operations using [atomicReplace] to commit temporary files.
  IoSecureStorageFileOperations({required AtomicReplace atomicReplace})
      : _atomicReplace = atomicReplace;

  final AtomicReplace _atomicReplace;

  @override
  Future<String> createTemporaryFile(String destinationPath) async {
    final directory = Directory(path.dirname(destinationPath));
    await directory.create(recursive: true);

    for (var attempt = 0; attempt < 100; attempt++) {
      final temporaryPath = '$destinationPath.$pid.'
          '${DateTime.now().microsecondsSinceEpoch}.$attempt.tmp';
      try {
        await File(temporaryPath).create(exclusive: true);
        return temporaryPath;
      } on PathExistsException {
        // Retry with a distinct suffix.
      }
    }

    throw FileSystemException(
      'Could not allocate a secure-storage temporary file.',
      destinationPath,
    );
  }

  @override
  Future<void> delete(String filePath) => File(filePath).delete();

  @override
  Future<bool> exists(String filePath) => File(filePath).exists();

  @override
  Future<Uint8List> read(String filePath) => File(filePath).readAsBytes();

  @override
  Future<void> replaceAtomically({
    required String temporaryPath,
    required String destinationPath,
    required String? backupPath,
  }) async {
    if (path.dirname(temporaryPath) != path.dirname(destinationPath)) {
      throw FileSystemException(
        'Secure-storage temporary files must share the destination directory.',
        temporaryPath,
      );
    }
    await _atomicReplace(
      temporaryPath: temporaryPath,
      destinationPath: destinationPath,
      backupPath: backupPath,
    );
  }

  @override
  Future<void> writeAndFlush(String filePath, Uint8List bytes) async {
    final handle = await File(filePath).open(mode: FileMode.write);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }
}

/// An unreadable encrypted payload.
///
/// The message deliberately excludes the codec exception and decoded input so
/// mnemonic material can never escape through logs or error reporting.
final class SecureStorageCorruptionException implements Exception {
  /// Creates a sanitized corruption error.
  const SecureStorageCorruptionException();

  @override
  String toString() => 'Secure storage data is unreadable.';
}

/// A failed secure-storage commit whose diagnostics contain no payload data.
final class SecureStorageWriteException implements Exception {
  /// Creates a sanitized write error.
  const SecureStorageWriteException();

  @override
  String toString() => 'Secure storage could not be updated safely.';
}

/// A failed attempt to restore the last known-good encrypted payload.
final class SecureStorageRecoveryException implements Exception {
  /// Creates a sanitized recovery error.
  const SecureStorageRecoveryException();

  @override
  String toString() => 'Secure storage recovery could not be completed.';
}

/// Persists an encrypted JSON map with atomic replacement and backup recovery.
///
/// The primary, backup, marker, and temporary files always live in the same
/// directory. No read or decode failure deletes either ciphertext. Callers
/// must serialize complete load-modify-save operations; the Windows plugin's
/// existing asynchronous lock provides that serialization.
class AtomicEncryptedFileStorage {
  /// Creates storage for the path returned by [filePath].
  AtomicEncryptedFileStorage({
    required FutureOr<String> Function() filePath,
    required SecureStorageCodec codec,
    required SecureStorageFileOperations files,
    void Function(String message)? log,
  })  : _filePath = filePath,
        _codec = codec,
        _files = files,
        _log = log;

  static const _backupSuffix = '.bak';
  static const _invalidBackupSuffix = '.invalid';
  static const _restorePendingSuffix = '.restore';
  static final _invalidMarkerBytes = Uint8List.fromList(const [1]);
  static final _restoreMarkerBytes = Uint8List.fromList(const [1]);

  final FutureOr<String> Function() _filePath;
  final SecureStorageCodec _codec;
  final SecureStorageFileOperations _files;
  final void Function(String message)? _log;

  /// Loads the complete string-to-string map.
  Future<Map<String, String>> load() async {
    final primary = await _filePath();
    final backup = '$primary$_backupSuffix';
    final invalidBackup = '$backup$_invalidBackupSuffix';
    final restorePending = '$backup$_restorePendingSuffix';

    if (!await _files.exists(primary)) {
      if (!await _files.exists(backup)) {
        return <String, String>{};
      }

      if (await _files.exists(restorePending)) {
        final recovered = await _loadFile(backup);
        await _restoreBackup(primary: primary, backup: backup);
        await _deleteMarker(invalidBackup);
        await _deleteMarker(restorePending);
        return recovered;
      }

      if (await _files.exists(invalidBackup)) {
        throw const SecureStorageRecoveryException();
      }

      final recovered = await _loadFile(backup);
      await _restoreBackup(primary: primary, backup: backup);
      return recovered;
    }

    try {
      final loaded = await _loadFile(primary);
      if (await _files.exists(invalidBackup)) {
        await _repairInvalidatedBackup(
          primary: primary,
          invalidBackup: invalidBackup,
        );
      }
      await _deleteMarker(restorePending);
      return loaded;
    } on SecureStorageCorruptionException catch (error, stackTrace) {
      if (!await _files.exists(invalidBackup) && await _files.exists(backup)) {
        Map<String, String> recovered;
        try {
          recovered = await _loadFile(backup);
        } on SecureStorageCorruptionException {
          _log?.call(
            'Windows secure-storage primary and backup are unreadable.',
          );
          Error.throwWithStackTrace(error, stackTrace);
        }

        try {
          await _restoreBackup(primary: primary, backup: backup);
        } on Object catch (_, recoveryStackTrace) {
          Error.throwWithStackTrace(
            const SecureStorageRecoveryException(),
            recoveryStackTrace,
          );
        }
        _log?.call('Recovered Windows secure storage from its backup.');
        return recovered;
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Atomically saves [data], preserving a validated recovery copy.
  Future<void> save(Map<String, String> data) async {
    final primary = await _filePath();
    final backup = '$primary$_backupSuffix';
    final invalidBackup = '$backup$_invalidBackupSuffix';
    final restorePending = '$backup$_restorePendingSuffix';

    final hadPrimary = await _prepareRecoveryBaseline(
      primary: primary,
      backup: backup,
      invalidBackup: invalidBackup,
      restorePending: restorePending,
    );

    final clearText = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final Uint8List encryptedText;
    try {
      encryptedText = Uint8List.fromList(
        await Future<Uint8List>.value(_codec.protect(clearText)),
      );
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SecureStorageWriteException(),
        stackTrace,
      );
    }

    final temporary = await _files.createTemporaryFile(primary);
    try {
      await _files.writeAndFlush(temporary, encryptedText);
      final verified = await _loadFile(temporary);
      if (!_mapsEqual(verified, data)) {
        throw const SecureStorageWriteException();
      }

      await _files.writeAndFlush(invalidBackup, _invalidMarkerBytes);
      if (hadPrimary) {
        // This marker is durable before ReplaceFileW starts. If Windows moves
        // the old primary to the backup name and the process stops before the
        // API reports its partial failure, the next load may restore that
        // already-validated predecessor.
        await _files.writeAndFlush(restorePending, _restoreMarkerBytes);
      }
      try {
        await _files.replaceAtomically(
          temporaryPath: temporary,
          destinationPath: primary,
          backupPath: backup,
        );
      } on Object catch (_, commitStackTrace) {
        final committed = await _recoverAfterFailedPrimaryCommit(
          primary: primary,
          backup: backup,
          invalidBackup: invalidBackup,
          restorePending: restorePending,
          expected: data,
        );
        if (!committed) {
          Error.throwWithStackTrace(
            const SecureStorageWriteException(),
            commitStackTrace,
          );
        }
      }

      try {
        await _refreshBackup(primary: primary, backup: backup);
        await _deleteMarker(invalidBackup);
        await _deleteMarker(restorePending);
      } on Object catch (_) {
        // The primary commit is already durable. Retain the invalid marker so
        // a stale backup is never used, then repair it after a later read.
        _log?.call(
          'Could not refresh the Windows secure-storage backup after commit.',
        );
      }
    } finally {
      await _deleteTemporaryFile(temporary);
    }
  }

  Future<bool> _prepareRecoveryBaseline({
    required String primary,
    required String backup,
    required String invalidBackup,
    required String restorePending,
  }) async {
    if (!await _files.exists(primary)) {
      if (await _files.exists(backup)) {
        // This resolves a prior interrupted replacement or a missing primary
        // before a new write is allowed to change any recovery state.
        await load();
      }

      if (!await _files.exists(primary)) {
        await _deleteMarkerStrict(invalidBackup);
        await _deleteMarkerStrict(restorePending);
        return false;
      }
    }

    final current = await _loadFile(primary);
    var backupIsCurrent = false;
    if (!await _files.exists(invalidBackup) && await _files.exists(backup)) {
      try {
        backupIsCurrent = _mapsEqual(await _loadFile(backup), current);
      } on SecureStorageCorruptionException {
        // A readable primary can safely replace an unreadable recovery copy.
      }
    }

    if (!backupIsCurrent) {
      await _files.writeAndFlush(invalidBackup, _invalidMarkerBytes);
      try {
        await _refreshBackup(primary: primary, backup: backup);
        await _deleteMarkerStrict(invalidBackup);
      } on Object catch (_, stackTrace) {
        Error.throwWithStackTrace(
          const SecureStorageWriteException(),
          stackTrace,
        );
      }
    }

    // A restore marker authorizes one specific backup. Never let it survive
    // into a later commit where that backup might represent different data.
    await _deleteMarkerStrict(restorePending);
    return true;
  }

  /// Removes the primary and all recovery state.
  Future<void> clear() async {
    final primary = await _filePath();
    final backup = '$primary$_backupSuffix';
    final invalidBackup = '$backup$_invalidBackupSuffix';
    final restorePending = '$backup$_restorePendingSuffix';

    // Remove the backup first: interruption leaves either the old primary or
    // an empty store and can never resurrect an intentionally cleared value.
    await _deleteIfPresent(backup);
    await _deleteIfPresent(primary);
    await _deleteMarker(invalidBackup);
    await _deleteMarker(restorePending);
  }

  Future<Map<String, String>> _loadFile(String filePath) async {
    final cipherText = await _files.read(filePath);
    final Uint8List clearText;
    try {
      clearText = Uint8List.fromList(
        await Future<Uint8List>.value(_codec.unprotect(cipherText)),
      );
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SecureStorageCorruptionException(),
        stackTrace,
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map ||
          decoded.entries.any(
            (entry) => entry.key is! String || entry.value is! String,
          )) {
        throw const FormatException();
      }
      return <String, String>{
        for (final entry in decoded.entries)
          entry.key as String: entry.value as String,
      };
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SecureStorageCorruptionException(),
        stackTrace,
      );
    }
  }

  Future<void> _restoreBackup({
    required String primary,
    required String backup,
  }) async {
    final temporary = await _files.createTemporaryFile(primary);
    try {
      await _files.writeAndFlush(temporary, await _files.read(backup));
      await _loadFile(temporary);
      await _files.replaceAtomically(
        temporaryPath: temporary,
        destinationPath: primary,
        backupPath: null,
      );
    } finally {
      await _deleteTemporaryFile(temporary);
    }
  }

  Future<void> _refreshBackup({
    required String primary,
    required String backup,
  }) async {
    final temporary = await _files.createTemporaryFile(backup);
    try {
      await _files.writeAndFlush(temporary, await _files.read(primary));
      await _loadFile(temporary);
      await _files.replaceAtomically(
        temporaryPath: temporary,
        destinationPath: backup,
        backupPath: null,
      );
    } finally {
      await _deleteTemporaryFile(temporary);
    }
  }

  Future<void> _repairInvalidatedBackup({
    required String primary,
    required String invalidBackup,
  }) async {
    try {
      await _refreshBackup(primary: primary, backup: '$primary$_backupSuffix');
      await _deleteMarker(invalidBackup);
    } on Object catch (_) {
      _log?.call(
        'Could not repair the invalidated Windows secure-storage backup.',
      );
    }
  }

  Future<bool> _recoverAfterFailedPrimaryCommit({
    required String primary,
    required String backup,
    required String invalidBackup,
    required String restorePending,
    required Map<String, String> expected,
  }) async {
    try {
      if (await _files.exists(primary)) {
        try {
          final current = await _loadFile(primary);
          final committed = _mapsEqual(current, expected);
          try {
            await _refreshBackup(primary: primary, backup: backup);
            await _deleteMarker(invalidBackup);
          } on Object catch (_) {
            // Keep the invalid marker; the valid primary is authoritative.
          }
          await _deleteMarker(restorePending);
          return committed;
        } on SecureStorageCorruptionException {
          // A partially failed replacement may leave an unreadable primary.
          // Continue below only if its validated predecessor still exists.
        }
      }

      if (await _files.exists(backup)) {
        await _loadFile(backup);
        await _files.writeAndFlush(restorePending, _restoreMarkerBytes);
        await _deleteMarkerStrict(invalidBackup);
        await _restoreBackup(primary: primary, backup: backup);
        await _deleteMarker(restorePending);
        return false;
      }

      if (!await _files.exists(primary)) {
        // A failed first write has no prior ciphertext to recover.
        await _deleteMarker(invalidBackup);
        await _deleteMarker(restorePending);
        return false;
      }
    } on Object catch (_, recoveryStackTrace) {
      Error.throwWithStackTrace(
        const SecureStorageRecoveryException(),
        recoveryStackTrace,
      );
    }

    throw const SecureStorageRecoveryException();
  }

  Future<void> _deleteIfPresent(String filePath) async {
    if (await _files.exists(filePath)) {
      await _files.delete(filePath);
    }
  }

  Future<void> _deleteMarker(String marker) async {
    try {
      await _deleteIfPresent(marker);
    } on Object catch (_) {
      _log?.call('Could not remove a Windows secure-storage recovery marker.');
    }
  }

  Future<void> _deleteMarkerStrict(String marker) => _deleteIfPresent(marker);

  Future<void> _deleteTemporaryFile(String temporary) async {
    try {
      await _deleteIfPresent(temporary);
    } on Object catch (_) {
      _log?.call('Could not remove a Windows secure-storage temporary file.');
    }
  }

  static bool _mapsEqual(
    Map<String, String> first,
    Map<String, String> second,
  ) =>
      first.length == second.length &&
      first.entries.every((entry) => second[entry.key] == entry.value);
}
