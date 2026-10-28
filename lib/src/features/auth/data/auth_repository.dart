import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OtpPurpose { signup, recovery }

final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
final currentUserProvider = StreamProvider<User?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  yield client?.auth.currentUser;
  if (client != null) {
    yield* client.auth.onAuthStateChange.map((event) => event.session?.user);
  }
});

class AuthRepository {
  AuthRepository(this.client);
  final SupabaseClient? client;
  bool get isConfigured => client != null;
  String? get currentUserId => client?.auth.currentUser?.id;
  SupabaseClient get _client =>
      client ?? (throw StateError('Connect Supabase before signing in.'));
  static const callback = 'com.rigmarket.rigmarket://auth/callback';
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp(String name, String email, String password) async {
    final result = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': name.trim()},
      emailRedirectTo: callback,
    );
    if (result.session != null) {
      await _client.auth.signOut(scope: SignOutScope.local);
      throw const AuthException(
        'Email confirmation is disabled in Supabase. Enable Confirm email before using account verification.',
      );
    }
    // Supabase may hide a confirmed duplicate behind a user with no identities.
    // That response did not start verification and must not open the OTP form.
    if (result.user == null || result.user?.identities?.isEmpty == true) {
      throw const AuthException(
        'No new verification email was requested. If you already have an account, sign in or use Forgot password.',
        code: 'signup_not_started',
      );
    }
  }

  Future<void> resend(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: callback,
    );
  }

  Future<void> reset(String email) =>
      _client.auth.resetPasswordForEmail(email.trim(), redirectTo: callback);

  Future<void> verifyCode(String email, String code, OtpPurpose purpose) async {
    final result = await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: purpose == OtpPurpose.signup ? OtpType.email : OtpType.recovery,
    );
    if (result.session == null || result.user == null) {
      throw const AuthException(
        'Verification did not create a session. Request a new code and try again.',
      );
    }
  }

  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() => _client.auth.signOut();
}

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);
