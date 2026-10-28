import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'features/account/presentation/account_screen.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/catalog/presentation/catalog_screen.dart';
import 'features/catalog/presentation/product_screen.dart';
import 'features/payments/payments.dart';
import 'features/payments/commerce.dart';
import 'shared/widgets.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    overridePlatformDefaultLocation: true,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            _AppShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CatalogScreen()),
          GoRoute(
            path: '/categories',
            builder: (_, _) => const CategoriesScreen(),
          ),
          GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
          GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
        ],
      ),
      GoRoute(
        path: '/auth',
        builder: (_, state) => AuthScreen(
          next: safeDestination(state.uri.queryParameters['next']),
        ),
      ),
      GoRoute(
        path: '/auth/update-password',
        builder: (_, _) => const AuthScreen(updatePassword: true),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (_, state) => ProductScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: '/checkout/:id',
        builder: (_, state) =>
            CheckoutScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => OrderScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(path: '/selling', builder: (_, _) => const SellerCenterScreen()),
    ],
    errorBuilder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text(appName),
      ),
      body: InfoPanel(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message: 'Let’s get back to your next build.',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go home'),
        ),
      ),
    ),
  );
  final subscription = ref
      .watch(supabaseClientProvider)
      ?.auth
      .onAuthStateChange
      .listen(
        (event) {
          if (event.event == AuthChangeEvent.passwordRecovery) {
            // An in-app recovery OTP keeps its form and verified recovery state.
            if (!ref
                .read(authControllerProvider.notifier)
                .isRecoveringPassword) {
              router.go('/auth/update-password');
            }
          } else if (event.event == AuthChangeEvent.signedIn) {
            final uri = router.routeInformationProvider.value.uri;
            // The auth form navigates only after its operation has completed.
            if (uri.path == '/auth/callback') {
              router.go(safeDestination(uri.queryParameters['next']));
            }
          }
        },
        onError: (Object error) {
          /* Auth UI and session provider expose recoverable failures. */
        },
      );
  ref.onDispose(() {
    subscription?.cancel();
    router.dispose();
  });
  return router;
});

class RigMarketApp extends ConsumerWidget {
  const RigMarketApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(startupErrorProvider);
    if (issue != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          body: SafeArea(
            child: InfoPanel(
              icon: Icons.settings_outlined,
              title: 'Check your app configuration',
              message: issue,
            ),
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    const destinations = ['/', '/categories', '/cart', '/orders', '/account'];
    final index = destinations.indexOf(path).clamp(0, 4);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: path == '/' ? null : const AppBackButton(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: blue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.memory_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                'PH · PHP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const PreviewNotice(),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (index) => context.go(destinations[index]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Categories',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
