import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rigmarket/src/features/auth/data/auth_repository.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository() : super(null);
  final calls = <String>[];
  String? userId;
  bool rejectCode = false;
  AuthException? signupError;
  AuthException? resendError;
  void Function()? duringVerification;

  @override
  bool get isConfigured => true;
  @override
  String? get currentUserId => userId;
  @override
  Future<void> signUp(String name, String email, String password) async {
    calls.add('signup:$email');
    if (signupError != null) throw signupError!;
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signin');
    userId = 'user-1';
  }

  @override
  Future<void> resend(String email) async {
    calls.add('resend-signup:$email');
    if (resendError != null) throw resendError!;
  }

  @override
  Future<void> reset(String email) async {
    calls.add('reset:$email');
  }

  @override
  Future<void> verifyCode(String email, String code, OtpPurpose purpose) async {
    calls.add('verify:${purpose.name}:$email');
    duringVerification?.call();
    if (rejectCode) {
      throw const AuthException(
        'Token has expired or is invalid',
        code: 'otp_expired',
      );
    }
    userId = 'user-1';
  }

  @override
  Future<void> updatePassword(String password) async {
    calls.add('update-password');
  }
}
