import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rigmarket/src/features/auth/application/auth_controller.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';
import 'package:rigmarket/src/features/payments/payments.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'checkout sends the server quote and retains the caller idempotency key',
    () async {
      final key = checkoutKey();
      Map<String, dynamic>? sent;
      final client = SupabaseClient(
        'https://project.supabase.co',
        'test-publishable',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'order': {'id': 'order1', 'status': 'creation_unknown'},
            }),
            202,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await PaymentRepository(client).call('checkout-create', {
        'idempotency_key': key,
        'expected_unit_price_centavos': 10050,
        'quantity': 1,
        'product_id': 'product1',
      });
      expect(sent!['idempotency_key'], key);
      expect(sent!.containsKey('buyer_id'), false);
      expect((result['order'] as Map)['status'], 'creation_unknown');
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(key),
        true,
      );
    },
  );
  test(
    'checkout exposes a useful backend error and never invents success',
    () async {
      final client = SupabaseClient(
        'https://project.supabase.co',
        'test-publishable',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'Insufficient stock'}),
            409,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        PaymentRepository(client).call('checkout-create', {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Insufficient stock',
          ),
        ),
      );
    },
  );
  test('auth resumes only approved internal payment routes', () {
    const id = '75c83632-c413-4a4d-b852-3b6cce8087dd';
    expect(safeDestination('/checkout/$id'), '/checkout/$id');
    expect(safeDestination('/orders/$id'), '/orders/$id');
    expect(
      safeDestination('/checkout/$id?next=https://evil.example'),
      '/account',
    );
    expect(safeDestination('//evil.example'), '/account');
  });
  testWidgets(
    'uncertain payment offers refresh and never offers a second payment',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(
                User(
                  id: 'buyer',
                  appMetadata: {},
                  userMetadata: {},
                  aud: 'authenticated',
                  createdAt: '2026-10-27T00:00:00Z',
                ),
              ),
            ),
            orderProvider('order1').overrideWith(
              (ref) async => {
                'order': {
                  'id': 'order1',
                  'status': 'creation_unknown',
                  'product_name': 'Test item',
                  'quantity': 1,
                  'total_centavos': 10050,
                },
              },
            ),
          ],
          child: const MaterialApp(home: OrderScreen(id: 'order1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirming checkout'), findsOneWidget);
      expect(find.textContaining('Do not pay again'), findsOneWidget);
      expect(find.text('Continue online payment'), findsNothing);
      expect(find.text('Refresh payment status'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
