import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/src/atomic_file_storage.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart'
    as windows;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const primary = '/secure/flutter_secure_storage.dat';
  const backup = '$primary.bak';
  const invalidBackup = '$backup.invalid';
  const restorePending = '$backup.restore';

  late _MemoryFileOperations files;
  late _TestCodec codec;
  late List<String> logs;
  late AtomicEncryptedFileStorage storage;

  setUp(() {
    files = _MemoryFileOperations();
    codec = _TestCodec();
    logs = <String>[];
    storage = AtomicEncryptedFileStorage(
      filePath: () => primary,
      codec: codec,
      files: files,
      log: logs.add,
    );
  });

  group('non-destructive reads', () {
    test('a decrypt failure preserves the only ciphertext', () async {
      final original = Uint8List.fromList(const [1, 2, 3, 4]);
      files.put(primary, original);

      await expectLater(
        storage.load(),
        throwsA(isA<SecureStorageCorruptionException>()),
      );

      expect(files.bytesAt(primary), original);
      expect(files.deletedPaths, isNot(contains(primary)));
    });

    test('a file read failure preserves the only ciphertext', () async {
      final original = codec.protectRaw('{"key":"value"}');
      files.put(primary, original);
      files.failReadPaths.add(primary);

      await expectLater(storage.load(), throwsStateError);

      expect(files.bytesAt(primary), original);
      expect(files.deletedPaths, isNot(contains(primary)));
    });

    for (final testCase in <(String, String)>[
      ('invalid UTF-8', String.fromCharCodes(const [0xFF, 0xFE])),
      ('invalid JSON', 'secret words are not JSON'),
      ('a non-object JSON root', '["secret words"]'),
      ('a non-string JSON value', '{"key": ["secret words"]}'),
    ]) {
      test('${testCase.$1} preserves the only ciphertext', () async {
        final original = codec.protectRaw(testCase.$2, encodeUtf8: false);
        files.put(primary, original);

        await expectLater(
          storage.load(),
          throwsA(isA<SecureStorageCorruptionException>()),
        );

        expect(files.bytesAt(primary), original);
        expect(files.deletedPaths, isNot(contains(primary)));
      });
    }

    test(
      'codec and JSON details never escape through errors or logs',
      () async {
        const secret = 'alpha beta gamma secret mnemonic';
        codec.failureText = secret;
        files
          ..put(primary, Uint8List.fromList(const [0]))
          ..put(backup, Uint8List.fromList(const [0]));

        Object? caught;
        try {
          await storage.load();
        } on Object catch (error) {
          caught = error;
        }

        expect(caught, isA<SecureStorageCorruptionException>());
        expect('$caught', isNot(contains(secret)));
        expect(logs.join('\n'), isNot(contains(secret)));
        expect(files.bytesAt(primary), const [0]);
        expect(files.bytesAt(backup), const [0]);
      },
    );
  });

  group('atomic writes and recovery', () {
    test('uses flushed same-directory temporary files', () async {
      await storage.save(const {'key': 'value'});

      expect(files.writeAndFlushPaths, isNotEmpty);
      expect(files.replacements, isNotEmpty);
      for (final replacement in files.replacements) {
        expect(
          path.dirname(replacement.temporaryPath),
          path.dirname(replacement.destinationPath),
        );
      }
      expect(
        files.paths.where((filePath) => filePath.endsWith('.tmp')),
        isEmpty,
      );
      expect(await storage.load(), const {'key': 'value'});
    });

    test(
      'prepares a validated backup before replacing a legacy primary',
      () async {
        files.put(
          primary,
          codec.protect(Uint8List.fromList(utf8.encode('{"key":"legacy"}'))),
        );

        await storage.save(const {'key': 'new'});

        final backupCommit = files.replacements.indexWhere(
          (replacement) => replacement.destinationPath == backup,
        );
        final primaryCommit = files.replacements.indexWhere(
          (replacement) => replacement.destinationPath == primary,
        );
        expect(backupCommit, isNonNegative);
        expect(primaryCommit, greaterThan(backupCommit));
        expect(await storage.load(), const {'key': 'new'});
      },
    );

    test(
      'a direct write never overwrites an unreadable only ciphertext',
      () async {
        final original = Uint8List.fromList(const [0]);
        files.put(primary, original);

        await expectLater(
          storage.save(const {'key': 'new'}),
          throwsA(isA<SecureStorageCorruptionException>()),
        );

        expect(files.bytesAt(primary), original);
        expect(files.existsSync(backup), isFalse);
      },
    );

    test(
      'a failed replacement preserves the last known-good primary',
      () async {
        await storage.save(const {'key': 'old'});
        final lastKnownGood = files.bytesAt(primary);
        files.failure = _ReplaceFailure.beforePrimaryReplacement;

        Object? caught;
        try {
          await storage.save(const {'key': 'secret replacement'});
        } on Object catch (error) {
          caught = error;
        }

        expect(caught, isA<SecureStorageWriteException>());
        expect('$caught', isNot(contains('secret replacement')));
        expect(files.bytesAt(primary), lastKnownGood);
        expect(await storage.load(), const {'key': 'old'});
      },
    );

    test(
      'a process-stop state during partial replacement remains recoverable',
      () async {
        await storage.save(const {'key': 'old'});
        files
          ..put(invalidBackup, Uint8List.fromList(const [1]))
          ..put(restorePending, Uint8List.fromList(const [1]))
          ..move(primary, backup);

        expect(await storage.load(), const {'key': 'old'});
        expect(files.existsSync(primary), isTrue);
        expect(files.existsSync(invalidBackup), isFalse);
        expect(files.existsSync(restorePending), isFalse);
      },
    );

    test(
      'restores the prior primary after a partial replacement failure',
      () async {
        await storage.save(const {'key': 'old'});
        files.failure = _ReplaceFailure.afterMovingPrimaryToBackup;

        await expectLater(
          storage.save(const {'key': 'new'}),
          throwsA(isA<SecureStorageWriteException>()),
        );

        expect(await storage.load(), const {'key': 'old'});
        expect(files.existsSync(invalidBackup), isFalse);
        expect(files.existsSync(restorePending), isFalse);
      },
    );

    test('retries a validated restore after the first restore fails', () async {
      await storage.save(const {'key': 'old'});
      files.failure = _ReplaceFailure.partialThenRestoreFailure;

      await expectLater(
        storage.save(const {'key': 'new'}),
        throwsA(isA<SecureStorageRecoveryException>()),
      );

      expect(files.existsSync(primary), isFalse);
      expect(files.existsSync(backup), isTrue);
      expect(files.existsSync(restorePending), isTrue);
      expect(await storage.load(), const {'key': 'old'});
      expect(files.existsSync(restorePending), isFalse);
    });

    test('repairs a backup refresh interrupted after primary commit', () async {
      await storage.save(const {'key': 'old'});
      files.failure = _ReplaceFailure.beforeBackupReplacement;

      await storage.save(const {'key': 'new'});

      expect(files.existsSync(invalidBackup), isTrue);
      expect(await storage.load(), const {'key': 'new'});
      expect(files.existsSync(invalidBackup), isFalse);

      files.put(primary, Uint8List.fromList(const [0]));
      expect(await storage.load(), const {'key': 'new'});
    });

    test(
      'a failed backup baseline refresh leaves the primary untouched',
      () async {
        await storage.save(const {'key': 'old'});
        final lastKnownGood = files.bytesAt(primary);
        files
          ..put(backup, Uint8List.fromList(const [0]))
          ..failure = _ReplaceFailure.beforeBackupReplacement;

        await expectLater(
          storage.save(const {'key': 'new'}),
          throwsA(isA<SecureStorageWriteException>()),
        );

        expect(files.bytesAt(primary), lastKnownGood);
        expect(files.existsSync(invalidBackup), isTrue);
        expect(await storage.load(), const {'key': 'old'});
      },
    );

    test(
      'recovers a corrupt primary from the current validated backup',
      () async {
        await storage.save(const {'key': 'old'});
        await storage.save(const {'key': 'new'});
        files.put(primary, Uint8List.fromList(const [0]));

        expect(await storage.load(), const {'key': 'new'});
        expect(await storage.load(), const {'key': 'new'});
        expect(files.existsSync(primary), isTrue);
      },
    );

    test(
      'backup recovery does not resurrect a successfully deleted key',
      () async {
        await storage.save(const {
          'deleted': 'secret mnemonic',
          'kept': 'value',
        });
        await storage.save(const {'kept': 'value'});
        files.put(primary, Uint8List.fromList(const [0]));

        expect(await storage.load(), const {'kept': 'value'});
      },
    );

    test(
      'an interrupted clear cannot report success or resurrect backup',
      () async {
        await storage.save(const {'mnemonic': 'old secret'});
        await storage.save(const {'mnemonic': 'current secret'});
        expect(files.existsSync(backup), isTrue);
        files.failDeletePaths.add(primary);

        await expectLater(storage.clear(), throwsStateError);

        expect(files.existsSync(backup), isFalse);
        expect(await storage.load(), const {'mnemonic': 'current secret'});
        files.failDeletePaths.clear();
        await storage.clear();
        expect(await storage.load(), isEmpty);
      },
    );

    test('never uses a backup marked stale after a committed write', () async {
      await storage.save(const {'key': 'old'});
      await storage.save(const {'key': 'new'});
      files.put(invalidBackup, Uint8List.fromList(const [1]));
      final corruptPrimary = Uint8List.fromList(const [0]);
      files.put(primary, corruptPrimary);

      await expectLater(
        storage.load(),
        throwsA(isA<SecureStorageCorruptionException>()),
      );

      expect(files.bytesAt(primary), corruptPrimary);
    });

    test(
      'an encryption error is sanitized and leaves primary untouched',
      () async {
        await storage.save(const {'key': 'old'});
        final lastKnownGood = files.bytesAt(primary);
        const secret = 'do not expose this mnemonic';
        codec
          ..failureText = secret
          ..failProtect = true;

        Object? caught;
        try {
          await storage.save(const {'key': secret});
        } on Object catch (error) {
          caught = error;
        }

        expect(caught, isA<SecureStorageWriteException>());
        expect('$caught', isNot(contains(secret)));
        expect(logs.join('\n'), isNot(contains(secret)));
        expect(files.bytesAt(primary), lastKnownGood);
      },
    );
  });

  test(
    'plugin operations retain upstream asynchronous serialization',
    () async {
      final mapStorage = _DelayedMapStorage();
      final target = windows.createFlutterSecureStorageWindows(
        MethodChannelFlutterSecureStorage(),
        mapStorage,
      );
      final options = <String, String>{'useBackwardCompatibility': 'false'};

      await Future.wait(<Future<void>>[
        for (var index = 0; index < 50; index++)
          target.write(
            key: 'key-$index',
            value: 'value-$index',
            options: options,
          ),
      ]);

      expect(mapStorage.values, hasLength(50));
      for (var index = 0; index < 50; index++) {
        expect(mapStorage.values['key-$index'], 'value-$index');
      }
    },
  );
}

final class _TestCodec implements SecureStorageCodec {
  static const _prefix = 0xA5;

  bool failProtect = false;
  String failureText = 'simulated codec failure';

  Uint8List protectRaw(String value, {bool encodeUtf8 = true}) {
    final bytes = encodeUtf8
        ? utf8.encode(value)
        : value.codeUnits.map((codeUnit) => codeUnit & 0xFF).toList();
    return Uint8List.fromList(<int>[
      _prefix,
      for (final byte in bytes) byte ^ 0x5A,
    ]);
  }

  @override
  Uint8List protect(Uint8List clearText) {
    if (failProtect) {
      throw StateError(failureText);
    }
    return Uint8List.fromList(<int>[
      _prefix,
      for (final byte in clearText) byte ^ 0x5A,
    ]);
  }

  @override
  Uint8List unprotect(Uint8List cipherText) {
    if (cipherText.isEmpty || cipherText.first != _prefix) {
      throw StateError(failureText);
    }
    return Uint8List.fromList(<int>[
      for (final byte in cipherText.skip(1)) byte ^ 0x5A,
    ]);
  }
}

final class _DelayedMapStorage extends windows.MapStorage {
  Map<String, String> values = <String, String>{};

  @override
  Future<void> clear(Map<String, String> options) async {
    await Future<void>.delayed(Duration.zero);
    values = <String, String>{};
  }

  @override
  Future<Map<String, String>> load(Map<String, String> options) async {
    await Future<void>.delayed(Duration.zero);
    return Map<String, String>.of(values);
  }

  @override
  Future<void> save(
    Map<String, String> data,
    Map<String, String> options,
  ) async {
    await Future<void>.delayed(Duration.zero);
    values = Map<String, String>.of(data);
  }
}

enum _ReplaceFailure {
  none,
  beforePrimaryReplacement,
  afterMovingPrimaryToBackup,
  partialThenRestoreFailure,
  beforeBackupReplacement,
}

final class _Replacement {
  const _Replacement({
    required this.temporaryPath,
    required this.destinationPath,
    required this.backupPath,
  });

  final String temporaryPath;
  final String destinationPath;
  final String? backupPath;
}

final class _MemoryFileOperations implements SecureStorageFileOperations {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Set<String> failReadPaths = <String>{};
  final Set<String> failDeletePaths = <String>{};
  final List<String> deletedPaths = <String>[];
  final List<String> writeAndFlushPaths = <String>[];
  final List<_Replacement> replacements = <_Replacement>[];

  _ReplaceFailure failure = _ReplaceFailure.none;
  var _nextTemporary = 0;
  var _restoreFailed = false;

  Iterable<String> get paths => _files.keys;

  void put(String filePath, Uint8List bytes) {
    _files[filePath] = Uint8List.fromList(bytes);
  }

  void move(String sourcePath, String destinationPath) {
    _files[destinationPath] = _files.remove(sourcePath)!;
  }

  Uint8List bytesAt(String filePath) => Uint8List.fromList(_files[filePath]!);

  bool existsSync(String filePath) => _files.containsKey(filePath);

  @override
  Future<String> createTemporaryFile(String destinationPath) async {
    final temporary = '$destinationPath.test-${_nextTemporary++}.tmp';
    _files[temporary] = Uint8List(0);
    return temporary;
  }

  @override
  Future<void> delete(String filePath) async {
    if (failDeletePaths.contains(filePath)) {
      throw StateError('simulated delete failure');
    }
    if (!_files.containsKey(filePath)) {
      throw StateError('missing test file');
    }
    deletedPaths.add(filePath);
    _files.remove(filePath);
  }

  @override
  Future<bool> exists(String filePath) async => _files.containsKey(filePath);

  @override
  Future<Uint8List> read(String filePath) async {
    if (failReadPaths.contains(filePath)) {
      throw StateError('simulated read failure');
    }
    final bytes = _files[filePath];
    if (bytes == null) {
      throw StateError('missing test file');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> replaceAtomically({
    required String temporaryPath,
    required String destinationPath,
    required String? backupPath,
  }) async {
    replacements.add(
      _Replacement(
        temporaryPath: temporaryPath,
        destinationPath: destinationPath,
        backupPath: backupPath,
      ),
    );
    if (path.dirname(temporaryPath) != path.dirname(destinationPath)) {
      throw StateError('temporary file used the wrong directory');
    }

    final isPrimaryReplacement = backupPath != null;
    if (failure == _ReplaceFailure.beforePrimaryReplacement &&
        isPrimaryReplacement) {
      failure = _ReplaceFailure.none;
      throw StateError('replacement failure with secret mnemonic');
    }
    if ((failure == _ReplaceFailure.afterMovingPrimaryToBackup ||
            failure == _ReplaceFailure.partialThenRestoreFailure) &&
        isPrimaryReplacement) {
      final current = _files.remove(destinationPath);
      if (current != null) {
        _files[backupPath] = current;
      }
      if (failure == _ReplaceFailure.afterMovingPrimaryToBackup) {
        failure = _ReplaceFailure.none;
      }
      throw StateError('partial replacement failure with secret mnemonic');
    }
    if (failure == _ReplaceFailure.partialThenRestoreFailure &&
        !isPrimaryReplacement &&
        destinationPath.endsWith('flutter_secure_storage.dat') &&
        !_restoreFailed) {
      _restoreFailed = true;
      failure = _ReplaceFailure.none;
      throw StateError('restore failure with secret mnemonic');
    }
    if (failure == _ReplaceFailure.beforeBackupReplacement &&
        destinationPath.endsWith('.bak')) {
      failure = _ReplaceFailure.none;
      throw StateError('backup refresh failure with secret mnemonic');
    }

    final replacement = _files.remove(temporaryPath);
    if (replacement == null) {
      throw StateError('missing replacement test file');
    }
    final current = _files[destinationPath];
    if (current != null && backupPath != null) {
      _files[backupPath] = Uint8List.fromList(current);
    }
    _files[destinationPath] = replacement;
  }

  @override
  Future<void> writeAndFlush(String filePath, Uint8List bytes) async {
    writeAndFlushPaths.add(filePath);
    _files[filePath] = Uint8List.fromList(bytes);
  }
}
