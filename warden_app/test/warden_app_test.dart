import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcash_warden/src/app.dart';
import 'package:wcash_warden/src/bridge/warden_bridge.dart';
import 'package:wcash_warden/src/core/product_identity.dart';
import 'package:wcash_warden/src/rust/api.dart';

void main() {
  setUp(() => wardenRouter.go('/'));

  test('product identity is isolated to Wcash Testnet', () {
    expect(
      WardenProductIdentity.applicationId,
      'com.wcashwallet.warden.testnet',
    );
    expect(WardenProductIdentity.executableName, 'wcash-warden-testnet');
    expect(
      WardenProductIdentity.databaseFileName,
      'wcash-warden-wcashtestnet-v5.sqlite3',
    );
    expect(WardenProductIdentity.walletStorageNamespace, 'wcashtestnet-v5');
    expect(
      WardenProductIdentity.secureStorageScope,
      'com.wcashwallet.warden.testnet.secure-store',
    );
    expect(
      WardenProductIdentity.mnemonicStorageKey,
      'com.wcashwallet.warden.testnet.secure-store.mnemonic.v1',
    );
  });

  testWidgets('shows the frozen network and attested service', (tester) async {
    await _pump(tester, const _FakeBridge());
    await tester.pumpAndSettle();

    expect(find.text('Wcash Warden'), findsOneWidget);
    expect(find.text('TESTNET'), findsOneWidget);
    expect(find.text('TWC'), findsOneWidget);
    expect(find.text('ATTESTED'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(
      find.text('https://wallet-testnet.wcashexplorer.com'),
      findsOneWidget,
    );
  });

  testWidgets('derives Wcash addresses and clears the phrase field', (
    tester,
  ) async {
    await _pump(tester, const _FakeBridge());
    await tester.pumpAndSettle();
    final previewButton = find.text('Preview receive addresses');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    const phrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon about';
    await tester.enterText(find.byKey(const Key('mnemonic-field')), phrase);
    await tester.tap(find.byKey(const Key('derive-addresses')));
    await tester.pumpAndSettle();

    expect(find.text('wutest1private'), findsOneWidget);
    expect(find.text('WTMiningAddress'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('mnemonic-field')),
    );
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('rejects malformed input before entering the native bridge', (
    tester,
  ) async {
    final bridge = _FakeBridgeWithCallCount();
    await _pump(tester, bridge);
    await tester.pumpAndSettle();
    final previewButton = find.text('Preview receive addresses');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('mnemonic-field')),
      'not enough words',
    );
    await tester.tap(find.byKey(const Key('derive-addresses')));
    await tester.pump();

    expect(bridge.deriveCalls, 0);
    expect(find.textContaining('12, 15, 18, 21, or 24-word'), findsOneWidget);
  });

  testWidgets('distinguishes native bridge failure from invalid input', (
    tester,
  ) async {
    await _pump(tester, const _FailingDerivationBridge());
    await tester.pumpAndSettle();
    final previewButton = find.text('Preview receive addresses');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    const phrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon about';
    await tester.enterText(find.byKey(const Key('mnemonic-field')), phrase);
    await tester.tap(find.byKey(const Key('derive-addresses')));
    await tester.pump();

    expect(
      find.text('Address derivation failed inside the Wcash Testnet bridge.'),
      findsOneWidget,
    );
  });

  testWidgets('reports a checksummed mnemonic rejection precisely', (
    tester,
  ) async {
    await _pump(tester, const _InvalidMnemonicBridge());
    await tester.pumpAndSettle();
    final previewButton = find.text('Preview receive addresses');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    const phrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon';
    await tester.enterText(find.byKey(const Key('mnemonic-field')), phrase);
    await tester.tap(find.byKey(const Key('derive-addresses')));
    await tester.pump();

    expect(
      find.textContaining('not a valid checksummed English BIP-39 phrase'),
      findsOneWidget,
    );
  });

  testWidgets(
    'reports endpoint attestation failure without alternate endpoint',
    (tester) async {
      await _pump(tester, const _FakeBridge(attestationFails: true));
      await tester.pumpAndSettle();

      expect(find.text('UNVERIFIED'), findsOneWidget);
      expect(
        find.text('The fixed service did not pass chain attestation.'),
        findsOneWidget,
      );
      expect(find.textContaining('custom'), findsNothing);
    },
  );
}

class _FakeBridgeWithCallCount extends _FakeBridge {
  int deriveCalls = 0;

  @override
  WardenAddresses deriveAddresses(String mnemonic) {
    deriveCalls += 1;
    return super.deriveAddresses(mnemonic);
  }
}

class _FailingDerivationBridge extends _FakeBridge {
  const _FailingDerivationBridge();

  @override
  WardenAddresses deriveAddresses(String mnemonic) {
    throw StateError('native bridge unavailable');
  }
}

class _InvalidMnemonicBridge extends _FakeBridge {
  const _InvalidMnemonicBridge();

  @override
  WardenAddresses deriveAddresses(String mnemonic) {
    throw ArgumentError('invalid English BIP-39 mnemonic');
  }
}

Future<void> _pump(WidgetTester tester, WardenBridge bridge) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [wardenBridgeProvider.overrideWithValue(bridge)],
      child: const WardenApp(),
    ),
  );
}

class _FakeBridge implements WardenBridge {
  const _FakeBridge({this.attestationFails = false});

  final bool attestationFails;

  @override
  WardenNetworkIdentity networkIdentity() => const WardenNetworkIdentity(
    networkName: 'Wcash Testnet',
    rpcChainName: 'test',
    ticker: 'TWC',
    decimals: 8,
    endpoint: 'https://wallet-testnet.wcashexplorer.com',
    consensusBranchId: 'b3cfd27e',
    genesisHash:
        '0271b5b0a10b2838f43cccdec9ca2f72aa72a7c103830082bac8f82f47f0593a',
    storageNamespace: 'wcashtestnet-v5',
    privateAddressPrefix: 'wutest1',
    miningAddressPrefix: 'WT',
  );

  @override
  Future<WardenEndpointAttestation> attestEndpoint() async {
    if (attestationFails) throw StateError('untrusted endpoint');
    return const WardenEndpointAttestation(
      endpoint: 'https://wallet-testnet.wcashexplorer.com',
      networkName: 'Wcash Testnet',
      consensusBranchId: 'b3cfd27e',
      genesisHash:
          '0271b5b0a10b2838f43cccdec9ca2f72aa72a7c103830082bac8f82f47f0593a',
      tipHeight: 48,
      tipHash:
          'b9752b654a180cab397e18978660a1080190f3e5690964f3c1aa54ce18e298eb',
    );
  }

  @override
  WardenAddresses deriveAddresses(String mnemonic) {
    if (!mnemonic.endsWith('about')) throw ArgumentError('invalid phrase');
    return const WardenAddresses(
      accountIndex: 0,
      privateReceiveAddress: 'wutest1private',
      transparentMiningAddress: 'WTMiningAddress',
    );
  }
}
