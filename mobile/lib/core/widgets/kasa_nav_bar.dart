import 'package:flutter/material.dart';

import '../theme/kasa_tokens.dart';

/// Indices of the shell branches in router.dart's StatefulShellRoute.
///
/// WHY named constants: the tab bar is a *presentation* of these branches, and a
/// role can show a subset of them in any order. Keeping the indices here (next
/// to the tab definitions) means router.dart and the tab bar cannot silently
/// disagree about which branch is which.
class ShellBranch {
  ShellBranch._();

  static const home = 0;
  static const properties = 1;

  /// "More" for landlords and "Me" for tenants: one branch, role-aware content.
  /// It also hosts /tenants so the bar stays visible on the tenants directory.
  static const more = 2;
  static const money = 3; // /invoices
  static const repairs = 4; // /maintenance
  static const readings = 5; // /readings (caretaker only)
}

class KasaNavItem {
  const KasaNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.branch,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// The shell branch this tab opens.
  final int branch;
}

const _home = KasaNavItem(
  label: 'Home',
  icon: Icons.home_outlined,
  selectedIcon: Icons.home_rounded,
  branch: ShellBranch.home,
);
const _repairs = KasaNavItem(
  label: 'Repairs',
  icon: Icons.build_outlined,
  selectedIcon: Icons.build_rounded,
  branch: ShellBranch.repairs,
);

/// Tabs per role.
///
///  * landlord  Home · Properties · Money · Repairs · More
///  * caretaker Home · Units · Readings · Repairs   (no money tab)
///  * tenant    Home · Pay · Repairs · Me
///
/// An unknown role (still loading) gets the landlord set: the route guard, not
/// the tab bar, is what keeps a tenant out of landlord screens.
List<KasaNavItem> kasaNavItemsFor(String? role) {
  switch (role) {
    case 'tenant':
      return const [
        _home,
        KasaNavItem(
          label: 'Pay',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          branch: ShellBranch.money,
        ),
        _repairs,
        KasaNavItem(
          label: 'Me',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          branch: ShellBranch.more,
        ),
      ];
    case 'caretaker':
      return const [
        _home,
        KasaNavItem(
          label: 'Units',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment_rounded,
          branch: ShellBranch.properties,
        ),
        KasaNavItem(
          label: 'Readings',
          icon: Icons.speed_outlined,
          selectedIcon: Icons.speed_rounded,
          branch: ShellBranch.readings,
        ),
        _repairs,
      ];
    default:
      return const [
        _home,
        KasaNavItem(
          label: 'Properties',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment_rounded,
          branch: ShellBranch.properties,
        ),
        KasaNavItem(
          label: 'Money',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          branch: ShellBranch.money,
        ),
        _repairs,
        KasaNavItem(
          label: 'More',
          icon: Icons.more_horiz_rounded,
          selectedIcon: Icons.more_horiz_rounded,
          branch: ShellBranch.more,
        ),
      ];
  }
}

/// Flat bottom tab bar: hairline top border, accent pill behind the current
/// tab, a word under every icon.
///
/// WHY Material's NavigationBar rather than a hand-built row: it reports each
/// tab to TalkBack as "Tab 2 of 5, selected" and gives a 48dp+ target for free,
/// which the old GestureDetector row did neither. Colours, indicator and label
/// styles come from AppTheme.navigationBarTheme so the bar is themed in one
/// place.
class KasaNavBar extends StatelessWidget {
  const KasaNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<KasaNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.kasaStroke, width: KasaBorders.hairline),
        ),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
