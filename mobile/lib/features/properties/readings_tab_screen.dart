import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_skeleton.dart';
import '../dashboard/needs_attention.dart';
import 'meter_readings_screen.dart';
import 'properties_screen.dart';

/// The caretaker's Readings tab.
///
/// Readings are taken round a building, so the tab opens straight onto the
/// sheet when there is only one property to walk. With several, it lists them
/// with what is still unread, and each opens its own sheet inside the tab so
/// the bar stays in view.
class ReadingsTabScreen extends ConsumerWidget {
  const ReadingsTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final props = ref.watch(propertiesProvider);

    return props.when(
      loading: () => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Readings'),
        ),
        body: const KasaSkeletonList(trailingWidth: null),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Readings'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(KasaSpace.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(apiError(e), textAlign: TextAlign.center),
                const SizedBox(height: KasaSpace.lg),
                OutlinedButton(
                  onPressed: () => ref.invalidate(propertiesProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Readings'),
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(KasaSpace.xxl),
                child: Text(
                  'You do not look after any properties yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (list.length == 1) {
          final p = list.single as Map<String, dynamic>;
          return MeterReadingsScreen(
            key: ValueKey(p['id']),
            propertyId: p['id'] as int,
            propertyName: p['name']?.toString() ?? '',
          );
        }
        return _PropertyPicker(properties: list.cast<Map<String, dynamic>>());
      },
    );
  }
}

class _PropertyPicker extends ConsumerWidget {
  const _PropertyPicker({required this.properties});

  final List<Map<String, dynamic>> properties;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final missing = <int, MissingReadings>{
      for (final m in ref.watch(missingReadingsProvider).valueOrNull ?? const <MissingReadings>[])
        m.propertyId: m,
    };
    final settled = ref.watch(missingReadingsProvider).hasValue;
    final bottomClear = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Readings'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          KasaSpace.gutter,
          KasaSpace.sm,
          KasaSpace.gutter,
          KasaSpace.xxl + bottomClear,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(KasaRadius.md),
              border: Border.all(color: cs.kasaStroke, width: KasaBorders.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < properties.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: cs.kasaStroke),
                  Builder(builder: (context) {
                    final p = properties[i];
                    final m = missing[p['id']];
                    final status = m != null
                        ? '${m.missing} of ${m.total} ${m.total == 1 ? 'unit' : 'units'} to read'
                        : settled
                            ? 'All read'
                            : 'Checking';
                    return InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MeterReadingsScreen(
                            propertyId: p['id'] as int,
                            propertyName: p['name']?.toString() ?? '',
                          ),
                        ),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KasaSpace.lg,
                            vertical: KasaSpace.md,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['name']?.toString() ?? '',
                                      style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      status,
                                      style: tt.bodyMedium?.copyWith(
                                        color: m != null ? cs.onSurface : cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
