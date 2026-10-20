import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../payments/payment_methods_screen.dart';
import '../properties/properties_screen.dart';
import 'dashboard_screen.dart';

/// What a new landlord still has to do before Kasa can bill anyone: add a
/// building with its units, and say how tenants pay.
///
/// Each step is read from what exists, not from a flag, so it is right however
/// the landlord got there, and it disappears once both are done.
class SetupChecklist extends ConsumerWidget {
  const SetupChecklist({super.key, required this.totalUnits});

  /// From the dashboard: units across all the landlord's buildings.
  final int totalUnits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull;
    // Unknown until loaded: say nothing rather than flash a step as undone.
    if (accounts == null) return const SizedBox.shrink();

    final hasBuilding = totalUnits > 0;
    final hasPayment = accounts.isNotEmpty;
    if (hasBuilding && hasPayment) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final done = [hasBuilding, hasPayment].where((d) => d).length;

    Future<void> addBuilding() async {
      await openAddProperty(context, ref);
      // The dashboard's unit count is what ticks this step.
      ref.invalidate(dashboardProvider);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KasaSectionHeader(
            'Get set up',
            trailing: Text('$done of 2 done',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)
                    .copyWith(fontFeatures: KasaType.tabular)),
          ),
          const SizedBox(height: 12),
          KasaListGroup(children: [
            _Step(
              done: hasBuilding,
              icon: Icons.apartment_rounded,
              title: 'Add your building',
              subtitle: 'Its house numbers, rent, deposit and bills like water',
              onTap: hasBuilding ? () => context.go('/properties') : addBuilding,
            ),
            _Step(
              done: hasPayment,
              icon: Icons.account_balance_wallet_outlined,
              title: 'Say how tenants pay',
              subtitle: 'Your paybill, till, bank account or cash',
              onTap: () => context.push('/payment-methods'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.done,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool done;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KasaListRow(
      leading: KasaLeadIcon(done ? Icons.check_rounded : icon, tone: done ? KasaStatusKind.paid : null),
      title: title,
      subtitle: done ? 'Done' : subtitle,
      trailing: done ? const KasaStatusChip(kind: KasaStatusKind.paid, label: 'Done') : null,
      onTap: onTap,
    );
  }
}
