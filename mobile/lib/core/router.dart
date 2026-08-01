import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/properties/properties_screen.dart';
import '../features/properties/property_detail_screen.dart';
import '../features/payments/invoices_screen.dart';
import '../features/payments/reports_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/tenants/tenants_screen.dart';
import '../features/maintenance/maintenance_screen.dart';
import '../features/profile/profile_screen.dart';
import 'providers/user_role_provider.dart';
import 'navigation_key.dart';

const _storage = FlutterSecureStorage();

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
        // Use cached Riverpod future so we bypass platform channel overhead on every navigation hop
        final role = await ref.read(userRoleProvider.future);
        const tenantRestricted = ['/properties', '/tenants', '/reports'];
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
      // Global routes without Bottom Nav
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
        
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tenants', builder: (_, __) => const TenantsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/invoices', builder: (_, __) => const InvoicesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/maintenance', builder: (_, __) => const MaintenanceScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _isVisible = true;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(userRoleProvider).valueOrNull;
    final isTenant = role == 'tenant';

    // Design bundle labels: HOME / PROPS / TENANTS / BILLS / FIX
    final navItems = isTenant
        ? [
            (icon: Icons.grid_view_rounded,  label: 'HOME',    index: 0),
            (icon: Icons.receipt_long,        label: 'BILLS',   index: 3),
            (icon: Icons.construction,        label: 'FIX',     index: 4),
          ]
        : [
            (icon: Icons.grid_view_rounded,  label: 'HOME',    index: 0),
            (icon: Icons.home_work_outlined,  label: 'PROPS',   index: 1),
            (icon: Icons.people_outline,      label: 'TENANTS', index: 2),
            (icon: Icons.receipt_long,        label: 'BILLS',   index: 3),
            (icon: Icons.construction,        label: 'FIX',     index: 4),
          ];

    int selectedUITab = navItems.indexWhere((e) => e.index == widget.navigationShell.currentIndex);
    if (selectedUITab < 0) selectedUITab = 0;

    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.forward) {
            if (!_isVisible) setState(() => _isVisible = true);
          } else if (notification.direction == ScrollDirection.reverse) {
            if (_isVisible) setState(() => _isVisible = false);
          }
          return true;
        },
        child: widget.navigationShell,
      ),
      // Neo-brutalist pill nav — no glass blur, no soft shadow, hard-edge offset only.
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        offset: _isVisible ? Offset.zero : const Offset(0, 1.2),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outline, width: 2),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow,
                  offset: const Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              children: List.generate(navItems.length, (i) {
                final item = navItems[i];
                final isSelected = selectedUITab == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => widget.navigationShell.goBranch(
                      item.index,
                      initialLocation: item.index == widget.navigationShell.currentIndex,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: isSelected ? cs.secondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            size: 20,
                            color: isSelected ? cs.onSecondary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.label,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.02,
                              color: isSelected ? cs.onSecondary : cs.onSurfaceVariant,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
