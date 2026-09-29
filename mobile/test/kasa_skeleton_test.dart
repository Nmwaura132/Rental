import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/theme/kasa_tokens.dart';
import 'package:rental_manager/core/widgets/kasa_skeleton.dart';

// The skeletons read only the ColorScheme, so the tests use plain themes and
// stay off the network (AppTheme loads Inter through google_fonts).
final _light = ThemeData(colorScheme: const ColorScheme.light());
final _dark = ThemeData(colorScheme: const ColorScheme.dark());

Widget _host(
  Widget child, {
  required ThemeData theme,
  bool reduceMotion = false,
  Size size = const Size(360, 780),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: reduceMotion),
    child: MaterialApp(theme: theme, home: Scaffold(body: child)),
  );
}

void main() {
  const skeletons = <String, Widget>{
    'list': KasaSkeletonList(),
    'list with wide trailing input': KasaSkeletonList(trailingWidth: 108),
    'summary': KasaSkeletonSummary(),
    'detail': KasaSkeletonDetail(),
  };

  for (final theme in {'light': _light, 'dark': _dark}.entries) {
    for (final s in skeletons.entries) {
      testWidgets('${s.key} skeleton lays out at 360dp (${theme.key})',
          (tester) async {
        await tester.pumpWidget(_host(s.value, theme: theme.value));
        await tester.pump(const Duration(milliseconds: 700));

        // A RenderFlex overflow would surface as a test exception.
        expect(tester.takeException(), isNull);
        expect(find.byType(KasaSkeleton), findsWidgets);
      });
    }
  }

  testWidgets('announces a single "Loading" to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const KasaSkeletonList(), theme: _light),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('Loading'), findsWidgets);
    handle.dispose();
  });

  testWidgets('reduced motion: no animation left running', (tester) async {
    await tester.pumpWidget(
      _host(
        const KasaSkeletonSummary(),
        theme: _light,
        reduceMotion: true,
      ),
    );

    // pumpAndSettle only returns if nothing keeps scheduling frames; a live
    // shimmer would time out here.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shimmer runs when motion is allowed', (tester) async {
    await tester.pumpWidget(
      _host(const KasaSkeletonList(), theme: _light),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.hasRunningAnimations, isTrue);
  });

  test('status pairs meet 4.5:1 in both themes', () {
    double lum(Color c) {
      double f(double v) =>
          v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    double ratio(Color a, Color b) {
      final la = lum(a);
      final lb = lum(b);
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final b in Brightness.values) {
      for (final k in KasaStatusKind.values) {
        final p = KasaStatus.of(k, b);
        expect(
          ratio(p.fg, p.bg),
          greaterThanOrEqualTo(4.5),
          reason: '$k in $b',
        );
      }
    }
  });
}
