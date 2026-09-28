import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_primitives.dart';
import 'unit_numbering.dart';

/// Moves every unit in a property onto the landlord's numbering in one step —
/// for buildings created before house numbers could be chosen, which came out
/// as 101, 102, 201…
class RenumberUnitsScreen extends ConsumerStatefulWidget {
  const RenumberUnitsScreen({
    super.key,
    required this.propertyId,
    required this.units,
  });

  final int propertyId;
  final List<Map<String, dynamic>> units;

  @override
  ConsumerState<RenumberUnitsScreen> createState() => _RenumberUnitsScreenState();
}

class _RenumberUnitsScreenState extends ConsumerState<RenumberUnitsScreen> {
  NumberingStyle _style = NumberingStyle.floorLetter;
  bool _hasGround = true;
  bool _saving = false;
  late final List<Map<String, dynamic>> _ordered;
  late final Map<int, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _ordered = [...widget.units]..sort(_byFloorThenNumber);
    _controllers = {
      for (final u in _ordered) u['id'] as int: TextEditingController(),
    };
    _applyStyle();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Floor first, then numerically where the numbers allow, so 2 sorts before
  /// 10 and 101 before 102.
  static int _byFloorThenNumber(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byFloor = ((a['floor'] as int?) ?? 0).compareTo((b['floor'] as int?) ?? 0);
    if (byFloor != 0) return byFloor;
    final na = int.tryParse(RegExp(r'\d+').stringMatch('${a['unit_number']}') ?? '');
    final nb = int.tryParse(RegExp(r'\d+').stringMatch('${b['unit_number']}') ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return '${a['unit_number']}'.compareTo('${b['unit_number']}');
  }

  void _applyStyle() {
    final floors = _ordered.map((u) => (u['floor'] as int?) ?? 0).toSet().toList()..sort();
    final positionOnFloor = <int, int>{};
    for (var i = 0; i < _ordered.length; i++) {
      final unit = _ordered[i];
      final floor = (unit['floor'] as int?) ?? 0;
      final position = positionOnFloor.update(floor, (p) => p + 1, ifAbsent: () => 0);
      _controllers[unit['id'] as int]!.text = houseNumber(
        _style,
        floorIndex: floors.indexOf(floor),
        position: position,
        runningIndex: i,
        hasGround: _hasGround,
      );
    }
  }

  Set<String> get _duplicates {
    final seen = <String>{};
    final twice = <String>{};
    for (final c in _controllers.values) {
      final n = c.text.trim().toUpperCase();
      if (n.isNotEmpty && !seen.add(n)) twice.add(n);
    }
    return twice;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(dioProvider).post(
        '/api/v1/properties/${widget.propertyId}/renumber/',
        data: {
          'units': [
            for (final u in _ordered)
              {'id': u['id'], 'unit_number': _controllers[u['id']]!.text.trim()},
          ],
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(const SnackBar(
        content: Text('Units renumbered.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duplicates = _duplicates;
    final hasBlank = _controllers.values.any((c) => c.text.trim().isEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Renumber units')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                NumberingStylePicker(
                  style: _style,
                  hasGround: _hasGround,
                  onChanged: (style, hasGround) => setState(() {
                    _style = style;
                    _hasGround = hasGround;
                    _applyStyle();
                  }),
                ),
                const SizedBox(height: 8),
                KasaCard(
                  accent: KasaCardAccent.tertiary,
                  padding: const EdgeInsets.all(12),
                  showShadow: false,
                  child: Text(
                    'Tenants pay using the new numbers from their next bill. '
                    'A payment made with an old number is not lost — it '
                    'appears under "payments to assign".',
                    style: GoogleFonts.inter(fontSize: 12, color: cs.tertiaryInk),
                  ),
                ),
                const SizedBox(height: 16),
                for (final unit in _ordered) ...[
                  _RenameRow(
                    oldNumber: '${unit['unit_number']}',
                    controller: _controllers[unit['id'] as int]!,
                    isDuplicate: duplicates.contains(
                        _controllers[unit['id'] as int]!.text.trim().toUpperCase()),
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: KasaButton(
                label: 'SAVE NEW NUMBERS',
                variant: KasaButtonVariant.primary,
                isLoading: _saving,
                onTap: (_saving || duplicates.isNotEmpty || hasBlank) ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameRow extends StatelessWidget {
  const _RenameRow({
    required this.oldNumber,
    required this.controller,
    required this.isDuplicate,
    required this.onChanged,
  });

  final String oldNumber;
  final TextEditingController controller;
  final bool isDuplicate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unchanged = controller.text.trim() == oldNumber;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            oldNumber,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 15,
              color: cs.kasaTextSub,
              decoration: unchanged ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
        Icon(Icons.arrow_forward, size: 16, color: cs.kasaTextSub),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              isDense: true,
              errorText: isDuplicate
                  ? 'Used twice'
                  : controller.text.trim().isEmpty
                      ? 'Required'
                      : null,
            ),
          ),
        ),
      ],
    );
  }
}
