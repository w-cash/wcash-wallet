import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/address_preview_screen.dart';
import 'screens/home_screen.dart';
import 'theme/warden_theme.dart';

final GoRouter wardenRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/address-preview',
      builder: (context, state) => const AddressPreviewScreen(),
    ),
  ],
);

class WardenApp extends StatelessWidget {
  const WardenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Wcash Warden Testnet',
      debugShowCheckedModeBanner: false,
      theme: buildWardenTheme(),
      routerConfig: wardenRouter,
    );
  }
}
