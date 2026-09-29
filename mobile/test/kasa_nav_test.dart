import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/providers/user_role_provider.dart';
import 'package:rental_manager/core/widgets/kasa_nav_bar.dart';
import 'package:rental_manager/features/more/more_screen.dart';

List<String> _labels(String? role) =>
    kasaNavItemsFor(role).map((e) => e.label).toList();

List<int> _branches(String? role) =>
    kasaNavItemsFor(role).map((e) => e.branch).toList();

Widget _moreHost(String role) {
  return ProviderScope(
    overrides: [userRoleProvider.overrideWith((ref) async => role)],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: const MoreScreen(),
    ),
  );
}

void main() {
  group('tab sets per role', () {
    test('landlord: Home, Properties, Money, Repairs, More', () {
      expect(_labels('landlord'),
          ['Home', 'Properties', 'Money', 'Repairs', 'More']);
      expect(_branches('landlord'), [
        ShellBranch.home,
        ShellBranch.properties,
        ShellBranch.money,
        ShellBranch.repairs,
        ShellBranch.more,
      ]);
    });

    test('tenant: Home, Pay, Repairs, Me and never Properties', () {
      expect(_labels('tenant'), ['Home', 'Pay', 'Repairs', 'Me']);
      expect(_branches('tenant'), isNot(contains(ShellBranch.properties)));
    });

    test('caretaker sees Readings but no money tab and no More', () {
      expect(_labels('caretaker'), ['Home', 'Units', 'Readings', 'Repairs']);
      expect(_branches('caretaker'), contains(ShellBranch.readings));
      expect(_branches('caretaker'), isNot(contains(ShellBranch.money)));
      expect(_branches('caretaker'), isNot(contains(ShellBranch.more)));
    });

    test('an unknown or still-loading role gets the landlord set', () {
      expect(_labels(null), _labels('landlord'));
    });

    test('every tab points at a real, distinct branch', () {
      for (final role in ['landlord', 'tenant', 'caretaker', null]) {
        final b = _branches(role);
        expect(b.toSet().length, b.length, reason: 'duplicate branch: $role');
        expect(b.every((i) => i >= 0 && i <= ShellBranch.readings), isTrue);
      }
    });

    test('Home is always the first tab (Back falls back to it)', () {
      for (final role in ['landlord', 'tenant', 'caretaker', null]) {
        expect(_branches(role).first, ShellBranch.home);
      }
    });
  });

  group('KasaNavBar', () {
    testWidgets('shows a word under every icon and reports taps by index',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            bottomNavigationBar: KasaNavBar(
              items: kasaNavItemsFor('landlord'),
              selectedIndex: 0,
              onSelected: (i) => tapped = i,
            ),
          ),
        ),
      );

      for (final label in _labels('landlord')) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Money'));
      await tester.pump();
      expect(tapped, 2);
    });

    testWidgets('marks the selected tab', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            bottomNavigationBar: KasaNavBar(
              items: kasaNavItemsFor('tenant'),
              selectedIndex: 2,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 2);
      expect(bar.destinations.length, 4);
    });
  });

  group('MoreScreen', () {
    testWidgets('landlord: tenants, reports, tax, notifications, profile',
        (tester) async {
      await tester.pumpWidget(_moreHost('landlord'));
      await tester.pumpAndSettle();

      expect(find.text('More'), findsOneWidget);
      for (final t in [
        'Tenants',
        'Reports',
        'Tax statement',
        'Notifications',
        'Profile and settings',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('tenant: titled Me, and never offered landlord screens',
        (tester) async {
      await tester.pumpWidget(_moreHost('tenant'));
      await tester.pumpAndSettle();

      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Profile and settings'), findsOneWidget);
      for (final t in ['Tenants', 'Reports', 'Tax statement']) {
        expect(find.text(t), findsNothing, reason: t);
      }
    });
  });
}
