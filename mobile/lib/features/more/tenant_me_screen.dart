import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../dashboard/dashboard_screen.dart';

const _storage = FlutterSecureStorage();

final _meProvider = FutureProvider.autoDispose<(String, String)>((ref) async => (
      await _storage.read(key: 'user_name') ?? '',
      await _storage.read(key: 'user_phone') ?? '',
    ));

/// The tenant's Me tab: who they are, the home they rent, and the few things
/// they can do about it.
class TenantMeScreen extends ConsumerWidget {
  const TenantMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(_meProvider).valueOrNull ?? ('', '');
    final home = ref.watch(dashboardProvider).valueOrNull ?? const {};
    final hasHome = home['unit_number'] != null;
    final noticeGiven = home['notice_effective_date'] != null;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Text('Me', style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          KasaCard(
            child: Row(children: [
              KasaAvatar(name: me.$1, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(me.$1, style: KasaFont.sans(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(_spaced(me.$2),
                      style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
                ]),
              ),
            ]),
          ),
          if (hasHome) ...[
            const SizedBox(height: 24),
            const KasaSectionHeader('Your home'),
            const SizedBox(height: 8),
            KasaCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(children: [
                KasaKeyValue('Unit', _strong(context, '${home['unit_number']} · ${home['property_name']}')),
                if (home['monthly_rent'] != null)
                  KasaKeyValue('Rent', _strong(context, '${formatCurrency(toDouble(home['monthly_rent']))} / month')),
                KasaKeyValue('Deposit held', _strong(context, formatCurrency(toDouble(home['deposit_held'])))),
                if (home['tenancy_start'] != null)
                  KasaKeyValue('Moved in',
                      _strong(context, DateFormat('d MMM yyyy').format(DateTime.parse('${home['tenancy_start']}')))),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          KasaListGroup(children: [
            if (hasHome)
              KasaListRow(
                tight: true,
                leading: const KasaLeadIcon(Icons.door_front_door_outlined),
                title: noticeGiven ? 'Notice given' : 'Give notice to move out',
                subtitle: noticeGiven
                    ? 'Out by ${DateFormat('d MMM yyyy').format(DateTime.parse('${home['notice_effective_date']}'))}'
                    : null,
                onTap: noticeGiven
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => GiveNoticeScreen(home: home)),
                        ),
              ),
            KasaListRow(
              tight: true,
              leading: const KasaLeadIcon(Icons.notifications_none_rounded),
              title: 'Notifications',
              onTap: () => context.push('/notifications'),
            ),
            KasaListRow(
              tight: true,
              leading: const KasaLeadIcon(Icons.settings_outlined),
              title: 'Settings and sign out',
              subtitle: 'Fingerprint unlock, password, log out',
              onTap: () => context.push('/profile'),
            ),
          ]),
        ],
      ),
    );
  }

  /// "+254712345678" -> "+254 712 345 678", the way people read numbers out.
  static String _spaced(String e164) {
    final local = toLocalKenyanDigits(e164);
    if (local.length != 9) return e164;
    return '+254 ${local.substring(0, 3)} ${local.substring(3, 6)} ${local.substring(6)}';
  }

  // WHY Expanded with flex 2: the value gets two thirds of the row and sits
  // flush right; a Flexible shrank to the text and floated mid-row.
  static Widget _strong(BuildContext context, String text) => Expanded(
        flex: 2,
        child: Text(text,
            textAlign: TextAlign.end,
            style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)
                .copyWith(fontFeatures: KasaType.tabular)),
      );
}

/// The last day of the month after this one: the date the tenancy agreement
/// sets for leaving. The server applies the same rule and decides; this only
/// tells the tenant before they confirm.
DateTime vacateBy(DateTime givenOn) => DateTime(givenOn.year, givenOn.month + 2, 0);

class GiveNoticeScreen extends ConsumerStatefulWidget {
  const GiveNoticeScreen({super.key, required this.home});
  final Map<String, dynamic> home;

  @override
  ConsumerState<GiveNoticeScreen> createState() => _GiveNoticeScreenState();
}

class _GiveNoticeScreenState extends ConsumerState<GiveNoticeScreen> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSend(String outBy) async {
    final yes = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Move out by $outBy?',
                style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('Your landlord is told straight away. This cannot be undone in the app.',
                style: KasaFont.sans(fontSize: 14, color: Theme.of(ctx).colorScheme.kasaTextSub)),
            const SizedBox(height: 16),
            KasaButton(label: 'Yes, give notice', onTap: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            KasaButton(label: 'Not now', variant: KasaButtonVariant.ghost, onTap: () => Navigator.pop(ctx, false)),
          ]),
        ),
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final resp = await ref.read(dioProvider).post(
        '/api/v1/tenants/tenancies/${widget.home['tenancy_id']}/give-notice/',
        data: {'reason': _reason.text.trim()},
      );
      ref.invalidate(dashboardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${resp.data['message'] ?? 'Notice given.'}')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiError(e)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final home = widget.home;
    final outBy = DateFormat('d MMM yyyy').format(vacateBy(DateTime.now()));
    final bill = (home['current_bill'] as Map?)?.cast<String, dynamic>();

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(backgroundColor: cs.kasaBg, surfaceTintColor: Colors.transparent, title: const Text('Give notice')),
      bottomNavigationBar: KasaActionBar(children: [
        KasaButton(label: 'Give notice', isLoading: _busy, onTap: _busy ? null : () => _confirmAndSend(outBy)),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Tell your landlord you are moving out of Unit ${home['unit_number']}. '
            'Your agreement needs a month of notice.',
            style: KasaFont.sans(fontSize: 16, color: cs.kasaTextSub),
          ),
          const SizedBox(height: 16),
          KasaNotice(
            icon: Icons.event_outlined,
            title: 'You would move out by $outBy',
            body: 'The end of next month, so the rent you have paid covers you to the day you leave.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _reason,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. moving for work'),
          ),
          const SizedBox(height: 8),
          KasaCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KasaKeyValue('Deposit held', Text(formatCurrency(toDouble(home['deposit_held'])))),
              if (bill != null)
                KasaKeyValue('Still to pay', Text(formatCurrency(toDouble(home['outstanding_balance'])))),
              const SizedBox(height: 4),
              Text('Your deposit is refunded after the move-out inspection, less anything still owed.',
                  style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
            ]),
          ),
        ],
      ),
    );
  }
}
