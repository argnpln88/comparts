import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

enum AuthAction {
  signIn,
  signUp,
  reset,
  updatePassword,
  verifySignup,
  verifyRecovery,
  completeRecovery,
}

final authNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AuthOutcome {
  const AuthOutcome(this.message, {this.navigate = false, this.nextAction});
  final String message;
  final bool navigate;
  final AuthAction? nextAction;
}

class AuthController extends Notifier<AsyncValue<void>> {
  final _sentAt = <String, DateTime>{};
  String? _verifiedRecoveryUserId;
  bool _verifyingRecovery = false;
  bool get isVerifyingRecovery => _verifyingRecovery;
  // SDK auth events can be delivered after verifyOTP has already returned.
  bool get isRecoveringPassword =>
      _verifyingRecovery || _verifiedRecoveryUserId != null;

  int resendSeconds(String email, OtpPurpose purpose) {
    final sent = _sentAt['${purpose.name}:${email.trim().toLowerCase()}'];
    if (sent == null) return 0;
    final remaining =
        60 - ref.read(authNowProvider)().difference(sent).inSeconds;
    return remaining.clamp(0, 60);
  }

  void _checkCooldown(String email, OtpPurpose purpose) {
    final seconds = resendSeconds(email, purpose);
    if (seconds > 0) {
      throw AuthException(
        'Wait $seconds seconds before requesting another code.',
      );
    }
  }

  void _recordSent(String email, OtpPurpose purpose) {
    _sentAt['${purpose.name}:${email.trim().toLowerCase()}'] = ref.read(
      authNowProvider,
    )();
  }

  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<AuthOutcome?> submit(
    AuthAction action, {
    required String email,
    required String password,
    required String name,
    String code = '',
  }) async {
    if (state.isLoading) return null;
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final AuthOutcome outcome;
      switch (action) {
        case AuthAction.signIn:
          await repo.signIn(email, password);
          outcome = const AuthOutcome('You’re signed in.', navigate: true);
        case AuthAction.signUp:
          _checkCooldown(email, OtpPurpose.signup);
          await repo.signUp(name, email, password);
          _recordSent(email, OtpPurpose.signup);
          outcome = const AuthOutcome(
            'Check your latest email for the account verification code. If you have already verified this email, sign in with your password.',
            nextAction: AuthAction.verifySignup,
          );
        case AuthAction.reset:
          _verifiedRecoveryUserId = null;
          _checkCooldown(email, OtpPurpose.recovery);
          await repo.reset(email);
          _recordSent(email, OtpPurpose.recovery);
          outcome = const AuthOutcome(
            'If an account exists for this email, a password reset code has been sent.',
            nextAction: AuthAction.verifyRecovery,
          );
        case AuthAction.verifySignup:
          final error = validateOtp(code);
          if (error != null) throw AuthException(error);
          await repo.verifyCode(email, code, OtpPurpose.signup);
          outcome = const AuthOutcome(
            'Email verified. Your account is ready.',
            navigate: true,
          );
        case AuthAction.verifyRecovery:
          _verifiedRecoveryUserId = null;
          final error = validateOtp(code);
          if (error != null) throw AuthException(error);
          _verifyingRecovery = true;
          try {
            await repo.verifyCode(email, code, OtpPurpose.recovery);
            _verifiedRecoveryUserId = repo.currentUserId;
            if (_verifiedRecoveryUserId == null) {
              throw const AuthException(
                'Request a new code and verify your email again.',
              );
            }
          } finally {
            _verifyingRecovery = false;
          }
          outcome = const AuthOutcome(
            'Code verified. Choose your new password.',
            nextAction: AuthAction.completeRecovery,
          );
        case AuthAction.completeRecovery:
          if (_verifiedRecoveryUserId == null ||
              repo.currentUserId != _verifiedRecoveryUserId) {
            throw const AuthException(
              'Verify your password reset code before choosing a new password.',
            );
          }
          final error = validatePassword(password);
          if (error != null) throw AuthException(error);
          await repo.updatePassword(password);
          _verifiedRecoveryUserId = null;
          outcome = const AuthOutcome(
            'Your password has been updated.',
            navigate: true,
          );
        case AuthAction.updatePassword:
          await repo.updatePassword(password);
          outcome = const AuthOutcome(
            'Your password has been updated.',
            navigate: true,
          );
      }
      if (ref.mounted) state = const AsyncData(null);
      return outcome;
    } on AuthException catch (error, stack) {
      if (ref.mounted) state = AsyncError(_errorMessage(error), stack);
    } catch (_, stack) {
      if (ref.mounted) {
        state = AsyncError(
          'Couldn’t connect. Check your connection and try again.',
          stack,
        );
      }
    }
    return null;
  }

  Future<bool> resend(
    String email, {
    OtpPurpose purpose = OtpPurpose.signup,
  }) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      _checkCooldown(email, purpose);
      final repo = ref.read(authRepositoryProvider);
      if (purpose == OtpPurpose.signup) {
        await repo.resend(email);
      } else {
        await repo.reset(email);
      }
      _recordSent(email, purpose);
      if (ref.mounted) state = const AsyncData(null);
      return true;
    } on AuthException catch (error, stack) {
      if (ref.mounted) state = AsyncError(_errorMessage(error), stack);
    } catch (_, stack) {
      if (ref.mounted) {
        state = AsyncError(
          'Couldn’t send the email. Try again shortly.',
          stack,
        );
      }
    }
    return false;
  }

  String _errorMessage(AuthException error) {
    var code = error.code;
    var message = error.message.trim();
    final structured = message.startsWith('{') || message.startsWith('[');
    if (structured) {
      try {
        final details = jsonDecode(message);
        if (details is Map) {
          code ??= (details['error_code'] ?? details['code'])?.toString();
          message =
              (details['message'] ??
                      details['msg'] ??
                      details['error_description'] ??
                      '')
                  .toString();
        }
      } on FormatException {
        message = '';
      }
    }
    final lower = message.toLowerCase();
    if (code == 'otp_expired') {
      return 'That code is invalid or expired. Check the latest email or request a new code.';
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        lower.contains('rate limit')) {
      return 'Too many requests. Please wait a few minutes before trying again.';
    }
    if ((lower.contains('error sending') && lower.contains('email')) ||
        lower.contains('smtp') ||
        code == 'email_address_not_authorized') {
      return 'We couldn’t send your email code. Our email service is temporarily unavailable. Please try again later.';
    }
    if (code == 'invalid_credentials') return 'Email or password is incorrect.';
    if (code == 'email_not_confirmed') {
      return 'Verify your email before signing in. Use Verify email / resend code to request a new code.';
    }
    if (code == 'unexpected_failure' ||
        (int.tryParse(error.statusCode ?? '') ?? 0) >= 500) {
      return 'We couldn’t complete this request. Please try again later.';
    }
    if (structured || message.isEmpty) {
      return 'We couldn’t complete this request. Please try again later.';
    }
    return message;
  }

  void clear() {
    _verifiedRecoveryUserId = null;
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);

String? validateEmail(String? value) {
  if (value == null ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validatePassword(String? value) =>
    value == null || value.length < 8 ? 'Use at least 8 characters.' : null;

String? validateOtp(String? value) =>
    value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())
    ? 'Enter the 6-digit code from your email.'
    : null;

String safeDestination(String? value) {
  if (const ['/', '/account', '/cart', '/orders', '/selling'].contains(value)) {
    return value!;
  }
  if (value != null &&
      RegExp(
        r'^/(product|checkout|orders)/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    return value;
  }
  return '/account';
}
