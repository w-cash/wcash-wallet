import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef WardenApplicationSupportLookup = Future<Directory> Function();

final class WardenApplicationSupportException implements Exception {
  const WardenApplicationSupportException();

  @override
  String toString() => 'The secure wallet data directory is unavailable.';
}

/// Resolves the operating system's app-scoped Application Support root.
///
/// Flutter supplies only this root to Rust. Rust owns the fixed Wcash Testnet
/// namespace and database filename below it; there is no user-selected path.
final class WardenApplicationSupport {
  const WardenApplicationSupport(this._lookup);

  factory WardenApplicationSupport.production() {
    return const WardenApplicationSupport(getApplicationSupportDirectory);
  }

  final WardenApplicationSupportLookup _lookup;

  Future<String> resolveRoot() async {
    try {
      final raw = (await _lookup()).path;
      if (raw.isEmpty || raw.contains('\u0000') || !path.isAbsolute(raw)) {
        throw const WardenApplicationSupportException();
      }

      final normalized = path.normalize(raw);
      if (normalized == path.rootPrefix(normalized)) {
        throw const WardenApplicationSupportException();
      }

      return normalized;
    } catch (_) {
      throw const WardenApplicationSupportException();
    }
  }
}

final wardenApplicationSupportProvider = Provider<WardenApplicationSupport>(
  (ref) => WardenApplicationSupport.production(),
);

final wardenApplicationSupportRootProvider = FutureProvider<String>(
  (ref) => ref.watch(wardenApplicationSupportProvider).resolveRoot(),
);
