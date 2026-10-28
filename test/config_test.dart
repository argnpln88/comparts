import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rigmarket/src/core/app_config.dart';
import 'package:rigmarket/src/features/auth/application/auth_controller.dart';

void main() {
  test(
    'empty configuration enables preview, partial configuration is rejected',
    () {
      expect(const AppConfig().isPreview, isTrue);
      expect(const AppConfig().validationError, isNull);
      expect(
        const AppConfig(supabaseUrl: 'https://demo.supabase.co')
            .validationError,
        isNotNull,
      );
    },
  );
  test('rejects backend keys and accepts only public client credentials', () {
    const url = 'https://demo.supabase.co';
    expect(
      const AppConfig(
        supabaseUrl: url,
        publishableKey: 'sb_secret_private',
      ).validationError,
      isNotNull,
    );
    final servicePayload = base64Url.encode(
      utf8.encode(jsonEncode({'role': 'service_role'})),
    );
    expect(
      AppConfig(
        supabaseUrl: url,
        publishableKey: 'header.$servicePayload.signature',
      ).validationError,
      isNotNull,
    );
    expect(
      const AppConfig(
        supabaseUrl: url,
        publishableKey: 'sb_publishable_demo',
      ).validationError,
      isNull,
    );
  });
  test('rejects insecure URLs and untrusted post-login destinations', () {
    expect(
      const AppConfig(
        supabaseUrl: 'http://demo.supabase.co',
        publishableKey: 'sb_publishable_demo',
      ).validationError,
      isNotNull,
    );
    expect(safeDestination('https://evil.example'), '/account');
    expect(safeDestination('//evil.example'), '/account');
    expect(safeDestination('/cart'), '/cart');
  });
  test('auth validation rejects malformed email and short password', () {
    expect(validateEmail('hello'), isNotNull);
    expect(validateEmail('builder@example.com'), isNull);
    expect(validatePassword('short'), isNotNull);
    expect(validatePassword('long-enough-password'), isNull);
  });
}
