import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

/// Deletes a tenant and everything kept about them, after showing the
/// landlord exactly what goes. True when the tenant was deleted.
///
/// WHY the server's count and not the app's: the bills and payments that
/// would be lost are only certain on the server, and a delete cannot be undone.
Future<bool> deleteTenant(BuildContext context, WidgetRef ref, int tenantId) async {
  final url = '/api/v1/auth/tenants/$tenantId/';
  final dio = ref.read(dioProvider);
  Map<String, dynamic> found;
  try {
    found = Map<String, dynamic>.from((await dio.get(url)).data as Map);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
    return false;
  }
  if (!context.mounted) return false;

  final yes = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    // Taller than half a small phone; scrolls rather than cutting off Delete.
    isScrollControlled: true,
    builder: (ctx) => _ConfirmSheet(found: found),
  );
  if (yes != true || !context.mounted) return false;

  try {
    await dio.delete(url);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${found['name']} deleted.')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiError(e)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
    return false;
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.found});
  final Map<String, dynamic> found;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canDelete = found['can_delete'] == true;
    final houses = (found['houses'] as List? ?? const []).join(', ');
    final bills = (found['bills'] as num?)?.toInt() ?? 0;
    final payments = (found['payments'] as num?)?.toInt() ?? 0;
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(canDelete ? 'Delete ${found['name']}?' : 'Cannot delete ${found['name']}',
              style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          if (!canDelete)
            Text('${found['reason']}', style: muted)
          else ...[
            Text('This removes them from Kasa for good. It cannot be undone.', style: muted),
            const SizedBox(height: 12),
            KasaCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(children: [
                if (houses.isNotEmpty) KasaKeyValue('House', Text(houses)),
                KasaKeyValue('Bills', Text('$bills')),
                KasaKeyValue(
                  'Payments',
                  Text(payments == 0 ? 'None' : '$payments · ${formatCurrency(toDouble(found['paid']))}'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Their house becomes vacant, and their bills, payments, repairs and messages are deleted.',
                style: muted),
          ],
          const SizedBox(height: 16),
          if (canDelete) ...[
            // The error colour, like the app's other deletes: this one cannot be undone.
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KasaRadius.md)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text('Delete tenant', style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          KasaButton(
            label: canDelete ? 'Keep' : 'OK',
            variant: KasaButtonVariant.ghost,
            onTap: () => Navigator.pop(context, false),
          ),
        ]),
      ),
    );
  }
}
