import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/api.dart' as rust;

abstract interface class WardenBridge {
  rust.WardenNetworkIdentity networkIdentity();

  Future<rust.WardenEndpointAttestation> attestEndpoint();

  rust.WardenAddresses deriveAddresses(String mnemonic);
}

class NativeWardenBridge implements WardenBridge {
  const NativeWardenBridge();

  @override
  rust.WardenNetworkIdentity networkIdentity() => rust.networkIdentity();

  @override
  Future<rust.WardenEndpointAttestation> attestEndpoint() =>
      rust.attestEndpoint();

  @override
  rust.WardenAddresses deriveAddresses(String mnemonic) =>
      rust.deriveAddresses(mnemonic: mnemonic, accountIndex: 0);
}

final wardenBridgeProvider = Provider<WardenBridge>(
  (ref) => const NativeWardenBridge(),
);

final networkIdentityProvider = Provider<rust.WardenNetworkIdentity>(
  (ref) => ref.watch(wardenBridgeProvider).networkIdentity(),
);

final endpointAttestationProvider =
    FutureProvider<rust.WardenEndpointAttestation>(
      (ref) => ref.watch(wardenBridgeProvider).attestEndpoint(),
    );
