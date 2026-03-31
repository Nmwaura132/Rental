import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/properties/properties_screen.dart';
import '../features/properties/property_detail_screen.dart';
import '../features/payments/invoices_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/tenants/tenants_screen.dart';
import '../features/maintenance/maintenance_screen.dart';
import '../features/profile/profile_screen.dart';
import 'providers/user_role_provider.dart';

// ignore: library_private_types_in_public_api
export 'router.dart';

const _storage = FlutterSecureStorage();

// Stable navigator keys — required for useRootNavigator:true to work
// correctly inside ShellRoute. Without these, showModalBottomSheet and
// showDialog with useRootNavigator:true have no reliable root to target.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    redirect: (context, state) async {
      final token = await _storage.read(key: 'access_token');
      final isLoggedIn = token != null;
      final isGoingToLogin = state.matchedLocation == '/login';
      if (!isLoggedIn && !isGoingToLogin) return '/login';
      if (isLoggedIn && isGoingToLogin) return '/dashboard';
      // Block tenant-restricted routes
      if (isLoggedIn) {
        final role = await _storage.read(key: 'user_role');
        const tenantRestricted = ['/properties', '/tenants'];
        if (role == 'tenant' &&
            tenantRestricted.any(
                (p) => state.matchedLocation.startsWith(p))) {
          return '/dashboard';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/properties',
            builder: (_, __) => const PropertiesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                  return PropertyDetailScreen(propertyId: id);
                },
              ),
            ],
          ),
          GoRoute(path: '/tenants', builder: (_, __) => const TenantsScreen()),
          GoRoute(path: '/invoices', builder: (_, __) => const InvoicesScreen()),
          GoRoute(path: '/maintenance', builder: (_, __) => const MaintenanceScreen()),
          GoRoute(
              path: '/notifications',
              builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final role = ref.watch(userRoleProvider).valueOrNull;
    final isTenant = role == 'tenant';

    // Tenants: 3 tabs. Landlord/caretaker/loading: all 5 tabs.
    final navItems = isTenant
        ? [
            (icon: Icons.dashboard, label: 'Home', path: '/dashboard'),
            (icon: Icons.receipt_long, label: 'Invoices', path: '/invoices'),
            (icon: Icons.construction, label: 'Maintenance', path: '/maintenance'),
          ]
        : [
            (icon: Icons.dashboard, label: 'Home', path: '/dashboard'),
            (icon: Icons.home_work, label: 'Properties', path: '/properties'),
            (icon: Icons.people, label: 'Tenants', path: '/tenants'),
            (icon: Icons.receipt_long, label: 'Invoices', path: '/invoices'),
            (icon: Icons.construction, label: 'Maintenance', path: '/maintenance'),
          ];

    // Determine selected index — property detail (/properties/123) maps to properties tab
    int selectedIndex = navItems.indexWhere((e) => location.startsWith(e.path));
    if (selectedIndex < 0) selectedIndex = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => context.go(navItems[i].path),
        destinations: navItems
            .map((e) => NavigationDestination(icon: Icon(e.icon), label: e.label))
            .toList(),
      ),
    );
  }
}
