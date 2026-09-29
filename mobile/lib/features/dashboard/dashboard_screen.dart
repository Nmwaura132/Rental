import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/kasa_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import 'needs_attention.dart';

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

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: KasaHomeAppBar(
        name: _userName ?? '',
        onProfile: () => context.push('/profile'),
      ),
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
            'tenant' => _TenantBento(data: data, cs: cs),
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

// ─── Header ───────────────────────────────────────────────────────────────────
// ─── Landlord Bento ───────────────────────────────────────────────────────────
// ─── Tenant Bento ─────────────────────────────────────────────────────────────

class _TenantBento extends StatelessWidget {
  const _TenantBento({required this.data, required this.cs});
  final Map<String, dynamic> data;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final outstanding = toDouble(data['outstanding_balance']);
    final dueAmt = toDouble(data['next_due_amount'] ?? data['monthly_rent'] ?? 0);
    final dueDate = _parseDate(data['next_due_date']);
    final tenancyEnd = _parseDate(data['tenancy_end']);
    final now = DateTime.now();
    final daysUntilDue = dueDate?.difference(now).inDays;
    final daysUntilTenancy = tenancyEnd?.difference(now).inDays;
    final tenancyPct = (tenancyEnd != null && data['tenancy_start'] != null)
        ? () {
            final start = _parseDate(data['tenancy_start'])!;
            final total = tenancyEnd.difference(start).inDays;
            final elapsed = now.difference(start).inDays;
            return (elapsed / total).clamp(0.0, 1.0);
          }()
        : 0.68;
    final dueDateLabel = dueDate != null
        ? DateFormat('d MMM yyyy').format(dueDate)
        : 'Next due date';

    return Column(
      // Stretch so the hero card fills the width like every row below
      // it. A Column centres by default, which sized the hero to its
      // own text — leaving dead space that changed with the figure.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero: Rent Due ──
        KasaCard(
          accent: KasaCardAccent.primary,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('Rent due · $dueDateLabel'),
              const SizedBox(height: 10),
              Text(
                outstanding > 0 ? formatCurrency(outstanding) : formatCurrency(dueAmt),
                style: KasaFont.sans(
                  fontSize: 60,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.44,
                  color: cs.onPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              if (daysUntilDue != null)
                _TrendChip(
                  label: daysUntilDue > 0 ? '$daysUntilDue DAYS LEFT' : 'Overdue',
                  onPrimary: cs.onPrimary,
                  primary: cs.primary,
                ),
              const SizedBox(height: 16),
              KasaButton(
                label: 'Pay with M-Pesa',
                onTap: () => context.go('/invoices'),
                variant: KasaButtonVariant.ghost,
                leading: Icon(Icons.phone_android, size: 16, color: cs.onPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── 2-col: Tenancy countdown + Tickets ──
        Row(
          children: [
            Expanded(
              child: KasaCard(
                accent: KasaCardAccent.secondary,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // WHY the open-ended case gets its own wording: most Kenyan
                    // tenancies have no agreed end date, and the countdown then
                    // rendered as "TENANCY ENDS / — / DAYS", which reads as
                    // missing data rather than the normal state it is.
                    _Label(
                      tenancyEnd != null ? 'Tenancy ends' : 'Tenancy',
                      ink: cs.onSecondary.withValues(alpha: 0.75),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tenancyEnd != null ? '${daysUntilTenancy ?? 0}' : 'OPEN',
                      style: KasaFont.sans(
                        fontSize: tenancyEnd != null ? 52 : 34,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.56,
                        color: cs.onSecondary,
                        height: 1,
                      ),
                    ),
                    Text(
                      tenancyEnd != null
                          ? 'days · ${DateFormat('d MMM yyyy').format(tenancyEnd)}'
                          : 'No end date agreed',
                      style: KasaFont.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: cs.onSecondary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: cs.kasaStroke, width: 1.5),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: tenancyPct,
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.onSecondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _NoticeAction(data: data),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: KasaCard(
                accent: KasaCardAccent.tertiary,
                padding: const EdgeInsets.all(18),
                onTap: () => context.go('/maintenance'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Tickets', ink: cs.tertiaryInk.withValues(alpha: 0.75)),
                    const SizedBox(height: 8),
                    Text(
                      '${data['open_tickets'] ?? 0}',
                      style: KasaFont.sans(
                        fontSize: 52,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.56,
                        color: cs.tertiaryInk,
                        height: 1,
                      ),
                    ),
                    Text(
                      'Open · ${data['in_progress_tickets'] ?? 0} in progress',
                      style: KasaFont.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.tertiaryInk,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Track',
                            style: KasaFont.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.tertiaryInk)),
                        Icon(Icons.arrow_forward, size: 16, color: cs.tertiaryInk),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Quick actions ──
        _ResponsiveTileGrid(
          children: [
            _QuickAction(icon: Icons.payments_outlined, label: 'Pay\nrent', accent: KasaCardAccent.primary, onTap: () => context.go('/invoices')),
            _QuickAction(icon: Icons.construction_outlined, label: 'Report\nissue', accent: KasaCardAccent.tertiary, onTap: () => context.go('/maintenance')),
            // WHY no third tile: this was "VIEW TENANCY" with an empty onTap —
            // a button that looked live and did nothing. There is no tenancy
            // detail screen for tenants to open, and the card above already
            // shows their unit and dates, so the honest fix is to drop it
            // rather than leave a dead target on the busiest screen.
          ],
        ),
        const SizedBox(height: 14),

        // ── Payment history ──
        _PaymentHistoryCard(data: data),
      ],
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text, {this.ink});
  final String text;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: KasaFont.sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.04,
        color: ink ?? cs.onSurface.withValues(alpha: 0.75),
        height: 1,
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.label, required this.onPrimary, required this.primary});
  final String label;
  final Color onPrimary;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onPrimary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: KasaFont.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.04,
          color: primary,
        ),
      ),
    );
  }
}

/// Lays tiles out in as many columns as the width comfortably allows, keeping
/// every tile in a row the same height.
///
/// WHY not a fixed Row of Expanded children: that always forces N-across, so a
/// 320dp phone squeezes three tiles into ~93dp each and clips their labels,
/// while a foldable or tablet stretches the same three across 700dp of dead
/// space. Deriving the column count from a minimum readable tile width fixes
/// both ends, and [maxWidth] stops the row sprawling on a large screen.
class _ResponsiveTileGrid extends StatelessWidget {
  const _ResponsiveTileGrid({required this.children});

  final List<Widget> children;

  /// Narrowest a tile can get before its two-line label starts clipping.
  static const double minTileWidth = 96;
  static const double spacing = 10;

  /// Past this the row stops growing and centres, so tiles keep a sane size on
  /// tablets and unfolded foldables.
  static const double maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(constraints.maxWidth, maxWidth);
        final fitted =
            ((available + spacing) / (minTileWidth + spacing)).floor();
        final columns = fitted.clamp(1, children.length);

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final end = math.min(start + columns, children.length);
          final slice = children.sublist(start, end);

          rows.add(
            // IntrinsicHeight so a label that wraps to a third line lifts its
            // neighbours with it instead of leaving the row ragged.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: spacing),
                    // Empty slots keep a short final row aligned with the one
                    // above rather than stretching its tiles wider.
                    Expanded(
                      child: column < slice.length
                          ? slice[column]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: spacing),
                  rows[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.accent, this.onTap});
  final IconData icon;
  final String label;
  final KasaCardAccent accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = switch (accent) {
      KasaCardAccent.primary   => cs.onPrimary,
      KasaCardAccent.secondary => cs.onSecondary,
      KasaCardAccent.tertiary  => cs.onTertiary,
      _                        => cs.onSurface,
    };
    return KasaCard(
      accent: accent,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: ink),
          const SizedBox(height: 10),
          Text(
            label,
            style: KasaFont.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.11,
              color: ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Occupancy Ring ───────────────────────────────────────────────────────────
// ─── Activity card (landlord) ─────────────────────────────────────────────────
// ─── Payment history card (tenant) ───────────────────────────────────────────

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = (data['payment_history'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return KasaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Label('Payment history'),
                GestureDetector(
                  onTap: () => context.go('/invoices'),
                  child: Text(
                    'ALL',
                    style: KasaFont.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.kasaTextSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No recent payments',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
              ),
            )
          else
            ...history.take(4).toList().asMap().entries.map((e) {
              final i = e.key;
              final h = e.value;
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: i > 0
                        ? BorderSide(color: cs.kasaStroke, width: KasaBorders.card)
                        : BorderSide.none,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                      ),
                      child: Icon(Icons.check, size: 22, color: cs.onPrimary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatCurrency(toDouble(h['amount'])),
                            style: KasaFont.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.15,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${h['mpesa_code'] ?? ''} · ${h['date'] ?? ''}',
                            style: KasaFont.mono(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: cs.kasaTextSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const KasaChip(label: 'Paid', variant: KasaChipVariant.primary, small: true),
                  ],
                ),
              );
            }),
        ],
      ),
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

DateTime? _parseDate(dynamic iso) {
  if (iso == null) return null;
  return DateTime.tryParse(iso.toString());
}

/// The tenant's written notice to vacate, shown on their tenancy card.
///
/// WHY it lives here: an open-ended tenancy ends by notice rather than by
/// reaching a date, so this is the action that actually terminates most Kenyan
/// tenancies — it belongs next to the tenancy status, not buried in settings.
class _NoticeAction extends ConsumerStatefulWidget {
  const _NoticeAction({required this.data});
  final Map<String, dynamic> data;

  @override
  ConsumerState<_NoticeAction> createState() => _NoticeActionState();
}

class _NoticeActionState extends ConsumerState<_NoticeAction> {
  bool _sending = false;

  Future<void> _giveNotice() async {
    final tenancyId = widget.data['tenancy_id'];
    if (tenancyId == null) return;

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Give notice to your landlord?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your landlord will be told straight away. Under your tenancy '
              'agreement you give a month of notice and move out by the end '
              'of next month, so your rent is paid up to the day you leave. '
              'This cannot be undone in the app.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Give notice'),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final resp = await ref.read(dioProvider).post(
            '/api/v1/tenants/tenancies/$tenancyId/give-notice/',
            data: {'reason': reason},
          );
      ref.invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(resp.data['message']?.toString() ?? 'Notice given.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effective = widget.data['notice_effective_date'];

    // Already given — show the date rather than a button that would only 409.
    if (effective != null) {
      final on = DateTime.tryParse(effective.toString());
      return Text(
        on != null
            ? 'Notice given · moving ${DateFormat('d MMM').format(on)}'
            : 'Notice given',
        style: KasaFont.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.onSecondary,
        ),
      );
    }

    if (widget.data['tenancy_id'] == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: _sending ? null : _giveNotice,
        style: TextButton.styleFrom(
          foregroundColor: cs.onSecondary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          minimumSize: const Size(44, 44),
          side: BorderSide(color: cs.onSecondary.withValues(alpha: 0.4), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _sending
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.onSecondary),
              )
            : Text(
                'GIVE 30 DAYS NOTICE',
                style: KasaFont.sans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondary,
                ),
              ),
      ),
    );
  }
}
