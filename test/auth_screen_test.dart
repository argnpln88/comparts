import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rigmarket/src/app.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_repository.dart';
import 'support/memory_auth_storage.dart';

Future<void> fill(WidgetTester tester, String key, String value) =>
    tester.enterText(find.byKey(Key(key)), value);
Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('auth-submit')));
  await tester.tap(find.byKey(const Key('auth-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'failed confirmation delivery stays on signup with a clear message',
    (tester) async {
      final repo = FakeAuthRepository()
        ..signupError = const AuthException(
          '{"code":"unexpected_failure","message":"Error sending confirmation email"}',
          statusCode: '500',
        );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider)..go('/auth');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RigMarketApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      await fill(tester, 'auth-name', 'Builder');
      await fill(tester, 'auth-email', 'builder@example.com');
      await fill(tester, 'auth-password', 'a-new-password');
      await fill(tester, 'auth-confirm', 'a-new-password');
      await submit(tester);
      expect(
        find.textContaining('Our email service is temporarily unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('unexpected_failure'), findsNothing);
      expect(find.byKey(const Key('auth-otp')), findsNothing);
      expect(find.byKey(const Key('auth-name')), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/auth');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'signup requires a code and resumes the intended page after verification',
    (tester) async {
      final repo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider)..go('/auth?next=/cart');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RigMarketApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      await fill(tester, 'auth-name', 'Builder');
      await fill(tester, 'auth-email', 'builder@example.com');
      await fill(tester, 'auth-password', 'a-new-password');
      await fill(tester, 'auth-confirm', 'a-new-password');
      await submit(tester);
      expect(find.byKey(const Key('auth-otp')), findsOneWidget);
      expect(find.text('Resend code in 60s'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/auth');
      repo.rejectCode = true;
      await fill(tester, 'auth-otp', '123456');
      await submit(tester);
      expect(find.textContaining('invalid or expired'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/auth');
      repo.rejectCode = false;
      await submit(tester);
      expect(router.routeInformationProvider.value.uri.path, '/cart');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'real SDK recovery event keeps the new-password form in the OTP flow',
    (tester) async {
      final calls = <String>[];
      final transport = MockClient((request) async {
        calls.add(request.url.path);
        final Object body;
        if (request.url.path.endsWith('/verify')) {
          String encode(Map<String, dynamic> value) => base64Url
              .encode(utf8.encode(jsonEncode(value)))
              .replaceAll('=', '');
          body = {
            'access_token':
                '${encode({'alg': 'HS256'})}.${encode({'sub': 'user-1', 'exp': 4102444800})}.test',
            'refresh_token': 'synthetic-test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'user-1',
              'aud': 'authenticated',
              'email': 'builder@example.com',
              'created_at': '2026-10-27T00:00:00Z',
            },
          };
        } else if (request.url.path.endsWith('/user')) {
          body = {
            'id': 'user-1',
            'aud': 'authenticated',
            'email': 'builder@example.com',
            'created_at': '2026-10-27T00:00:00Z',
          };
        } else {
          body = {};
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      // SDK isolate initialization must also start outside fake widget time.
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test',
          httpClient: transport,
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: MemoryAuthStorage(),
          ),
        ),
      ))!;
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(() async {
        // The SDK owns a real JSON isolate; dispose it outside fake widget time.
        await tester.runAsync(() async {
          container.dispose();
          await client.dispose();
          transport.close();
        });
      });
      final router = container.read(routerProvider)..go('/auth');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RigMarketApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await fill(tester, 'auth-email', 'builder@example.com');
      await submit(tester);
      expect(calls, contains('/auth/v1/recover'));
      expect(find.byKey(const Key('auth-password')), findsNothing);
      await fill(tester, 'auth-otp', '123456');
      await submit(tester);
      expect(router.routeInformationProvider.value.uri.path, '/auth');
      expect(find.text('New password'), findsOneWidget);
      expect(calls, isNot(contains('/auth/v1/user')));
      await fill(tester, 'auth-password', 'my-new-password');
      await fill(tester, 'auth-confirm', 'does-not-match');
      await submit(tester);
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(calls, isNot(contains('/auth/v1/user')));
      await fill(tester, 'auth-confirm', 'my-new-password');
      await submit(tester);
      expect(router.routeInformationProvider.value.uri.path, '/account');
      expect(calls.where((path) => path == '/auth/v1/user').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
