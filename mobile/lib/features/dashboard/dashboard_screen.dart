import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/kasa_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import 'needs_attention.dart';
import 'setup_checklist.dart';
import 'tenant_home.dart';

const _storage = FlutterSecureStorage();

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/payments/dashboard/');
  return resp.data as Map<String, dynamic>;
});

/// Unread notifications, for the bell badge.
///
/// WHY it needed a provider at all: the badge used to be drawn unconditionally,
/// so every user was permanently told they had something waiting and no amount
/// of reading could clear it.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/notifications/unread-count/');
  return (resp.data['unread'] as num?)?.toInt() ?? 0;
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _userName;

  @override
  void initState() {
    super.initState();
    _storage.read(key: 'user_name').then((v) {
      if (mounted) setState(() => _userName = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(dashboardProvider);
    final cs = Theme.of(context).colorScheme;
    final home = stats.valueOrNull;
    final owed = toDouble(home?['outstanding_balance']);
    // Only where a prompt can actually be sent: behind a shared bank paybill
    // the paybill and account on Home are the way to pay.
    final canPrompt = ref.watch(userRoleProvider).valueOrNull == 'tenant' &&
        home?['stk_enabled'] == true &&
        owed > 0;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: KasaHomeAppBar(
        name: _userName ?? '',
        onProfile: () => context.push('/profile'),
      ),
      bottomNavigationBar: canPrompt
          ? KasaActionBar(children: [
              KasaButton(
                label: 'Pay ${formatCurrency(owed)} with M-Pesa',
                leading: Icon(Icons.phone_android_rounded, size: 20, color: cs.onPrimary),
                onTap: () => context.go('/invoices'),
              ),
            ])
          : null,
      body: stats.when(
        loading: () => const KasaSkeletonSummary(),
        error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(dashboardProvider)),
        data: (data) {
          // WHY the role and not the payload shape: landlords and caretakers
          // used to get the same payload, so keying off it showed caretakers
          // a landlord's screen.
          final role = ref.watch(userRoleProvider).valueOrNull;
          final Widget body = switch (role) {
            'caretaker' => _CaretakerHome(data: data),
            'tenant' => TenantHome(data: data),
            _ => _LandlordHome(data: data),
          };
          return RefreshIndicator(
            onRefresh: () => ref.refresh(dashboardProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [body],
            ),
          );
        },
      ),
    );
  }
}

// Landlord

/// This month's money at a glance, then everything waiting on the landlord.
class _LandlordHome extends StatelessWidget {
  const _LandlordHome({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final expected = toDouble(data['expected_this_month_kes']);
    final collected = toDouble(data['collected_against_expected_kes']);
    final arrears = toDouble(data['overdue_amount_kes']);
    final overdueCount = (data['overdue_invoices'] as num?)?.toInt() ?? 0;
    final total = (data['total_units'] as num?)?.toInt() ?? 0;
    final occupied = (data['occupied_units'] as num?)?.toInt() ?? 0;
    // Nothing billed yet this month is not the same as nothing collected.
    final share = expected > 0 ? (collected / expected).clamp(0.0, 1.0) : null;
    final month = DateFormat('MMMM').format(DateTime.now());
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetupChecklist(totalUnits: total),
        KasaCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('Collected \u00b7 $month', style: muted)),
                if (share != null) Text('${(share * 100).round()}%', style: muted),
              ]),
              const SizedBox(height: 16),
              Text(formatCurrency(collected), style: KasaType.moneyXl.copyWith(color: cs.onSurface)),
              const SizedBox(height: 4),
              Text(
                expected > 0
                    ? 'of ${formatCurrency(expected)} expected'
                    : 'No bills raised yet this month',
                style: muted,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(KasaRadius.pill),
                child: LinearProgressIndicator(
                  value: share ?? 0,
                  minHeight: 8,
                  backgroundColor: cs.kasaElev,
                  color: cs.statusPaid,
                  semanticsLabel: 'Share of this month collected',
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: cs.kasaStroke),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => context.go('/invoices'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Arrears', style: muted),
                            const SizedBox(height: 4),
                            Text(formatCurrency(arrears),
                                style: KasaType.moneyL.copyWith(
                                    color: arrears > 0 ? cs.statusOverdue : cs.onSurface)),
                          ],
                        ),
                      ),
                    ),
                    VerticalDivider(width: 33, color: cs.kasaStroke),
                    Expanded(
                      child: InkWell(
                        onTap: () => context.go('/properties'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Occupancy', style: muted),
                            const SizedBox(height: 4),
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '$occupied/$total',
                                  style: KasaType.moneyL.copyWith(color: cs.onSurface)),
                              TextSpan(text: ' occupied', style: muted),
                            ])),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        NeedsAttentionSection(
          canSeeMoney: true,
          overdueCount: overdueCount,
          overdueAmount: arrears,
        ),
      ],
    );
  }
}

// Caretaker

/// A caretaker's day: meters, repairs, people moving. Never money: the
/// server does not send it to them.
class _CaretakerHome extends StatelessWidget {
  const _CaretakerHome({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final readingsLeft = (data['readings_left'] as num?)?.toInt() ?? 0;
    final openRepairs = (data['open_repairs'] as num?)?.toInt() ?? 0;
    final vacant = (data['vacant_units'] as num?)?.toInt() ?? 0;
    final movingOut = (data['moving_out'] as List? ?? []).cast<Map<String, dynamic>>();
    final arriving = (data['arriving'] as List? ?? []).cast<Map<String, dynamic>>();
    final day = DateFormat('EEEE d MMM').format(DateTime.now());

    String when(Object? iso) {
      final d = DateTime.tryParse('$iso');
      return d == null ? '' : DateFormat('d MMM').format(d);
    }

    Widget count(int n, String label, VoidCallback onTap) => Expanded(
          child: KasaCard(
            padding: const EdgeInsets.all(16),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$n', style: KasaType.moneyL.copyWith(color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(label, style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
              ],
            ),
          ),
        );

    final todo = <Widget>[
      if (readingsLeft > 0)
        KasaListRow(
          leading: const KasaLeadIcon(Icons.speed_rounded),
          title: 'Read water meters',
          subtitle: '$readingsLeft still to read this month',
          onTap: () => context.go('/readings'),
        ),
      if (openRepairs > 0)
        KasaListRow(
          leading: const KasaLeadIcon(Icons.build_outlined, tone: KasaStatusKind.due),
          title: openRepairs == 1 ? '1 repair open' : '$openRepairs repairs open',
          subtitle: 'Update each one as it progresses',
          onTap: () => context.go('/maintenance'),
        ),
      for (final m in movingOut)
        KasaListRow(
          leading: const KasaLeadIcon(Icons.door_front_door_outlined, tone: KasaStatusKind.notice),
          title: 'Move-out inspection',
          subtitle: '${m['unit']} \u00b7 ${m['tenant']} \u00b7 leaves ${when(m['date'])}',
        ),
      for (final a in arriving)
        KasaListRow(
          leading: const KasaLeadIcon(Icons.people_outline_rounded),
          title: 'New tenant arriving',
          subtitle: '${a['unit']} \u00b7 ${a['tenant']} \u00b7 ${when(a['date'])}',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Today',
            style: KasaFont.sans(fontSize: 28, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text(day, style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
        const SizedBox(height: 20),
        Row(children: [
          count(readingsLeft, 'Readings left', () => context.go('/readings')),
          const SizedBox(width: 8),
          count(openRepairs, 'Open repairs', () => context.go('/maintenance')),
          const SizedBox(width: 8),
          count(vacant, vacant == 1 ? 'Vacant unit' : 'Vacant units', () => context.go('/properties')),
        ]),
        const SizedBox(height: 20),
        KasaSectionHeader('To do',
            trailing: Text('${todo.length}',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))),
        const SizedBox(height: 12),
        if (todo.isEmpty)
          Text('Nothing waiting. Meters are read and repairs are closed.',
              style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))
        else
          KasaListGroup(children: todo),
      ],
    );
  }
}

// ─── Error state ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: cs.kasaTextSub),
            const SizedBox(height: 16),
            Text(
              'Could not load dashboard',
              style: KasaFont.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again.',
              style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
            ),
            const SizedBox(height: 24),
            KasaButton(label: 'Retry', onTap: onRetry, variant: KasaButtonVariant.secondary),
          ],
        ),
      ),
    );
  }
}
