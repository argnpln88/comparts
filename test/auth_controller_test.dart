import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rigmarket/src/features/auth/application/auth_controller.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repo;
  late ProviderContainer container;
  late AuthController controller;
  late DateTime now;
  setUp(() {
    repo = FakeAuthRepository();
    now = DateTime.utc(2026, 10, 27);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authNowProvider.overrideWithValue(() => now),
      ],
    );
    controller = container.read(authControllerProvider.notifier);
  });
  tearDown(() => container.dispose());
  Future<AuthOutcome?> submit(AuthAction action, {String code = '123456'}) =>
      controller.submit(
        action,
        email: 'builder@example.com',
        password: 'a-new-password',
        name: 'Builder',
        code: code,
      );

  test('sign-up requires code verification before navigation', () async {
    final requested = await submit(AuthAction.signUp);
    expect(requested!.navigate, isFalse);
    expect(requested.nextAction, AuthAction.verifySignup);
    expect(repo.userId, isNull);
    final verified = await submit(AuthAction.verifySignup);
    expect(verified!.navigate, isTrue);
    expect(repo.calls, [
      'signup:builder@example.com',
      'verify:signup:builder@example.com',
    ]);
  });

  for (final raw in [false, true]) {
    test(
      raw
          ? 'raw JSON email failure is explained without exposing the payload'
          : 'email delivery failure remains a failed signup without a cooldown',
      () async {
        repo.signupError = AuthException(
          raw
              ? '{"code":"unexpected_failure","message":"Error sending confirmation email"}'
              : 'Error sending confirmation email',
          code: raw ? null : 'unexpected_failure',
          statusCode: '500',
        );
        expect(await submit(AuthAction.signUp), isNull);
        expect(
          container.read(authControllerProvider).error,
          'We couldn’t send your email code. Our email service is temporarily unavailable. Please try again later.',
        );
        expect(
          controller.resendSeconds('builder@example.com', OtpPurpose.signup),
          0,
        );
        expect(repo.userId, isNull);
        repo.signupError = null;
        expect(
          (await submit(AuthAction.signUp))!.nextAction,
          AuthAction.verifySignup,
        );
      },
    );
  }

  test(
    'resend errors explain throttling and do not imply an email was sent',
    () async {
      repo.resendError = const AuthException(
        'Email rate limit exceeded',
        code: 'over_email_send_rate_limit',
      );
      expect(await controller.resend('builder@example.com'), isFalse);
      expect(
        container.read(authControllerProvider).error,
        'Too many requests. Please wait a few minutes before trying again.',
      );
      expect(
        controller.resendSeconds('builder@example.com', OtpPurpose.signup),
        0,
      );
    },
  );

  test(
    'recovery cannot update password before a valid code and is single-use',
    () async {
      expect(await submit(AuthAction.completeRecovery), isNull);
      expect(repo.calls, isEmpty);
      final request = await submit(AuthAction.reset);
      expect(request!.nextAction, AuthAction.verifyRecovery);
      expect(request.message, contains('If an account exists'));
      repo.rejectCode = true;
      expect(await submit(AuthAction.verifyRecovery), isNull);
      expect(
        container.read(authControllerProvider).error,
        contains('invalid or expired'),
      );
      expect(await submit(AuthAction.completeRecovery), isNull);
      expect(repo.calls, isNot(contains('update-password')));
      repo.rejectCode = false;
      repo.duringVerification = () =>
          expect(controller.isVerifyingRecovery, isTrue);
      final verification = await submit(AuthAction.verifyRecovery);
      expect(controller.isVerifyingRecovery, isFalse);
      expect(verification!.navigate, isFalse);
      expect(verification.nextAction, AuthAction.completeRecovery);
      expect((await submit(AuthAction.completeRecovery))!.navigate, isTrue);
      expect(await submit(AuthAction.completeRecovery), isNull);
      expect(repo.calls.where((call) => call == 'update-password').length, 1);
    },
  );

  test(
    'signup verification and changed sessions cannot authorize recovery update',
    () async {
      await submit(AuthAction.verifySignup);
      expect(await submit(AuthAction.completeRecovery), isNull);
      await submit(AuthAction.verifyRecovery);
      repo.userId = 'another-user';
      expect(await submit(AuthAction.completeRecovery), isNull);
      expect(repo.calls, isNot(contains('update-password')));
    },
  );

  test(
    'malformed codes are rejected before making verification requests',
    () async {
      for (final code in ['12345', 'abcdef', '1234567', '']) {
        expect(await submit(AuthAction.verifyRecovery, code: code), isNull);
      }
      expect(repo.calls, isEmpty);
    },
  );

  test(
    'resend cooldown is enforced and recovery resends use password recovery',
    () async {
      await submit(AuthAction.reset);
      expect(
        controller.resendSeconds('BUILDER@example.com', OtpPurpose.recovery),
        60,
      );
      expect(
        await controller.resend(
          'builder@example.com',
          purpose: OtpPurpose.recovery,
        ),
        isFalse,
      );
      expect(repo.calls, ['reset:builder@example.com']);
      now = now.add(const Duration(seconds: 60));
      expect(
        await controller.resend(
          'builder@example.com',
          purpose: OtpPurpose.recovery,
        ),
        isTrue,
      );
      expect(repo.calls, [
        'reset:builder@example.com',
        'reset:builder@example.com',
      ]);
      expect(
        controller.resendSeconds('builder@example.com', OtpPurpose.recovery),
        60,
      );
      expect(
        controller.resendSeconds('builder@example.com', OtpPurpose.signup),
        0,
      );
    },
  );
}
