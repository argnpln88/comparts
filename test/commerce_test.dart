import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';
import 'package:rigmarket/src/features/payments/payments.dart';
import 'package:rigmarket/src/features/payments/review_photos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommerceFake extends PaymentRepository {
  CommerceFake({this.pending}) : super(null);
  final Completer<Map<String, dynamic>>? pending;
  final calls = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic>? address;
  final uploaded = <String>[];
  @override
  Future<Map<String, dynamic>?> savedAddress() async => address;
  @override
  Future<void> saveAddress(Map<String, dynamic> value) async {
    address = value;
  }

  @override
  Future<String> uploadReviewPhoto(
    String orderId,
    Uint8List bytes,
    String extension,
  ) async {
    final path = '$orderId/item.$extension';
    uploaded.add(path);
    return path;
  }

  @override
  Future<Map<String, dynamic>> call(
    String function,
    Map<String, dynamic> body,
  ) async {
    calls.add((function, body));
    if (pending != null) return pending!.future;
    return {
      'order': {
        'id': 'order1',
        'status': function == 'checkout-create'
            ? 'creation_unknown'
            : 'cod_pending',
      },
    };
  }
}

class PhotoPickerFake extends ImagePicker {
  ImageSource? source;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR1cAAAAASUVORK5CYII=',
  );
  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse.empty();
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    return XFile.fromData(bytes, mimeType: 'image/png', name: 'item.png');
  }
}

User sampleUser() => const User(
  id: 'buyer',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-28T00:00:00Z',
);
void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'quantity changes preserve checkout drafts and wait for a fresh total',
    (tester) async {
      phoneSize(tester);
      final repo = CommerceFake()
        ..address = {
          'recipient': 'Sample Buyer',
          'phone': '09171234567',
          'address': '123 Sample Street, Barangay Demo',
          'city': 'Quezon City',
          'postal_code': '1100',
        };
      final updating = Completer<Map<String, dynamic>>();
      Map<String, dynamic> quote(int quantity) => {
        'product_name': 'Keyboard',
        'unit_price_centavos': 10000,
        'quantity': quantity,
        'total_centavos': 10000 * quantity,
      };
      final router = GoRouter(
        initialLocation: '/checkout/product1',
        routes: [
          GoRoute(
            path: '/checkout/:id',
            builder: (_, _) => const CheckoutScreen(productId: 'product1'),
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (_, _) => const Scaffold(body: Text('Order created')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(sampleUser()),
            ),
            paymentRepositoryProvider.overrideWithValue(repo),
            quoteProvider(('product1', 1))
                .overrideWith((ref) async => quote(1)),
            quoteProvider(('product1', 2))
                .overrideWith((ref) => updating.future),
            quoteProvider(('product1', 3))
                .overrideWith((ref) async => quote(3)),
            quoteProvider(('product1', 4)).overrideWith(
              (ref) async => throw StateError('Insufficient stock'),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Update address'));
      await tester.tap(find.text('Update address'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('shipping-recipient')));
      await tester.enterText(
        find.byKey(const Key('shipping-recipient')),
        'Edited Buyer',
      );
      await tester.ensureVisible(find.byKey(const Key('quantity-plus')));
      await tester.tap(find.byKey(const Key('quantity-plus')));
      await tester.pump();
      expect(find.byKey(const Key('quantity-input')), findsOneWidget);
      final place = find.text('Place order · Cash on delivery');
      await tester.ensureVisible(place);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(of: place, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Updating total…'), findsOneWidget);
      updating.complete(quote(2));
      await tester.pumpAndSettle();
      expect(find.text('Total: ₱200.00'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('shipping-recipient')));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('shipping-recipient')))
            .controller!
            .text,
        'Edited Buyer',
      );
      final input = find.byKey(const Key('quantity-input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '4');
      await tester.pumpAndSettle();
      await tester.ensureVisible(place);
      expect(find.text('Insufficient stock'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(of: place, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, '0');
      await tester.pumpAndSettle();
      await tester.ensureVisible(place);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(of: place, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, '3');
      await tester.pumpAndSettle();
      await tester.ensureVisible(place);
      expect(find.text('Total: ₱300.00'), findsOneWidget);
      await tester.tap(place);
      await tester.pumpAndSettle();
      expect(repo.calls.single.$2['quantity'], 3);
      expect(
        (repo.calls.single.$2['shipping_address'] as Map)['recipient'],
        'Edited Buyer',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a slow saved-address response preserves a typed address draft', (
    tester,
  ) async {
    phoneSize(tester);
    final loaded = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(sampleUser())),
          savedAddressProvider.overrideWith((ref) => loaded.future),
          quoteProvider(('product1', 1)).overrideWith(
            (ref) async => {
              'product_name': 'Keyboard',
              'unit_price_centavos': 10000,
              'total_centavos': 10000,
            },
          ),
        ],
        child: const MaterialApp(home: CheckoutScreen(productId: 'product1')),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('shipping-recipient')),
      'My address draft',
    );
    loaded.complete({
      'recipient': 'Saved Buyer',
      'phone': '09171234567',
      'address': '123 Saved Street, Barangay Demo',
      'city': 'Quezon City',
      'postal_code': '1100',
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('shipping-recipient')))
          .controller!
          .text,
      'My address draft',
    );
    expect(find.text('Use current address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving checkout during a request does not crash or reopen the order',
    (tester) async {
      phoneSize(tester);
      final pending = Completer<Map<String, dynamic>>();
      final repo = CommerceFake(pending: pending);
      final router = GoRouter(
        initialLocation: '/checkout/product1',
        routes: [
          GoRoute(
            path: '/checkout/:id',
            builder: (_, _) => const CheckoutScreen(productId: 'product1'),
          ),
          GoRoute(
            path: '/cart',
            builder: (_, _) => const Scaffold(body: Text('Returned to cart')),
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (_, _) =>
                const Scaffold(body: Text('Unexpected redirect')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(sampleUser()),
            ),
            paymentRepositoryProvider.overrideWithValue(repo),
            quoteProvider(('product1', 1)).overrideWith(
              (ref) async => {
                'product_name': 'Keyboard',
                'unit_price_centavos': 10000,
                'total_centavos': 10000,
              },
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'shipping-recipient': 'Sample Buyer',
        'shipping-phone': '09171234567',
        'shipping-address': '123 Sample Street',
        'shipping-city': 'Quezon City',
        'shipping-postal': '1100',
      }.entries) {
        await tester.ensureVisible(find.byKey(Key(entry.key)));
        await tester.enterText(find.byKey(Key(entry.key)), entry.value);
      }
      final place = find.text('Place order · Cash on delivery');
      await tester.ensureVisible(place);
      await tester.tap(place);
      await tester.pump();
      expect(repo.calls.length, 1);
      await tester.tap(find.byKey(const Key('app-back')));
      await tester.pumpAndSettle();
      pending.complete({
        'order': {'id': 'order1', 'status': 'cod_pending'},
      });
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/cart');
      expect(find.text('Returned to cart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final online in [false, true]) {
    testWidgets(
      online
          ? 'online checkout includes the validated shipping snapshot'
          : 'COD checkout validates address and never calls Xendit',
      (tester) async {
        phoneSize(tester);
        final repo = CommerceFake();
        final router = GoRouter(
          initialLocation: '/checkout/product1',
          routes: [
            GoRoute(
              path: '/checkout/:id',
              builder: (_, _) => const CheckoutScreen(productId: 'product1'),
            ),
            GoRoute(
              path: '/orders/:id',
              builder: (_, _) => const Scaffold(body: Text('Order created')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWith(
                (ref) => Stream.value(sampleUser()),
              ),
              paymentRepositoryProvider.overrideWithValue(repo),
              quoteProvider(('product1', 1)).overrideWith(
                (ref) async => {
                  'product_name': 'Ryzen 5 7600',
                  'unit_price_centavos': 1099500,
                  'total_centavos': 1099500,
                },
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        final place = find.text('Place order · Cash on delivery');
        await tester.ensureVisible(place);
        await tester.tap(place);
        await tester.pumpAndSettle();
        expect(repo.calls, isEmpty);
        for (final entry in {
          'shipping-recipient': 'Sample Buyer',
          'shipping-phone': '09171234567',
          'shipping-address': '123 Sample Street, Barangay Demo',
          'shipping-city': 'Quezon City',
          'shipping-postal': '1100',
        }.entries) {
          await tester.ensureVisible(find.byKey(Key(entry.key)));
          await tester.enterText(find.byKey(Key(entry.key)), entry.value);
        }
        if (online) {
          await tester.ensureVisible(find.byKey(const Key('payment-method')));
          await tester.tap(find.byKey(const Key('payment-method')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Online payment').last);
          await tester.pumpAndSettle();
        }
        final button = find.text(
          online ? 'Continue to payment' : 'Place order · Cash on delivery',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(repo.calls.length, 1);
        expect(
          repo.calls.single.$1,
          online ? 'checkout-create' : 'commerce-order',
        );
        expect(repo.calls.single.$2['expected_unit_price_centavos'], 1099500);
        expect(
          (repo.calls.single.$2['shipping_address'] as Map)['postal_code'],
          '1100',
        );
        expect(repo.calls.single.$2.containsKey('buyer_id'), isFalse);
        if (!online) expect(repo.calls.single.$2['action'], 'create_cod');
        expect(find.text('Order created'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<CommerceFake> openOrder(
    WidgetTester tester, {
    String role = 'buyer',
    String stage = 'processing',
    String method = 'cod',
    String? payment,
    PhotoPickerFake? picker,
  }) async {
    phoneSize(tester);
    final repo = CommerceFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(sampleUser())),
          paymentRepositoryProvider.overrideWithValue(repo),
          if (picker != null)
            reviewPhotoPickerProvider.overrideWithValue(picker),
          orderProvider('order1').overrideWith(
            (ref) async => {
              'role': role,
              'order': {
                'id': 'order1',
                'product_name': 'Mechanical Keyboard',
                'quantity': 1,
                'total_centavos': 249500,
                'status':
                    payment ?? (stage == 'delivered' ? 'paid' : 'cod_pending'),
                'payment_method': method,
                'fulfillment': 'delivery',
                'fulfillment_status': stage,
              },
              'events': [],
              'review': null,
            },
          ),
        ],
        child: const MaterialApp(home: OrderScreen(id: 'order1')),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets(
    'buyer can confirm receipt only after dispatch, with COD payment acknowledgement',
    (tester) async {
      final repo = await openOrder(tester, stage: 'shipped');
      expect(find.text('Mark out for delivery'), findsNothing);
      await tester.tap(find.byKey(const Key('order-receive')));
      await tester.pumpAndSettle();
      expect(find.textContaining('paid ₱2,495.00 in cash'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await tester.tap(find.text('I received it and paid'));
      await tester.pumpAndSettle();
      expect(repo.calls.single.$2['action'], 'receive');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'seller can dispatch but cannot acknowledge buyer receipt or review',
    (tester) async {
      await openOrder(tester, role: 'seller');
      expect(find.text('Mark out for delivery'), findsOneWidget);
      expect(find.byKey(const Key('order-receive')), findsNothing);
      expect(find.byKey(const Key('review-notes')), findsNothing);
    },
  );

  testWidgets('processing orders cannot be received or reviewed', (
    tester,
  ) async {
    await openOrder(tester);
    expect(find.byKey(const Key('order-receive')), findsNothing);
    expect(find.byKey(const Key('review-notes')), findsNothing);
  });

  for (final action in ['dispatch', 'receive', 'cancel']) {
    testWidgets(
      '$action dialog Back closes without submitting an order update',
      (tester) async {
        final repo = await openOrder(
          tester,
          role: action == 'dispatch' ? 'seller' : 'buyer',
          stage: action == 'receive' ? 'shipped' : 'processing',
        );
        await tester.tap(
          find.text(switch (action) {
            'dispatch' => 'Mark out for delivery',
            'receive' => 'Mark as received',
            _ => 'Cancel order',
          }),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('modal-back')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('modal-back')), findsNothing);
        expect(repo.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('received purchase allows stars and written review notes', (
    tester,
  ) async {
    final repo = await openOrder(tester, stage: 'delivered');
    expect(find.byKey(const Key('order-receive')), findsNothing);
    await tester.tap(find.byTooltip('Rate 5 stars'));
    await tester.enterText(
      find.byKey(const Key('review-notes')),
      'Item arrived in good condition.',
    );
    await tester.ensureVisible(find.byKey(const Key('review-submit')));
    await tester.tap(find.byKey(const Key('review-submit')));
    await tester.pumpAndSettle();
    expect(repo.calls.single.$2['action'], 'review');
    expect(repo.calls.single.$2['rating'], 5);
    expect(
      repo.calls.single.$2['review_notes'],
      'Item arrived in good condition.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('online payment shows Paid only after confirmation', (
    tester,
  ) async {
    await openOrder(tester, method: 'xendit', payment: 'payment_pending');
    expect(find.text('Online payment'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await openOrder(tester, method: 'xendit', payment: 'paid');
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('To ship'), findsOneWidget);
    expect(find.textContaining('Test Mode'), findsNothing);
  });

  testWidgets('buyer can capture an item photo and submit it with a review', (
    tester,
  ) async {
    final picker = PhotoPickerFake();
    final repo = await openOrder(tester, stage: 'delivered', picker: picker);
    await tester.ensureVisible(find.text('Capture item'));
    await tester.tap(find.text('Capture item'));
    await tester.pumpAndSettle();
    expect(picker.source, ImageSource.camera);
    expect(find.byTooltip('Remove photo'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Rate 5 stars'));
    await tester.tap(find.byTooltip('Rate 5 stars'));
    await tester.enterText(
      find.byKey(const Key('review-notes')),
      'Received the item, photo attached.',
    );
    await tester.ensureVisible(find.byKey(const Key('review-submit')));
    await tester.tap(find.byKey(const Key('review-submit')));
    await tester.pumpAndSettle();
    expect(repo.uploaded, ['order1/item.png']);
    expect(repo.calls.single.$2['photo_paths'], ['order1/item.png']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved address can be reused, edited and saved without placing an order',
    (tester) async {
      phoneSize(tester);
      final repo = CommerceFake()
        ..address = {
          'recipient': 'Sample Buyer',
          'phone': '09171234567',
          'address': '123 Sample Street, Barangay Demo',
          'city': 'Quezon City',
          'postal_code': '1100',
        };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(sampleUser()),
            ),
            paymentRepositoryProvider.overrideWithValue(repo),
            quoteProvider(('product1', 1)).overrideWith(
              (ref) async => {
                'product_name': 'Keyboard',
                'unit_price_centavos': 10000,
                'total_centavos': 10000,
              },
            ),
          ],
          child: const MaterialApp(home: CheckoutScreen(productId: 'product1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use current address'), findsOneWidget);
      expect(find.byKey(const Key('shipping-address')), findsNothing);
      await tester.tap(find.text('Update address'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('shipping-address')));
      await tester.enterText(
        find.byKey(const Key('shipping-address')),
        '456 Updated Street, Barangay Demo',
      );
      // Reusing the current address discards this unsaved draft.
      await tester.ensureVisible(find.text('Use current address'));
      await tester.tap(find.text('Use current address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update address'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('shipping-address')))
            .controller!
            .text,
        '123 Sample Street, Barangay Demo',
      );
      await tester.ensureVisible(find.byKey(const Key('shipping-address')));
      await tester.enterText(
        find.byKey(const Key('shipping-address')),
        '456 Updated Street, Barangay Demo',
      );
      await tester.ensureVisible(find.text('Save delivery address'));
      await tester.tap(find.text('Save delivery address'));
      await tester.pumpAndSettle();
      expect(repo.address!['address'], '456 Updated Street, Barangay Demo');
      expect(repo.calls, isEmpty);
      expect(find.byKey(const Key('shipping-address')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
