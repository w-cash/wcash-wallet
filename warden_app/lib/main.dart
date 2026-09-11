import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/warden_form_factor.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assertValidWardenFormFactor();
  await WardenRust.init();
  runApp(const ProviderScope(child: WardenApp()));
}
