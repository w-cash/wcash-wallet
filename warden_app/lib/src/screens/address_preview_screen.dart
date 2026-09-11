import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../bridge/warden_bridge.dart';
import '../rust/api.dart';
import '../theme/warden_theme.dart';
import '../widgets/warden_scaffold.dart';

class AddressPreviewScreen extends ConsumerStatefulWidget {
  const AddressPreviewScreen({super.key});

  @override
  ConsumerState<AddressPreviewScreen> createState() =>
      _AddressPreviewScreenState();
}

class _AddressPreviewScreenState extends ConsumerState<AddressPreviewScreen> {
  final _mnemonicController = TextEditingController();
  WardenAddresses? _addresses;
  String? _error;
  bool _obscurePhrase = true;

  @override
  void dispose() {
    _mnemonicController.clear();
    _mnemonicController.dispose();
    super.dispose();
  }

  void _derive() {
    final rawPhrase = _mnemonicController.text.trim();
    if (rawPhrase.length > 512 || utf8.encode(rawPhrase).length > 512) {
      _rejectInput('The recovery phrase is too long.');
      return;
    }
    if (rawPhrase.isNotEmpty && !RegExp(r'^[a-zA-Z\s]+$').hasMatch(rawPhrase)) {
      _rejectInput('Use English BIP-39 words and spaces only.');
      return;
    }

    final phrase = rawPhrase.toLowerCase().split(RegExp(r'\s+')).join(' ');
    final wordCount = phrase.isEmpty ? 0 : phrase.split(' ').length;
    if (!const {12, 15, 18, 21, 24}.contains(wordCount)) {
      _rejectInput('Enter a 12, 15, 18, 21, or 24-word English BIP-39 phrase.');
      return;
    }

    try {
      final addresses = ref.read(wardenBridgeProvider).deriveAddresses(phrase);
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      final invalidMnemonic = error.toString().contains(
        'invalid English BIP-39 mnemonic',
      );
      setState(() {
        _addresses = null;
        _error = invalidMnemonic
            ? 'The recovery phrase is not a valid checksummed English BIP-39 phrase.'
            : 'Address derivation failed inside the Wcash Testnet bridge.';
      });
    } finally {
      _mnemonicController.clear();
    }
  }

  void _rejectInput(String message) {
    _mnemonicController.clear();
    setState(() {
      _addresses = null;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WardenScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Text(
            'Address preview',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Derive Wcash Testnet account 0 addresses without saving wallet state.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: WardenColors.textMuted),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: WardenColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: WardenColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recovery phrase',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Testnet integration preview only. Do not enter a phrase that '
                  'protects real funds. The app does not save it, and this field '
                  'is cleared after each attempt.',
                  style: TextStyle(color: WardenColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('mnemonic-field'),
                  controller: _mnemonicController,
                  obscureText: _obscurePhrase,
                  maxLines: 1,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    hintText: 'Enter 12, 15, 18, 21, or 24 words',
                    errorText: _error,
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePhrase = !_obscurePhrase),
                      icon: Icon(
                        _obscurePhrase
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _obscurePhrase ? 'Show phrase' : 'Hide phrase',
                    ),
                  ),
                  onSubmitted: (_) => _derive(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('derive-addresses'),
                  onPressed: _derive,
                  child: const Text('Derive addresses'),
                ),
              ],
            ),
          ),
          if (_addresses case final addresses?) ...[
            const SizedBox(height: 20),
            _AddressResult(addresses: addresses),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AddressResult extends StatelessWidget {
  const _AddressResult({required this.addresses});

  final WardenAddresses addresses;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: WardenColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WardenColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final qr = Container(
            width: 188,
            height: 188,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: PrettyQrView.data(
              data: addresses.privateReceiveAddress,
              decoration: const PrettyQrDecoration(
                quietZone: PrettyQrQuietZone.modules(4),
                shape: PrettyQrSquaresSymbol(color: Colors.black),
              ),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Wcash Unified Address',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Orchard receiver for private Ironwood payouts',
                style: TextStyle(color: WardenColors.textMuted),
              ),
              const SizedBox(height: 8),
              SelectableText(
                addresses.privateReceiveAddress,
                key: const Key('private-address'),
                style: const TextStyle(
                  color: WardenColors.text,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Transparent mining address',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                addresses.transparentMiningAddress,
                key: const Key('mining-address'),
                style: const TextStyle(
                  color: WardenColors.text,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: qr),
                const SizedBox(height: 22),
                details,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qr,
              const SizedBox(width: 24),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}
