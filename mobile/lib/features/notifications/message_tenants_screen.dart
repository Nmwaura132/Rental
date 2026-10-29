import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

const _url = '/api/v1/notifications/message-tenants/';
const _max = 300;

/// The landlord's current tenancies, to pick one tenant from.
final _tenanciesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await fetchAllPages(ref.watch(dioProvider), '/api/v1/tenants/tenancies/',
      queryParameters: {'status': 'active'});
  return rows.cast<Map<String, dynamic>>();
});

final _buildingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await fetchAllPages(ref.watch(dioProvider), '/api/v1/properties/');
  return rows.cast<Map<String, dynamic>>();
});

/// Who a message goes to: everyone, one building, or one tenant.
sealed class _To {
  const _To();
  Map<String, dynamic> get params;
}

class _Everyone extends _To {
  const _Everyone();
  @override
  Map<String, dynamic> get params => const {};
}

class _Building extends _To {
  const _Building(this.id, this.name);
  final int id;
  final String name;
  @override
  Map<String, dynamic> get params => {'property': id};
}

class _Tenant extends _To {
  const _Tenant(this.id, this.name);
  final int id;
  final String name;
  @override
  Map<String, dynamic> get params => {'tenancy': id};
}

/// A landlord's own SMS to their tenants: water off, a meeting, a reminder.
class MessageTenantsScreen extends ConsumerStatefulWidget {
  const MessageTenantsScreen({super.key});

  @override
  ConsumerState<MessageTenantsScreen> createState() => _MessageTenantsScreenState();
}

class _MessageTenantsScreenState extends ConsumerState<MessageTenantsScreen> {
  final _message = TextEditingController();
  _To _to = const _Everyone();
  int? _recipients;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _count();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _count() async {
    setState(() => _recipients = null);
    try {
      final resp = await ref.read(dioProvider).get(_url, queryParameters: _to.params);
      if (mounted) setState(() => _recipients = (resp.data['recipients'] as num).toInt());
    } catch (_) {
      // The send itself reports a real problem; the count is only a hint.
      if (mounted) setState(() => _recipients = null);
    }
  }

  void _pick(_To to) {
    setState(() => _to = to);
    _count();
  }

  String get _toLabel => switch (_to) {
        _Everyone() => 'All my tenants',
        _Building(:final name) => 'Everyone at $name',
        _Tenant(:final name) => name,
      };

  Future<void> _chooseRecipients() async {
    final buildings = ref.read(_buildingsProvider).valueOrNull ?? const [];
    final tenancies = ref.read(_tenanciesProvider).valueOrNull ?? const [];
    final picked = await showModalBottomSheet<_To>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            KasaListGroup(children: [
              KasaListRow(
                leading: const KasaLeadIcon(Icons.groups_outlined),
                title: 'All my tenants',
                onTap: () => Navigator.pop(ctx, const _Everyone()),
              ),
            ]),
            if (buildings.length > 1) ...[
              const SizedBox(height: 16),
              const KasaSectionHeader('A building'),
              const SizedBox(height: 8),
              KasaListGroup(children: [
                for (final b in buildings)
                  KasaListRow(
                    leading: const KasaLeadIcon(Icons.apartment_rounded),
                    title: '${b['name']}',
                    onTap: () => Navigator.pop(ctx, _Building(b['id'] as int, '${b['name']}')),
                  ),
              ]),
            ],
            if (tenancies.isNotEmpty) ...[
              const SizedBox(height: 16),
              const KasaSectionHeader('One tenant'),
              const SizedBox(height: 8),
              KasaListGroup(children: [
                for (final t in tenancies)
                  KasaListRow(
                    leading: const KasaLeadIcon(Icons.person_outline_rounded),
                    title: '${t['tenant_name'] ?? 'Tenant'}',
                    subtitle: 'Unit ${t['unit_number']} · ${t['property_name']}',
                    onTap: () => Navigator.pop(ctx, _Tenant(t['id'] as int, '${t['tenant_name'] ?? 'Tenant'}')),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
    if (picked != null) _pick(picked);
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    final n = _recipients ?? 0;
    final cs = Theme.of(context).colorScheme;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Send to $n ${n == 1 ? 'tenant' : 'tenants'}?',
                style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('Each gets it as an SMS starting with their building\'s name. It cannot be unsent.',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
            const SizedBox(height: 16),
            KasaButton(label: 'Send', onTap: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            KasaButton(label: 'Not yet', variant: KasaButtonVariant.ghost, onTap: () => Navigator.pop(ctx, false)),
          ]),
        ),
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final resp = await ref.read(dioProvider).post(_url, data: {'message': text, ..._to.params});
      if (!mounted) return;
      final sent = (resp.data['sent'] as num).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent to $sent ${sent == 1 ? 'tenant' : 'tenants'}.')),
      );
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
    // Warm both lists so the recipient sheet opens already filled.
    ref.watch(_buildingsProvider);
    ref.watch(_tenanciesProvider);
    final length = _message.text.length;
    final n = _recipients;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(backgroundColor: cs.kasaBg, surfaceTintColor: Colors.transparent, title: const Text('Message tenants')),
      // WHY the button in the body: it stays above the keyboard while typing.
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              KasaListGroup(children: [
                KasaListRow(
                  leading: const KasaLeadIcon(Icons.send_outlined),
                  title: _toLabel,
                  subtitle: n == null ? 'Counting…' : '$n ${n == 1 ? 'tenant' : 'tenants'} · tap to change',
                  onTap: _chooseRecipients,
                ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                minLines: 4,
                maxLines: 8,
                maxLength: _max,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'e.g. Water will be off on Saturday from 9am to 1pm.',
                  alignLabelWithHint: true,
                ),
              ),
              Text(
                // An SMS holds 160 characters; longer ones cost two or more.
                length <= 160 ? '1 SMS each' : '${(length / 153).ceil()} SMS each',
                style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
              ),
            ],
          ),
        ),
        KasaActionBar(children: [
          KasaButton(
            label: n == null || n == 0 ? 'Send' : 'Send to $n ${n == 1 ? 'tenant' : 'tenants'}',
            isLoading: _busy,
            onTap: _busy || _message.text.trim().isEmpty || (n ?? 0) == 0 ? null : _send,
          ),
        ]),
      ]),
    );
  }
}
