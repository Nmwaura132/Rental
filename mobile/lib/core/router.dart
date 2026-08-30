import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


import '../features/auth/login_screen.dart';
import 'auth/biometric_service.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/properties/properties_screen.dart';
import '../features/properties/property_detail_screen.dart';
import '../features/properties/unit_detail_screen.dart';
import '../features/payments/invoices_screen.dart';
import '../features/payments/reports_screen.dart';
import '../features/payments/tax_screen.dart';
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

      // WHY this runs before the signed-out check, and keys off the refresh
      // token rather than the access token: after signing out there is no
      // access token, but the refresh token is deliberately kept so a
      // fingerprint can still get back in. Both that case and a live session
      // on cold start are "sealed until the sensor says otherwise", and /login
      // is where that check happens.
      if (!ref.read(sessionUnlockedProvider)) {
        // Carry the verdict in the URL so LoginScreen knows on its first build
        // whether it is a sign-in form or an unlock screen. Deciding it there
        // would mean an async gap on every sign-in.
        final lock = await ref.read(biometricServiceProvider).lockState();
        final params = state.uri.queryParameters;

        if (lock == SessionLockState.locked) {
          final alreadyLocked = isGoingToLogin && params['locked'] == '1';
          return alreadyLocked ? null : '/login?locked=1';
        }
        if (lock == SessionLockState.expired) {
          final alreadyExpired = isGoingToLogin && params['expired'] == '1';
          return alreadyExpired ? null : '/login?expired=1';
        }
      }

      if (!isLoggedIn && !isGoingToLogin) return '/login';
      if (isLoggedIn && isGoingToLogin) return '/dashboard';
      // Block tenant-restricted routes
      if (isLoggedIn) {
        // Use cached Riverpod future so we bypass platform channel overhead on every navigation hop
        final role = await ref.read(userRoleProvider.future);
        // /tax is the landlord's own KRA liability; the API refuses it for
        // anyone else, so routing a tenant there would only show them a 403.
        const tenantRestricted = ['/properties', '/tenants', '/reports', '/tax'];
        if (role == 'tenant' &&
            tenantRestricted.any(
                (p) => state.matchedLocation.startsWith(p))) {
          return '/dashboard';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(
          isLocked: state.uri.queryParameters['locked'] == '1',
          hasExpired: state.uri.queryParameters['expired'] == '1',
        ),
      ),
      // Global routes without Bottom Nav
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/tax', builder: (_, __) => const TaxScreen()),
        
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
                    routes: [
                      GoRoute(
                        path: 'units/:unitId',
                        builder: (context, state) {
                          final unitId = int.tryParse(
                                  state.pathParameters['unitId'] ?? '') ??
                              0;
                          return UnitDetailScreen(unitId: unitId);
                        },
                      ),
                    ],
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
  // Mirrors whether the ACTIVE branch's own nested Navigator still has
  // something to pop, kept in sync by the NavigationNotification listener
  // below. Used to tell "deep inside a branch" apart from "at a branch root".
  bool _branchCanPop = false;

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
    final isOnHomeTab = widget.navigationShell.currentIndex == 0;

    final shell = Scaffold(
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
        child: NotificationListener<NavigationNotification>(
          onNotification: (notification) {
            final nextBranchCanPop = notification.canHandlePop;
            if (nextBranchCanPop != _branchCanPop) {
              setState(() => _branchCanPop = nextBranchCanPop);
            }
            // WHY stop propagation (true) rather than the `false` that
            // NavigatorPopHandler uses: WidgetsApp's root handler forwards
            // whatever canHandlePop it receives straight to the engine as
            // setFrameworkHandlesBack(). At a branch root the branch Navigator
            // correctly reports canHandlePop: false — nothing to pop *within*
            // the branch — and letting that reach WidgetsApp unregisters
            // Flutter's back callback, so Android's default finish() runs and
            // the app exits without PopScope ever being consulted.
            // NavigatorPopHandler can forward it because there the two agree;
            // here they are inverted (the branch cannot pop, yet we still want
            // the framework to handle Back so we can fall back to Home), so it
            // must stop here and leave PopScope as the only voice the engine
            // hears.
            return true;
          },
          child: widget.navigationShell,
        ),
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

    // WHY: StatefulShellRoute.indexedStack pops each branch's OWN stack on
    // Back, but never falls back to branch 0 first — once a branch is at its
    // root, Back exits the app outright. That left any single tab switch
    // (Props, Tenants, Bills, Fix) one Back press from closing Kasa, with no
    // way home. Intercept only the "branch is already at its own root" case:
    // Back there returns to Home, while Back on Home, or Back deeper inside a
    // branch's own stack, behaves normally.
    return PopScope(
      canPop: isOnHomeTab || _branchCanPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.navigationShell.goBranch(0, initialLocation: true);
      },
      child: shell,
    );
  }
}
