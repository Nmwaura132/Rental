import 'package:flutter/material.dart';

/// How a building's house numbers are laid out. The number is what tenants
/// type after the landlord's account when they pay ("623943#G1"), so Kasa
/// follows the landlord's scheme rather than inventing one.
enum NumberingStyle {
  floorLetter('Floor + letter', 'G1, G2 · 1A, 1B'),
  floorNumber('Floor + number', 'G01, G02 · 101, 102'),
  letterNumber('Letter + number', 'A1, A2 · B1, B2'),
  running('Running numbers', '1, 2, 3, 4');

  const NumberingStyle(this.label, this.example);
  final String label;
  final String example;
}

const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

String _letter(int i) => i < _letters.length ? _letters[i] : '${i + 1}';

/// The house number for the [position]th unit on the [floorIndex]th floor
/// counting up from the bottom. [runningIndex] is its place in the whole
/// building. With [hasGround], the bottom floor is the ground floor ("G").
String houseNumber(
  NumberingStyle style, {
  required int floorIndex,
  required int position,
  required int runningIndex,
  required bool hasGround,
}) {
  final isGround = hasGround && floorIndex == 0;
  final floor = hasGround ? floorIndex : floorIndex + 1;
  return switch (style) {
    NumberingStyle.floorLetter =>
      isGround ? 'G${position + 1}' : '$floor${_letter(position)}',
    NumberingStyle.floorNumber => isGround
        ? 'G${(position + 1).toString().padLeft(2, '0')}'
        : '$floor${(position + 1).toString().padLeft(2, '0')}',
    NumberingStyle.letterNumber => '${_letter(floorIndex)}${position + 1}',
    NumberingStyle.running => '${runningIndex + 1}',
  };
}

/// Numbers for a building of [floors] floors with [perFloor] units each.
List<String> layoutNumbers(
  NumberingStyle style, {
  required int floors,
  required int perFloor,
  required bool hasGround,
}) =>
    [
      for (int f = 0; f < floors; f++)
        for (int p = 0; p < perFloor; p++)
          houseNumber(style,
              floorIndex: f,
              position: p,
              runningIndex: f * perFloor + p,
              hasGround: hasGround),
    ];

/// The floor a house number sits on: "G1" is the ground floor, "3B" the third.
/// Only meaningful for the floor-first styles; anything else is filed at 0.
int floorOf(String number, {required bool hasGround}) {
  if (number.toUpperCase().startsWith('G')) return 0;
  final digits = int.tryParse(RegExp(r'^\d+').stringMatch(number) ?? '');
  if (digits == null) return 0;
  // "101" is floor 1; "1A" is floor 1.
  final floor = digits >= 100 ? digits ~/ 100 : digits;
  return hasGround ? floor : floor - 1;
}

/// Style dropdown plus the ground-floor switch.
class NumberingStylePicker extends StatelessWidget {
  const NumberingStylePicker({
    super.key,
    required this.style,
    required this.hasGround,
    required this.onChanged,
  });

  final NumberingStyle style;
  final bool hasGround;
  final void Function(NumberingStyle style, bool hasGround) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<NumberingStyle>(
          isExpanded: true,
          initialValue: style,
          decoration: const InputDecoration(labelText: 'Numbering style'),
          items: [
            for (final s in NumberingStyle.values)
              DropdownMenuItem(
                value: s,
                child: Text('${s.label}  ·  ${s.example}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (s) => onChanged(s ?? style, hasGround),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ground floor has units'),
          subtitle: const Text('Off if numbering starts on the first floor'),
          value: hasGround,
          onChanged: (v) => onChanged(style, v),
        ),
      ],
    );
  }
}

/// Orders house numbers the way a person would: G1, G2, G10, then 1A, 1B, 2A.
/// Digit runs compare as numbers, so "G2" comes before "G10".
int compareUnitNumbers(String a, String b) {
  final runs = RegExp(r'\d+|\D+');
  final pa = runs.allMatches(a).map((m) => m[0]!).toList();
  final pb = runs.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
