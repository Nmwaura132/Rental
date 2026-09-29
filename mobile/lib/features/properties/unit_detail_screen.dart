import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/call.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../payments/invoices_screen.dart';
import '../payments/unplaced_payments.dart';
import '../tenants/deposit_settlement_screen.dart';
import '../tenants/tenants_screen.dart';
import 'properties_screen.dart';
import 'property_detail_screen.dart';

final unitOccupancyProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, unitId) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/properties/units/$unitId/occupancy/');
  return resp.data as Map<String, dynamic>;
});

DateTime? _date(Object? iso) => DateTime.tryParse('${iso ?? ''}');

String _pretty(Object? iso, [String pattern = 'd MMM yyyy']) {
  final d = _date(iso);
  return d == null ? '—' : DateFormat(pattern).format(d.toLocal());
}

/// True once the last day of a notice has come, when the tenant is out and the
/// deposit can be settled.
bool _lastDayReached(Object? iso) {
  final d = _date(iso);
  if (d == null) return false;
  final today = DateTime.now();
  return !DateTime(d.year, d.month, d.day).isAfter(DateTime(today.year, today.month, today.day));
}

/// Everything about one unit: who lives there, what they owe and have paid,
/// what they have reported. Or, when empty, the way to fill it.
///
/// Money is the landlord's. A caretaker sees who lives there, how to reach
/// them and what needs seeing to, and the server does not send them the rest.
class UnitDetailScreen extends ConsumerWidget {
  const UnitDetailScreen({super.key, required this.unitId});
  final int unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final occupancy = ref.watch(unitOccupancyProvider(unitId));
    final isLandlord = ref.watch(userRoleProvider).valueOrNull == 'landlord';

    final data = occupancy.valueOrNull;
    final unit = (data?['unit'] as Map?)?.cast<String, dynamic>();
    final tenancy = (data?['tenancy'] as Map?)?.cast<String, dynamic>();
    final tenantName = '${(data?['tenant'] as Map?)?['name'] ?? 'the tenant'}';

    void refresh() {
      ref.invalidate(unitOccupancyProvider(unitId));
      ref.invalidate(propertiesProvider);
      final propertyId = unit?['property'];
      if (propertyId is int) ref.invalidate(propertyDetailProvider(propertyId));
    }

    Future<void> deleteUnit() async {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete unit?'),
          content: Text('Delete unit ${unit?['unit_number']}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      final errorColor = Theme.of(context).colorScheme.error;
      try {
        await ref.read(dioProvider).delete('/api/v1/properties/units/$unitId/');
        refresh();
        router.pop();
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
      }
    }

    Widget? actionBar;
    if (data != null) {
      if (tenancy == null) {
        actionBar = KasaActionBar(children: [
          KasaButton(
            label: 'Add tenant',
            variant: KasaButtonVariant.primary,
            leading: Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
            // Runs both steps here rather than routing to the tenants tab: that
            // tab is a shell branch, and pushing it from inside the properties
            // branch only bounced back to the property list.
            onTap: () async {
              await startTenancyForUnit(context, ref, unitId);
              refresh();
            },
          ),
        ]);
      } else if (isLandlord && toDouble(tenancy['balance']) > 0) {
        actionBar = KasaActionBar(children: [
          KasaButton(
            label: 'Record payment',
            variant: KasaButtonVariant.primary,
            onTap: () async {
              final id = await pickOpenBill(
                context,
                ref,
                title: 'Which bill is this payment for?',
                tenancyId: tenancy['id'] as int,
              );
              if (id == null || !context.mounted) return;
              await recordPaymentOn(context, ref, id);
              refresh();
            },
          ),
        ]);
      }
    }

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Text.rich(
          TextSpan(children: [
            TextSpan(text: unit == null ? 'Unit' : 'Unit ${unit['unit_number']}'),
            if (data?['property_name'] != null)
              TextSpan(
                text: ' · ${data!['property_name']}',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
              ),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        actions: [
          if (isLandlord && unit != null)
            PopupMenuButton<String>(
              tooltip: 'Unit options',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) async {
                switch (v) {
                  case 'edit':
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => EditUnitDialog(unit: unit, onDone: refresh),
                    );
                  case 'notice':
                    await giveNoticeAsLandlord(context, ref, {'id': tenancy!['id']});
                    refresh();
                  case 'settle':
                    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => DepositSettlementScreen(
                        tenancyId: tenancy!['id'] as int,
                        tenantName: tenantName,
                      ),
                    ));
                    refresh();
                  case 'delete':
                    await deleteUnit();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit unit')),
                if (tenancy != null && tenancy['notice_effective_date'] == null)
                  const PopupMenuItem(value: 'notice', child: Text('Give notice')),
                if (tenancy != null && _lastDayReached(tenancy['notice_effective_date']))
                  const PopupMenuItem(value: 'settle', child: Text('Settle deposit')),
                if (tenancy == null)
                  const PopupMenuItem(value: 'delete', child: Text('Delete unit')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: actionBar,
      body: occupancy.when(
        loading: () => const KasaSkeletonDetail(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 48, color: cs.kasaTextSub),
                const SizedBox(height: 12),
                Text(apiError(e),
                    textAlign: TextAlign.center, style: KasaFont.sans(color: cs.kasaTextSub)),
                const SizedBox(height: 16),
                KasaButton(
                  label: 'Retry',
                  variant: KasaButtonVariant.secondary,
                  fullWidth: false,
                  onTap: () => ref.invalidate(unitOccupancyProvider(unitId)),
                ),
              ],
            ),
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => refresh(),
          child: d['tenancy'] == null
              ? _VacantBody(data: d, isLandlord: isLandlord)
              : _OccupiedBody(data: d, isLandlord: isLandlord),
        ),
      ),
    );
  }
}

// Vacant

class _VacantBody extends StatelessWidget {
  const _VacantBody({required this.data, required this.isLandlord});
  final Map<String, dynamic> data;
  final bool isLandlord;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unit = (data['unit'] as Map).cast<String, dynamic>();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        KasaCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: [
            KasaKeyValue('Rent', _value(context, '${formatCurrency(toDouble(unit['rent_amount']))} / month')),
            if (isLandlord)
              KasaKeyValue('Deposit', _value(context, formatCurrency(toDouble(unit['deposit_amount'])))),
            ..._payRows(context, data),
          ]),
        ),
        const SizedBox(height: 40),
        Icon(Icons.meeting_room_outlined, size: 56, color: cs.kasaTextSub),
        const SizedBox(height: 12),
        Text('This unit is vacant.',
            textAlign: TextAlign.center,
            style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 6),
        Text('Add a tenant and their tenancy starts here.',
            textAlign: TextAlign.center,
            style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
      ],
    );
  }
}

// Occupied

class _OccupiedBody extends StatelessWidget {
  const _OccupiedBody({required this.data, required this.isLandlord});
  final Map<String, dynamic> data;
  final bool isLandlord;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tenant = (data['tenant'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tenancy = (data['tenancy'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payments = (data['payments'] as List? ?? const []).cast<Map<String, dynamic>>();
    final repairs = (data['maintenance'] as List? ?? const []).cast<Map<String, dynamic>>();
    final leaving = tenancy['notice_effective_date'];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (leaving != null) ...[
          KasaNotice(
            icon: Icons.door_front_door_outlined,
            title: 'Moving out ${_pretty(leaving)}',
            body: 'Notice given ${_pretty(tenancy['notice_given_at'], 'd MMM')}. '
                'Book the move-out inspection'
                '${isLandlord ? ' before refunding the deposit' : ''}.',
          ),
          const SizedBox(height: 16),
        ],
        _TenantCard(tenant: tenant, tenancy: tenancy, isLandlord: isLandlord),
        if (isLandlord) ...[
          const SizedBox(height: 24),
          KasaSectionHeader(
            'Payments',
            trailing: InkWell(
              onTap: () => context.go('/invoices'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('All bills',
                    style: KasaFont.sans(
                        fontSize: 14, fontWeight: FontWeight.w500, color: cs.primary)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            Text('No payments recorded yet.',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))
          else
            KasaListGroup(children: [
              for (final p in payments.take(5))
                KasaListRow(
                  tight: true,
                  title: _pretty(p['period_start'] ?? p['paid_at'], 'MMMM'),
                  subtitle: [
                    '${p['method_display'] ?? p['method'] ?? ''}',
                    if ('${p['reference'] ?? ''}'.isNotEmpty) '${p['reference']}',
                  ].join(' · '),
                  trailing: Text(
                    NumberFormat('#,##0').format(toDouble(p['amount'])),
                    style: KasaFont.sans(
                            fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)
                        .copyWith(fontFeatures: KasaType.tabular),
                  ),
                ),
            ]),
        ],
        const SizedBox(height: 24),
        const KasaSectionHeader('Repairs'),
        const SizedBox(height: 8),
        if (repairs.isEmpty)
          Text('Nothing reported.', style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))
        else
          KasaListGroup(children: [for (final r in repairs) _RepairRow(request: r)]),
        ..._details(context, tenant),
        const SizedBox(height: 24),
        const KasaSectionHeader('Unit'),
        const SizedBox(height: 8),
        KasaCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: _payRows(context, data)),
        ),
      ],
    );
  }

  /// Work, KRA PIN, ID and next of kin. The filing details are the landlord's
  /// and are simply absent for a caretaker.
  List<Widget> _details(BuildContext context, Map<String, dynamic> tenant) {
    final cs = Theme.of(context).colorScheme;
    String field(String key) => '${tenant[key] ?? ''}'.trim();

    final rows = <Widget>[
      if (field('occupation').isNotEmpty)
        KasaKeyValue('Work', _value(context, field('occupation'))),
      if (isLandlord && tenant.containsKey('kra_pin'))
        KasaKeyValue(
          'KRA PIN',
          field('kra_pin').isEmpty
              ? Text('Not on file',
                  style: KasaFont.sans(fontSize: 14, color: cs.statusOverdue))
              : _value(context, field('kra_pin')),
        ),
      if (isLandlord && field('national_id').isNotEmpty)
        KasaKeyValue('ID', _value(context, field('national_id'))),
      if (field('next_of_kin_name').isNotEmpty)
        KasaKeyValue(
          'Next of kin',
          _value(context, '${field('next_of_kin_name')} · ${field('next_of_kin_phone')}'),
        ),
    ];
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      const KasaSectionHeader('Details'),
      const SizedBox(height: 8),
      KasaCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: rows),
      ),
    ];
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.tenancy, required this.isLandlord});
  final Map<String, dynamic> tenant;
  final Map<String, dynamic> tenancy;
  final bool isLandlord;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = '${tenant['name'] ?? 'Unknown'}';
    final phone = '${tenant['phone_number'] ?? ''}';
    final balance = toDouble(tenancy['balance']);
    final (kind, label) = tenancy['overdue'] == true
        ? (KasaStatusKind.overdue, 'Overdue')
        : balance > 0
            ? (KasaStatusKind.due, 'Due')
            : (KasaStatusKind.paid, 'Paid');

    return KasaCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            KasaAvatar(name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KasaFont.sans(
                          fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(phone,
                      style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)
                          .copyWith(fontFeatures: KasaType.tabular)),
                ],
              ),
            ),
            if (phone.isNotEmpty)
              IconButton(
                tooltip: 'Call $name',
                icon: const Icon(Icons.phone_outlined),
                onPressed: () => callNumber(context, phone),
              ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Divider(height: 1, color: cs.kasaStroke),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(children: [
              KasaKeyValue(
                  'Rent', _value(context, '${formatCurrency(toDouble(tenancy['rent_amount']))} / month')),
              KasaKeyValue('Since', _value(context, _pretty(tenancy['start_date'], 'MMM yyyy'))),
              if (isLandlord) ...[
                KasaKeyValue(
                  'Deposit held',
                  _value(
                    context,
                    tenancy['deposit_paid'] == true
                        ? formatCurrency(toDouble(tenancy['deposit_amount']))
                        : 'Not paid',
                  ),
                ),
                KasaKeyValue(
                  'Balance',
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _value(context, formatCurrency(balance)),
                    const SizedBox(width: 8),
                    KasaStatusChip(kind: kind, label: label),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class _RepairRow extends StatelessWidget {
  const _RepairRow({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final status = '${request['status'] ?? ''}';
    final done = status == 'resolved';
    final tail = done
        ? (request['resolved_at'] != null ? 'fixed ${_pretty(request['resolved_at'], 'd MMM')}' : 'fixed')
        : status == 'in_progress'
            ? 'in progress'
            : 'open';

    return KasaListRow(
      tight: true,
      title: '${request['title'] ?? ''}',
      subtitle: 'Reported ${_pretty(request['created_at'], 'd MMM')} · $tail',
      trailing: KasaStatusChip(
        kind: done ? KasaStatusKind.occupied : KasaStatusKind.due,
        label: done
            ? 'Done'
            : status == 'in_progress'
                ? 'In progress'
                : 'Open',
      ),
    );
  }
}

// Shared bits

/// A value in a key/value row: 14 tall, in the full text colour, in figures
/// that line up.
Widget _value(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Flexible(
    child: Text(
      text,
      textAlign: TextAlign.end,
      style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)
          .copyWith(fontFeatures: KasaType.tabular),
    ),
  );
}

/// What the tenant types into M-Pesa for this unit, which a landlord reads out
/// when a payment does not arrive where it was expected.
List<Widget> _payRows(BuildContext context, Map<String, dynamic> data) {
  final cs = Theme.of(context).colorScheme;
  Widget mono(String text) => Text(text, style: KasaFont.mono(fontSize: 14, color: cs.onSurface));
  final paybill = '${data['paybill'] ?? ''}';
  final account = '${data['pay_account'] ?? ''}';
  return [
    if (paybill.isNotEmpty) KasaKeyValue('Paybill', mono(paybill)),
    if (account.isNotEmpty) KasaKeyValue('Account', mono(account)),
  ];
}
