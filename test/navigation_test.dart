import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rigmarket/src/app.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';
import 'package:rigmarket/src/features/catalog/application/catalog_providers.dart';
import 'package:rigmarket/src/features/payments/payments.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('a tab opened without history has a visible Back to Home', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider)..go('/orders');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RigMarketApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.canPop(), isFalse);
    await tester.tap(find.byKey(const Key('app-back')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Back prefers the previous page over its fallback destination', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider)..go('/cart');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RigMarketApp(),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/setup');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-back')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/cart');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final seller in [false, true]) {
    testWidgets(
      seller
          ? 'seller direct order Back returns to Seller Center'
          : 'checkout replacement order Back returns to Orders',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(
                const User(
                  id: 'buyer',
                  appMetadata: {},
                  userMetadata: {},
                  aud: 'authenticated',
                  createdAt: '2026-10-28T00:00:00Z',
                ),
              ),
            ),
            orderProvider('order1').overrideWith(
              (ref) async => {
                'role': seller ? 'seller' : 'buyer',
                'order': {
                  'id': 'order1',
                  'product_name': 'Keyboard',
                  'quantity': 1,
                  'total_centavos': 10000,
                  'status': 'cod_pending',
                  'fulfillment': 'delivery',
                  'payment_method': 'cod',
                  'fulfillment_status': 'processing',
                },
              },
            ),
            ordersProvider.overrideWith((ref) async => []),
            sellerProfileProvider.overrideWith(
              (ref) async => {'shop_name': 'COMPARTS', 'status': 'approved'},
            ),
            sellerOrdersProvider.overrideWith((ref) async => []),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(routerProvider)..go('/orders/order1');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const RigMarketApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);
        await tester.tap(find.byKey(const Key('app-back')));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          seller ? '/selling' : '/orders',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'filter sheet Back dismisses its draft without applying changes',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RigMarketApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Sort and filter'));
      await tester.tap(find.byTooltip('Sort and filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'used'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modal-back')));
      await tester.pumpAndSettle();
      expect(find.text('Make it your build'), findsNothing);
      expect(container.read(catalogFiltersProvider).condition, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
