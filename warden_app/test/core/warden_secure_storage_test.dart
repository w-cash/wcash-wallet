import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcash_warden/src/core/product_identity.dart';
import 'package:wcash_warden/src/core/storage/warden_application_support.dart';
import 'package:wcash_warden/src/core/storage/warden_secure_storage.dart';

void main() {
  group('Warden mnemonic storage', () {
    test('writes, verifies, reads, and verifies deletion', () async {
      final backend = _MemorySecureStoreBackend();
      final store = WardenMnemonicStore(backend);

      await store.writeMnemonic(_validMnemonic);

      expect(await store.readMnemonic(), _validMnemonic);
      expect(backend.writes, 1);
      expect(backend.reads, 2);

      await store.deleteMnemonic();

      expect(await store.readMnemonic(), isNull);
      expect(backend.deletes, 1);
    });

    test('removes an unverifiable write and reports no secret', () async {
      final backend = _MemorySecureStoreBackend(readOverride: 'mismatch');
      final store = WardenMnemonicStore(backend);

      final error = await _captureError(
        () => store.writeMnemonic(_validMnemonic),
      );

      expect(error, isA<WardenSecureStorageException>());
      expect(error.toString(), contains('could not be verified'));
      expect(error.toString(), isNot(contains(_validMnemonic)));
      expect(backend.deletes, 1);
      expect(backend.value, isNull);
    });

    test('does not expose a platform write error or mnemonic', () async {
      final backend = _MemorySecureStoreBackend(
        writeError: StateError('write failed for $_validMnemonic'),
      );
      final store = WardenMnemonicStore(backend);

      final error = await _captureError(
        () => store.writeMnemonic(_validMnemonic),
      );

      expect(
        error.toString(),
        'Secure wallet recovery phrase could not be stored.',
      );
      expect(error.toString(), isNot(contains('write failed')));
      expect(error.toString(), isNot(contains(_validMnemonic)));
    });

    test('fails closed when a stored mnemonic cannot be read', () async {
      final backend = _MemorySecureStoreBackend(
        readError: StateError('secret platform detail'),
      );
      final store = WardenMnemonicStore(backend);

      final error = await _captureError(store.readMnemonic);

      expect(
        error.toString(),
        'Secure wallet recovery phrase could not be read.',
      );
      expect(error.toString(), isNot(contains('platform detail')));
    });

    test('fails closed when deletion cannot be verified', () async {
      final backend = _MemorySecureStoreBackend(
        initialValue: _validMnemonic,
        preserveOnDelete: true,
      );
      final store = WardenMnemonicStore(backend);

      final error = await _captureError(store.deleteMnemonic);

      expect(
        error.toString(),
        'Secure wallet recovery phrase could not be removed.',
      );
      expect(error.toString(), isNot(contains(_validMnemonic)));
    });

    test('does not expose a platform deletion error', () async {
      final backend = _MemorySecureStoreBackend(
        initialValue: _validMnemonic,
        deleteError: StateError('delete failed for $_validMnemonic'),
      );
      final store = WardenMnemonicStore(backend);

      final error = await _captureError(store.deleteMnemonic);

      expect(
        error.toString(),
        'Secure wallet recovery phrase could not be removed.',
      );
      expect(error.toString(), isNot(contains('delete failed')));
      expect(error.toString(), isNot(contains(_validMnemonic)));
    });

    test('uses isolated, non-migrating Apple and Android options', () {
      expect(
        wardenIosSecureStorageOptions.toMap(),
        containsPair('accountName', WardenProductIdentity.secureStorageScope),
      );
      expect(
        wardenIosSecureStorageOptions.toMap(),
        containsPair('accessibility', 'unlocked_this_device'),
      );
      expect(
        wardenIosSecureStorageOptions.toMap(),
        containsPair('synchronizable', 'false'),
      );
      expect(
        wardenMacOsSecureStorageOptions.toMap(),
        containsPair('accessibility', 'unlocked_this_device'),
      );
      expect(
        wardenMacOsSecureStorageOptions.toMap(),
        containsPair('synchronizable', 'false'),
      );
      expect(
        wardenAndroidSecureStorageOptions.toMap(),
        containsPair(
          'sharedPreferencesName',
          WardenProductIdentity.secureStorageScope,
        ),
      );
      expect(
        wardenAndroidSecureStorageOptions.toMap(),
        containsPair('resetOnError', 'false'),
      );
      expect(LinuxOptions.defaultOptions.toMap(), isEmpty);
      expect(
        WindowsOptions.defaultOptions.toMap(),
        containsPair('useBackwardCompatibility', 'false'),
      );
    });
  });

  group('Warden Application Support root', () {
    test('normalizes an injected absolute Application Support path', () async {
      final locator = WardenApplicationSupport(
        () async => Directory('/tmp/wcash/../wcash/application-support'),
      );

      expect(await locator.resolveRoot(), '/tmp/wcash/application-support');
    });

    test(
      'rejects relative and filesystem-root paths without details',
      () async {
        for (final path in <String>['relative/path', '/']) {
          final locator = WardenApplicationSupport(() async => Directory(path));
          final error = await _captureError(locator.resolveRoot);
          expect(
            error.toString(),
            'The secure wallet data directory is unavailable.',
          );
          expect(error.toString(), isNot(contains(path)));
        }
      },
    );
  });

  testWidgets('secure-store provider accepts an injected backend', (
    tester,
  ) async {
    final backend = _MemorySecureStoreBackend();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardenSecureStoreBackendProvider.overrideWithValue(backend),
        ],
        child: const MaterialApp(home: _SecureStorageProbe()),
      ),
    );

    await tester.tap(find.byKey(const Key('store-mnemonic')));
    await tester.pumpAndSettle();

    expect(find.text('Stored securely'), findsOneWidget);
    expect(find.textContaining(_validMnemonic), findsNothing);
    expect(backend.value, _validMnemonic);
  });
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

Future<Object> _captureError<T>(Future<T> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  throw StateError('expected action to fail');
}

final class _MemorySecureStoreBackend implements WardenSecureStoreBackend {
  _MemorySecureStoreBackend({
    String? initialValue,
    this.readOverride,
    this.writeError,
    this.readError,
    this.deleteError,
    this.preserveOnDelete = false,
  }) : value = initialValue;

  String? value;
  final String? readOverride;
  final Object? writeError;
  final Object? readError;
  final Object? deleteError;
  final bool preserveOnDelete;
  int writes = 0;
  int reads = 0;
  int deletes = 0;

  @override
  Future<void> write({required String key, required String value}) async {
    writes += 1;
    if (writeError case final error?) throw error;
    expect(key, WardenMnemonicStore.mnemonicKey);
    this.value = value;
  }

  @override
  Future<String?> read({required String key}) async {
    reads += 1;
    if (readError case final error?) throw error;
    expect(key, WardenMnemonicStore.mnemonicKey);
    return readOverride ?? value;
  }

  @override
  Future<void> delete({required String key}) async {
    deletes += 1;
    if (deleteError case final error?) throw error;
    expect(key, WardenMnemonicStore.mnemonicKey);
    if (!preserveOnDelete) value = null;
  }
}

final class _SecureStorageProbe extends ConsumerStatefulWidget {
  const _SecureStorageProbe();

  @override
  ConsumerState<_SecureStorageProbe> createState() =>
      _SecureStorageProbeState();
}

final class _SecureStorageProbeState
    extends ConsumerState<_SecureStorageProbe> {
  bool _stored = false;

  Future<void> _store() async {
    final store = ref.read(wardenMnemonicStoreProvider);
    await store.writeMnemonic(_validMnemonic);
    final present = await store.readMnemonic() != null;
    if (mounted) setState(() => _stored = present);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(_stored ? 'Stored securely' : 'Not stored'),
          FilledButton(
            key: const Key('store-mnemonic'),
            onPressed: _store,
            child: const Text('Store'),
          ),
        ],
      ),
    );
  }
}
