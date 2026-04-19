import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_logo.dart';
import '../../core/widgets/kasa_primitives.dart';

const _storage = FlutterSecureStorage();

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/payments/dashboard/');
  return resp.data as Map<String, dynamic>;
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
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      body: SafeArea(
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(dashboardProvider)),
          data: (data) {
            final isLandlord = data.containsKey('properties');
            return RefreshIndicator(
              onRefresh: () => ref.refresh(dashboardProvider.future),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _DashHeader(
                      userName: _userName,
                      subtitle: isLandlord
                          ? 'Here\'s how your portfolio is running.'
                          : '${data['property_name'] ?? ''} · Unit ${data['unit_number'] ?? ''}',
                      isDark: isDark,
                      onThemeToggle: () {
                        ref.read(themeModeProvider.notifier).setMode(
                              isDark ? ThemeMode.light : ThemeMode.dark,
                            );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (isLandlord)
                          _LandlordBento(data: data, cs: cs)
                        else
                          _TenantBento(data: data, cs: cs),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _DashHeader extends StatelessWidget {
  const _DashHeader({
    required this.userName,
    required this.subtitle,
    required this.isDark,
    required this.onThemeToggle,
  });

  final String? userName;
  final String subtitle;
  final bool isDark;
  final VoidCallback onThemeToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstName = (userName ?? 'there').split(' ').first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KasaLockupHorizontal(markSize: 26),
              const Spacer(),
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  size: 22,
                  color: cs.onSurface,
                ),
                onPressed: onThemeToggle,
                tooltip: 'Toggle theme',
              ),
              IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications_outlined, size: 22, color: cs.onSurface),
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () => context.push('/notifications'),
                tooltip: 'Notifications',
              ),
              IconButton(
                icon: Icon(Icons.account_circle_outlined, size: 22, color: cs.onSurface),
                onPressed: () => context.push('/profile'),
                tooltip: 'Profile',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'HABARI, $firstName',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.56,
              color: cs.onSurface,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.kasaTextSub,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Landlord Bento ───────────────────────────────────────────────────────────

class _LandlordBento extends StatelessWidget {
  const _LandlordBento({required this.data, required this.cs});
  final Map<String, dynamic> data;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final revenue = toDouble(data['monthly_collected_kes']);
    final overdueAmt = toDouble(data['overdue_amount_kes']);
    final overdueCount = (data['overdue_invoices'] ?? 0) as int;
    final totalUnits = (data['total_units'] ?? 0) as int;
    final occupiedUnits = (data['occupied_units'] ?? 0) as int;
    final occupancyPct = totalUnits > 0 ? (occupiedUnits / totalUnits * 100).round() : 0;
    final month = DateFormat('MMM yyyy').format(DateTime.now()).toUpperCase();

    return Column(
      children: [
        // ── Hero: Total Revenue ──
        KasaCard(
          accent: KasaCardAccent.primary,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('TOTAL REVENUE · $month'),
              const SizedBox(height: 10),
              Text(
                formatCurrency(revenue),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 60,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.44,
                  color: cs.onPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              _TrendChip(label: '${data['properties'] ?? 0} PROPERTIES · $totalUnits UNITS', onPrimary: cs.onPrimary, primary: cs.primary),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── 2-col: Occupancy + Overdue ──
        Row(
          children: [
            Expanded(
              child: KasaCard(
                accent: KasaCardAccent.secondary,
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _Label('OCCUPANCY', ink: cs.onSecondary.withValues(alpha: 0.75)),
                    const SizedBox(height: 8),
                    _OccupancyRing(
                      pct: occupancyPct.toDouble(),
                      size: 108,
                      color: cs.onSecondary,
                      bg: cs.onSecondary.withValues(alpha: 0.18),
                      label: '$occupancyPct%',
                      labelColor: cs.onSecondary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$occupiedUnits / $totalUnits UNITS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: KasaCard(
                accent: KasaCardAccent.tertiary,
                padding: const EdgeInsets.all(18),
                onTap: () => context.go('/invoices'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('OVERDUE', ink: cs.tertiaryInk.withValues(alpha: 0.75)),
                    const SizedBox(height: 8),
                    Text(
                      '$overdueCount',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 54,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.62,
                        color: cs.tertiaryInk,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatCurrency(overdueAmt),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.tertiaryInk,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('VIEW',
                            style: GoogleFonts.inter(
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
        Row(
          children: [
            Expanded(child: _QuickAction(icon: Icons.add_home_work_outlined, label: 'ADD\nPROPERTY', accent: KasaCardAccent.primary, onTap: () => context.push('/properties'))),
            const SizedBox(width: 10),
            Expanded(child: _QuickAction(icon: Icons.person_add_outlined, label: 'ADD\nTENANT', accent: KasaCardAccent.secondary, onTap: () => context.push('/tenants'))),
            const SizedBox(width: 10),
            Expanded(child: _QuickAction(icon: Icons.receipt_long_outlined, label: 'NEW\nINVOICE', accent: KasaCardAccent.tertiary, onTap: () => context.push('/invoices'))),
          ],
        ),
        const SizedBox(height: 14),

        // ── Recent activity (mini-card list) ──
        _ActivityCard(data: data),
      ],
    );
  }
}

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
    final leaseEnd = _parseDate(data['lease_end']);
    final now = DateTime.now();
    final daysUntilDue = dueDate?.difference(now).inDays;
    final daysUntilLease = leaseEnd?.difference(now).inDays;
    final leasePct = (leaseEnd != null && data['lease_start'] != null)
        ? () {
            final start = _parseDate(data['lease_start'])!;
            final total = leaseEnd.difference(start).inDays;
            final elapsed = now.difference(start).inDays;
            return (elapsed / total).clamp(0.0, 1.0);
          }()
        : 0.68;
    final dueDateLabel = dueDate != null
        ? DateFormat('d MMM yyyy').format(dueDate).toUpperCase()
        : 'NEXT DUE DATE';

    return Column(
      children: [
        // ── Hero: Rent Due ──
        KasaCard(
          accent: KasaCardAccent.primary,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('RENT DUE · $dueDateLabel'),
              const SizedBox(height: 10),
              Text(
                outstanding > 0 ? formatCurrency(outstanding) : formatCurrency(dueAmt),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 60,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.44,
                  color: cs.onPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              if (daysUntilDue != null)
                _TrendChip(
                  label: daysUntilDue > 0 ? '$daysUntilDue DAYS LEFT' : 'OVERDUE',
                  onPrimary: cs.onPrimary,
                  primary: cs.primary,
                ),
              const SizedBox(height: 16),
              KasaButton(
                label: 'PAY WITH MPESA',
                onTap: () => context.go('/invoices'),
                variant: KasaButtonVariant.ghost,
                leading: Icon(Icons.phone_android, size: 16, color: cs.onPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── 2-col: Lease countdown + Tickets ──
        Row(
          children: [
            Expanded(
              child: KasaCard(
                accent: KasaCardAccent.secondary,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('LEASE ENDS', ink: cs.onSecondary.withValues(alpha: 0.75)),
                    const SizedBox(height: 8),
                    Text(
                      '${daysUntilLease ?? '—'}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.56,
                        color: cs.onSecondary,
                        height: 1,
                      ),
                    ),
                    Text(
                      leaseEnd != null
                          ? 'DAYS · ${DateFormat('d MMM yyyy').format(leaseEnd).toUpperCase()}'
                          : 'DAYS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
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
                            widthFactor: leasePct,
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
                    _Label('TICKETS', ink: cs.tertiaryInk.withValues(alpha: 0.75)),
                    const SizedBox(height: 8),
                    Text(
                      '${data['open_tickets'] ?? 0}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.56,
                        color: cs.tertiaryInk,
                        height: 1,
                      ),
                    ),
                    Text(
                      'OPEN · ${data['in_progress_tickets'] ?? 0} IN PROGRESS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.tertiaryInk,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TRACK',
                            style: GoogleFonts.inter(
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
        Row(
          children: [
            Expanded(child: _QuickAction(icon: Icons.payments_outlined, label: 'PAY\nRENT', accent: KasaCardAccent.primary, onTap: () => context.go('/invoices'))),
            const SizedBox(width: 10),
            Expanded(child: _QuickAction(icon: Icons.construction_outlined, label: 'REPORT\nISSUE', accent: KasaCardAccent.tertiary, onTap: () => context.go('/maintenance'))),
            const SizedBox(width: 10),
            Expanded(child: _QuickAction(icon: Icons.description_outlined, label: 'VIEW\nLEASE', accent: KasaCardAccent.secondary, onTap: () {})),
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
      style: GoogleFonts.spaceGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w700,
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
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04,
          color: primary,
        ),
      ),
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
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
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

class _OccupancyRing extends StatelessWidget {
  const _OccupancyRing({
    required this.pct,
    required this.size,
    required this.color,
    required this.bg,
    required this.label,
    required this.labelColor,
  });

  final double pct;
  final double size;
  final Color color;
  final Color bg;
  final String label;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(pct: pct, color: color, bg: bg),
          ),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.04,
              color: labelColor,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.pct, required this.color, required this.bg});
  final double pct;
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = (size.width - 14) / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final bgPaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(Offset(cx, cy), r, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * (pct / 100), false, fgPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct || old.color != color;
}

// ─── Activity card (landlord) ─────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Build activity rows from summary data since the dashboard API returns aggregates.
    final items = <_ActivityItem>[
      _ActivityItem(
        icon: Icons.home_work_outlined,
        accent: KasaCardAccent.secondary,
        text: '${data['properties'] ?? 0} properties · ${data['total_units'] ?? 0} units',
        time: 'PORTFOLIO',
      ),
      _ActivityItem(
        icon: Icons.people_outline,
        accent: KasaCardAccent.primary,
        text: '${data['occupied_units'] ?? 0} occupied · ${data['vacant_units'] ?? 0} vacant',
        time: 'OCCUPANCY',
      ),
      _ActivityItem(
        icon: Icons.payments_outlined,
        accent: KasaCardAccent.tertiary,
        text: 'KES ${_fmt(data['overdue_amount_kes'])} outstanding',
        time: 'OVERDUE',
      ),
    ];

    return KasaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Label('PORTFOLIO SUMMARY'),
                GestureDetector(
                  onTap: () => context.push('/reports'),
                  child: Text(
                    'REPORTS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.kasaTextSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            final ink = switch (item.accent) {
              KasaCardAccent.primary   => cs.onPrimary,
              KasaCardAccent.secondary => cs.onSecondary,
              KasaCardAccent.tertiary  => cs.tertiaryInk,
              _                        => cs.onSurface,
            };
            final fill = switch (item.accent) {
              KasaCardAccent.primary   => cs.primary,
              KasaCardAccent.secondary => cs.secondary,
              KasaCardAccent.tertiary  => cs.tertiary,
              _                        => cs.surface,
            };
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  top: i > 0
                      ? BorderSide(color: cs.kasaStroke, width: 2)
                      : BorderSide.none,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.kasaStroke, width: 2),
                    ),
                    child: Icon(item.icon, size: 20, color: ink),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.text,
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.time,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.04,
                              color: cs.kasaTextSub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ActivityItem {
  const _ActivityItem({required this.icon, required this.accent, required this.text, required this.time});
  final IconData icon;
  final KasaCardAccent accent;
  final String text;
  final String time;
}

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
                const _Label('PAYMENT HISTORY'),
                GestureDetector(
                  onTap: () => context.go('/invoices'),
                  child: Text(
                    'ALL',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
                style: GoogleFonts.inter(fontSize: 14, color: cs.kasaTextSub),
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
                        ? BorderSide(color: cs.kasaStroke, width: 2)
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
                        border: Border.all(color: cs.kasaStroke, width: 2),
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
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.15,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${h['mpesa_code'] ?? ''} · ${h['date'] ?? ''}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: cs.kasaTextSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const KasaChip(label: 'PAID', variant: KasaChipVariant.primary, small: true),
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
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again.',
              style: GoogleFonts.inter(fontSize: 13, color: cs.kasaTextSub),
            ),
            const SizedBox(height: 24),
            KasaButton(label: 'RETRY', onTap: onRetry, variant: KasaButtonVariant.secondary),
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

String _fmt(dynamic v) {
  final n = toDouble(v);
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toStringAsFixed(0);
}
