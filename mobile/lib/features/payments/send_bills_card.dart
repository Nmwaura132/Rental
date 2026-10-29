import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_primitives.dart';

const _url = '/api/v1/payments/invoices/send-month/';

/// The coming month's billing: which month, how many tenants, how many sent.
final sendMonthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final resp = await ref.watch(dioProvider).get(_url);
  return Map<String, dynamic>.from(resp.data as Map);
});

/// Lets a landlord text the coming month's bills now, typically right after
/// reading the meters, instead of waiting for 06:00 on the 1st.
///
/// Hides itself when there is no one to bill or every bill has gone out.
class SendBillsCard extends ConsumerStatefulWidget {
  const SendBillsCard({super.key, this.onSent});

  /// Lets the host refresh what it shows once bills exist.
  final VoidCallback? onSent;

  @override
  ConsumerState<SendBillsCard> createState() => _SendBillsCardState();
}

class _SendBillsCardState extends ConsumerState<SendBillsCard> {
  bool _busy = false;

  Future<void> _send(String month, int count) async {
    final cs = Theme.of(context).colorScheme;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Send $month bills to $count ${count == 1 ? 'tenant' : 'tenants'}?',
                style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Each tenant is texted their rent and any bills like water, with how to pay. '
              'Enter this month\'s meter readings first, or water is left off.',
              style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
            ),
            const SizedBox(height: 16),
            KasaButton(label: 'Send bills', onTap: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            KasaButton(label: 'Not yet', variant: KasaButtonVariant.ghost, onTap: () => Navigator.pop(ctx, false)),
          ]),
        ),
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final resp = await ref.read(dioProvider).post(_url);
      final sent = (resp.data['sent'] as num?)?.toInt() ?? 0;
      ref.invalidate(sendMonthProvider);
      widget.onSent?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$month bills sent to $sent ${sent == 1 ? 'tenant' : 'tenants'}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(sendMonthProvider).valueOrNull;
    if (data == null) return const SizedBox.shrink();

    final tenancies = (data['tenancies'] as num?)?.toInt() ?? 0;
    final sent = (data['already_sent'] as num?)?.toInt() ?? 0;
    final toSend = tenancies - sent;
    if (toSend <= 0) return const SizedBox.shrink();

    final month = DateFormat('MMMM').format(DateTime.parse('${data['period']}'));
    // The gap below belongs to the card, so a hidden card leaves none.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: KasaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$month bills', style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text(
          sent == 0
              ? '$toSend ${toSend == 1 ? 'tenant' : 'tenants'} to bill. They go out by themselves '
                  'at 6am on the 1st, or send them now.'
              : '$sent sent, $toSend still to send.',
          style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
        ),
        const SizedBox(height: 12),
        KasaButton(
          label: 'Send $month bills now',
          isLoading: _busy,
          onTap: _busy ? null : () => _send(month, toSend),
        ),
      ]),
      ),
    );
  }
}
