import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';

import 'support/memory_auth_storage.dart';

Map<String, dynamic> sessionResponse() {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'HS256'})}.${encode({'sub': 'user-1', 'exp': 4102444800})}.test-signature',
    'refresh_token': 'synthetic-test-refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': 'user-1',
      'aud': 'authenticated',
      'email': 'builder@example.com',
      'created_at': '2026-10-27T00:00:00Z',
    },
  };
}

void main() {
  for (final duplicate in [false, true]) {
    test(
      duplicate
          ? 'obfuscated duplicate signup does not report an OTP request'
          : 'pending signup with an email identity can request verification',
      () async {
        final transport = MockClient(
          (request) async => http.Response(
            jsonEncode({
              'id': 'user-1',
              'aud': 'authenticated',
              'email': 'builder@example.com',
              'created_at': '2026-10-27T00:00:00Z',
              'identities': duplicate
                  ? []
                  : [
                      {
                        'id': 'identity-1',
                        'user_id': 'user-1',
                        'provider': 'email',
                      },
                    ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        final client = SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test',
          httpClient: transport,
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: MemoryAuthStorage(),
          ),
        );
        addTearDown(() async {
          await client.dispose();
          transport.close();
        });
        final request = AuthRepository(client)
            .signUp('Builder', 'builder@example.com', 'a-password');
        if (duplicate) {
          await expectLater(
            request,
            throwsA(
              isA<AuthException>().having(
                (error) => error.code,
                'code',
                'signup_not_started',
              ),
            ),
          );
        } else {
          await expectLater(request, completes);
        }
        expect(client.auth.currentSession, isNull);
      },
    );
  }

  test('signup uses email OTP and recovery uses recovery OTP, with real SDK events', () async {
    final requests = <http.Request>[];
    final events = <AuthChangeEvent>[];
    final transport = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(sessionResponse()),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      httpClient: transport,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: MemoryAuthStorage(),
      ),
    );
    final subscription = client.auth.onAuthStateChange.listen(
      (event) => events.add(event.event),
    );
    addTearDown(() async {
      await subscription.cancel();
      await client.dispose();
      transport.close();
    });
    final repo = AuthRepository(client);
    await repo.verifyCode(' builder@example.com ', '123456', OtpPurpose.signup);
    await repo.verifyCode('builder@example.com', '654321', OtpPurpose.recovery);
    await Future<void>.delayed(Duration.zero);
    expect(
      requests.map((request) => request.url.path),
      everyElement('/auth/v1/verify'),
    );
    expect(jsonDecode(requests[0].body)['type'], 'email');
    expect(jsonDecode(requests[1].body)['type'], 'recovery');
    expect(jsonDecode(requests[0].body)['email'], 'builder@example.com');
    expect(repo.currentUserId, 'user-1');
    expect(events, contains(AuthChangeEvent.passwordRecovery));
  });

  test('verification response without a session is rejected', () async {
    final transport = MockClient(
      (_) async => http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      httpClient: transport,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: MemoryAuthStorage(),
      ),
    );
    addTearDown(() async {
      await client.dispose();
      transport.close();
    });
    expect(
      () =>
          AuthRepository(client)
              .verifyCode('builder@example.com', '123456', OtpPurpose.signup),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'sign-up rejects auto-confirmed sessions instead of bypassing required OTP',
    () async {
      final paths = <String>[];
      final transport = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/logout') ? {} : sessionResponse(),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        httpClient: transport,
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryAuthStorage(),
        ),
      );
      addTearDown(() async {
        await client.dispose();
        transport.close();
      });
      await expectLater(
        AuthRepository(client)
            .signUp('Builder', 'builder@example.com', 'a-password'),
        throwsA(isA<AuthException>()),
      );
      expect(client.auth.currentSession, isNull);
      expect(paths, contains('/auth/v1/logout'));
    },
  );
}
