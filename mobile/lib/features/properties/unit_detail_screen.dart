import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../tenants/tenants_screen.dart';

final unitOccupancyProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, unitId) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/properties/units/$unitId/occupancy/');
  return resp.data as Map<String, dynamic>;
});

/// Everything about one unit: who lives there, what they have paid, what they
/// have reported — or, when empty, the way to fill it.
class UnitDetailScreen extends ConsumerWidget {
  const UnitDetailScreen({super.key, required this.unitId});
  final int unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final occupancy = ref.watch(unitOccupancyProvider(unitId));

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        backgroundColor: cs.kasaBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          occupancy.valueOrNull?['unit']?['unit_number'] != null
              ? 'UNIT ${occupancy.value!['unit']['unit_number']}'
              : 'UNIT',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.04,
            color: cs.onSurface,
          ),
        ),
      ),
      body: occupancy.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 56, color: cs.kasaTextSub),
                const SizedBox(height: 12),
                Text(apiError(e),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: cs.kasaTextSub)),
                const SizedBox(height: 16),
                KasaButton(
                  label: 'RETRY',
                  variant: KasaButtonVariant.secondary,
                  onTap: () => ref.invalidate(unitOccupancyProvider(unitId)),
                ),
              ],
            ),
          ),
        ),
        data: (d) => d['tenancy'] == null
            ? _VacantUnit(data: d, unitId: unitId)
            : _OccupiedUnit(data: d),
      ),
    );
  }
}

// ─── Vacant ───────────────────────────────────────────────────────────────────

class _VacantUnit extends ConsumerWidget {
  const _VacantUnit({required this.data, required this.unitId});
  final Map<String, dynamic> data;
  final int unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final unit = data['unit'] as Map<String, dynamic>;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _UnitFacts(unit: unit, propertyName: data['property_name']?.toString()),
        const SizedBox(height: 24),
        Icon(Icons.meeting_room_outlined, size: 64, color: cs.kasaTextSub),
        const SizedBox(height: 12),
        Text(
          'This unit is vacant.',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Add a tenant and their tenancy starts here.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: cs.kasaTextSub),
        ),
        const SizedBox(height: 20),
        KasaButton(
          label: 'ADD TENANT',
          variant: KasaButtonVariant.primary,
          // Runs both steps here rather than routing to the tenants tab: that
          // tab is a shell branch, and pushing it from inside the properties
          // branch only bounced back to the property list.
          onTap: () async {
            await startTenancyForUnit(context, ref, unitId);
            ref.invalidate(unitOccupancyProvider(unitId));
          },
        ),
      ],
    );
  }
}

// ─── Occupied ─────────────────────────────────────────────────────────────────

class _OccupiedUnit extends StatelessWidget {
  const _OccupiedUnit({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unit = data['unit'] as Map<String, dynamic>;
    final tenant = (data['tenant'] as Map?)?.cast<String, dynamic>() ?? {};
    final tenancy = (data['tenancy'] as Map?)?.cast<String, dynamic>() ?? {};
    final payments = (data['payments'] as List? ?? []).cast<Map<String, dynamic>>();
    final maintenance =
        (data['maintenance'] as List? ?? []).cast<Map<String, dynamic>>();
    final noticeDate = tenancy['notice_effective_date']?.toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _TenantCard(tenant: tenant, tenancy: tenancy),

        if (noticeDate != null) ...[
          const SizedBox(height: 12),
          KasaCard(
            accent: KasaCardAccent.tertiary,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.event_busy_outlined, size: 20, color: cs.onTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notice given — moving out ${_pretty(noticeDate)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        _UnitFacts(unit: unit, propertyName: data['property_name']?.toString()),

        const SizedBox(height: 20),
        const _SectionHeader('PAYMENT HISTORY'),
        const SizedBox(height: 8),
        if (payments.isEmpty)
          const _Empty(text: 'No payments recorded yet.')
        else
          ...payments.map((p) => _PaymentRow(payment: p)),

        const SizedBox(height: 20),
        const _SectionHeader('MAINTENANCE'),
        const SizedBox(height: 8),
        if (maintenance.isEmpty)
          const _Empty(text: 'Nothing reported.')
        else
          ...maintenance.map((m) => _MaintenanceRow(request: m)),
      ],
    );
  }

  static String _pretty(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMM yyyy').format(d);
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.tenancy});
  final Map<String, dynamic> tenant;
  final Map<String, dynamic> tenancy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = tenant['name']?.toString() ?? 'Unknown';
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    // Absent for caretakers, who do not need the landlord's filing details.
    final kra = tenant['kra_pin']?.toString();
    final nationalId = tenant['national_id']?.toString();

    return KasaCard(
      accent: KasaCardAccent.secondary,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.onSecondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(KasaRadius.md),
                  border: Border.all(color: cs.kasaStroke, width: 2),
                ),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tenant['phone_number']?.toString() ?? '',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: cs.onSecondary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Fact(label: 'RENT', value: formatCurrency(toDouble(tenancy['rent_amount'])), ink: cs.onSecondary),
          _Fact(label: 'SINCE', value: _pretty(tenancy['start_date']?.toString()), ink: cs.onSecondary),
          if (tenant['occupation'] != null)
            _Fact(label: 'WORK', value: tenant['occupation'].toString(), ink: cs.onSecondary),
          if (kra != null)
            _Fact(
              label: 'KRA PIN',
              value: kra.isEmpty ? 'Not on file' : kra,
              ink: cs.onSecondary,
              warn: kra.isEmpty,
            ),
          if (nationalId != null && nationalId.isNotEmpty)
            _Fact(label: 'ID', value: nationalId, ink: cs.onSecondary),
          if (tenant['next_of_kin_name'] != null)
            _Fact(
              label: 'NEXT OF KIN',
              value:
                  '${tenant['next_of_kin_name']} · ${tenant['next_of_kin_phone'] ?? ''}',
              ink: cs.onSecondary,
            ),
        ],
      ),
    );
  }

  static String _pretty(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMM yyyy').format(d);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.ink,
    this.warn = false,
  });
  final String label;
  final String value;
  final Color ink;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.04,
                color: ink.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: warn ? cs.error : ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitFacts extends StatelessWidget {
  const _UnitFacts({required this.unit, this.propertyName});
  final Map<String, dynamic> unit;
  final String? propertyName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KasaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            propertyName ?? '',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          _Fact(label: 'UNIT', value: unit['unit_number']?.toString() ?? '', ink: cs.onSurface),
          // The code tenants actually type into M-Pesa, which is not always
          // the same as the unit number the landlord uses.
          _Fact(label: 'PAY CODE', value: unit['payment_code']?.toString() ?? '', ink: cs.onSurface),
          _Fact(label: 'RENT', value: formatCurrency(toDouble(unit['rent_amount'])), ink: cs.onSurface),
          _Fact(label: 'STATUS', value: (unit['status']?.toString() ?? '').toUpperCase(), ink: cs.onSurface),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.04,
        color: Theme.of(context).colorScheme.kasaTextSub,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: Theme.of(context).colorScheme.kasaTextSub,
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});
  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paidAt = payment['paid_at']?.toString();
    final when = paidAt == null
        ? '—'
        : DateFormat('d MMM yyyy').format(DateTime.parse(paidAt).toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KasaCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatCurrency(toDouble(payment['amount'])),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$when · ${(payment['method']?.toString() ?? '').toUpperCase()}',
                    style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub),
                  ),
                ],
              ),
            ),
            Text(
              payment['invoice_number']?.toString() ?? '',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: cs.kasaTextSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceRow extends StatelessWidget {
  const _MaintenanceRow({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = request['status']?.toString() ?? '';
    final isOpen = status == 'open' || status == 'in_progress';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KasaCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                request['title']?.toString() ?? '',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            KasaChip(
              label: status.replaceAll('_', ' ').toUpperCase(),
              variant:
                  isOpen ? KasaChipVariant.tertiary : KasaChipVariant.neutral,
            ),
          ],
        ),
      ),
    );
  }
}
