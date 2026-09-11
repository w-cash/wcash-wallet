import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/warden_form_factor.dart';
import '../theme/warden_theme.dart';

class WardenScaffold extends StatelessWidget {
  const WardenScaffold({required this.child, this.showBack = false, super.key});

  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(showBack: showBack),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(WardenLayout.pagePadding),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: WardenLayout.maxContentWidth,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showBack});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: WardenLayout.pagePadding,
        vertical: 14,
      ),
      child: Row(
        children: [
          if (showBack) ...[
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
          ],
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WardenColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'W',
              style: TextStyle(
                color: WardenColors.background,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Wcash Warden',
              style: TextStyle(
                color: WardenColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: WardenColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'TESTNET',
              style: TextStyle(
                color: WardenColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
