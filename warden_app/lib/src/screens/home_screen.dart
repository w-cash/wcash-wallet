import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bridge/warden_bridge.dart';
import '../core/warden_form_factor.dart';
import '../rust/api.dart';
import '../theme/warden_theme.dart';
import '../widgets/warden_scaffold.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(networkIdentityProvider);
    final attestation = ref.watch(endpointAttestationProvider);

    return WardenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Text(
            'Wcash Testnet,\nkept deliberately separate.',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 18),
          Text(
            'A narrow Wcash wallet foundation with private Ironwood receiving, '
            'a transparent mining address, and a fixed attested network service.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: WardenColors.textMuted),
          ),
          SizedBox(height: WardenLayout.sectionGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = kWardenMobile || constraints.maxWidth < 760;
              final overview = _Overview(identity: identity);
              final service = _ServiceStatus(
                identity: identity,
                attestation: attestation,
              );
              if (stacked) {
                return Column(
                  children: [overview, const SizedBox(height: 16), service],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: overview),
                  const SizedBox(width: 16),
                  Expanded(child: service),
                ],
              );
            },
          ),
          SizedBox(height: WardenLayout.sectionGap),
          _MilestoneNotice(onPreview: () => context.push('/address-preview')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.identity});

  final WardenNetworkIdentity identity;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Network identity',
      child: Column(
        children: [
          _Detail(label: 'Network', value: identity.networkName),
          _Detail(label: 'Ticker', value: identity.ticker),
          _Detail(label: 'Precision', value: '${identity.decimals} decimals'),
          _Detail(label: 'Branch ID', value: identity.consensusBranchId),
          _Detail(
            label: 'Private prefix',
            value: identity.privateAddressPrefix,
          ),
          _Detail(label: 'Mining prefix', value: identity.miningAddressPrefix),
        ],
      ),
    );
  }
}

class _ServiceStatus extends ConsumerWidget {
  const _ServiceStatus({required this.identity, required this.attestation});

  final WardenNetworkIdentity identity;
  final AsyncValue<WardenEndpointAttestation> attestation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Panel(
      title: 'Wallet service',
      trailing: attestation.when(
        loading: () => const _StateLabel(label: 'CHECKING'),
        error: (_, _) => const _StateLabel(label: 'UNVERIFIED', error: true),
        data: (_) => const _StateLabel(label: 'ATTESTED'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            identity.endpoint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: WardenColors.text,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 18),
          attestation.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The fixed service did not pass chain attestation.',
                  style: TextStyle(color: WardenColors.error),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => ref.invalidate(endpointAttestationProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check again'),
                ),
              ],
            ),
            data: (data) => Column(
              children: [
                _Detail(label: 'Chain tip', value: '${data.tipHeight}'),
                _Detail(label: 'Tip hash', value: _compact(data.tipHash)),
                _Detail(label: 'Genesis', value: _compact(data.genesisHash)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _compact(String value) {
    if (value.length <= 22) return value;
    return '${value.substring(0, 10)}…${value.substring(value.length - 10)}';
  }
}

class _MilestoneNotice extends StatelessWidget {
  const _MilestoneNotice({required this.onPreview});

  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: WardenColors.accentMuted,
        borderRadius: BorderRadius.circular(WardenLayout.cardRadius),
        border: Border.all(color: const Color(0xFF2F6436)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foundation milestone',
                  style: TextStyle(
                    color: WardenColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'This build verifies Wcash identity and previews deterministic '
                  'receive addresses. It does not persist a wallet, synchronize '
                  'balances, or send transactions yet.',
                  style: TextStyle(color: WardenColors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onPreview,
            child: const Text('Preview receive addresses'),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: WardenColors.surface,
        borderRadius: BorderRadius.circular(WardenLayout.cardRadius),
        border: Border.all(color: WardenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: WardenColors.text,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: error ? WardenColors.error : WardenColors.accent,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
