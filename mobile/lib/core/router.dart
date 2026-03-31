import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

const _storage = FlutterSecureStorage();

// Stable root navigator key — required for useRootNavigator:true to work
// correctly inside StatefulShellRoute. Without this, showModalBottomSheet and
// showDialog with useRootNavigator:true have no reliable root to target.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

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
      // Global routes without Bottom Nav
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        
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

    final navItems = isTenant
        ? [
            (icon: Icons.dashboard, label: 'Home', index: 0),
            (icon: Icons.receipt_long, label: 'Invoices', index: 3),
            (icon: Icons.construction, label: 'Maintenance', index: 4),
          ]
        : [
            (icon: Icons.dashboard, label: 'Home', index: 0),
            (icon: Icons.home_work, label: 'Properties', index: 1),
            (icon: Icons.people, label: 'Tenants', index: 2),
            (icon: Icons.receipt_long, label: 'Invoices', index: 3),
            (icon: Icons.construction, label: 'Maintenance', index: 4),
          ];

    int selectedUITab = navItems.indexWhere((e) => e.index == widget.navigationShell.currentIndex);
    if (selectedUITab < 0) selectedUITab = 0;

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
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        offset: _isVisible ? Offset.zero : const Offset(0, 1.2),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(navItems.length, (i) {
                      final item = navItems[i];
                      final isSelected = selectedUITab == i;
                      final color = isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant;
                      
                      return GestureDetector(
                        onTap: () {
                          widget.navigationShell.goBranch(
                            item.index,
                            initialLocation: item.index == widget.navigationShell.currentIndex,
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(item.icon, color: color),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
