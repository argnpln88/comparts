import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_theme.dart';
import '../../../shared/widgets.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({
    super.key,
    this.next = '/account',
    this.updatePassword = false,
  });
  final String next;
  final bool updatePassword;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController(),
      _code = TextEditingController();
  late AuthAction _action;
  bool _obscure = true;
  String? _message, _pendingEmail;
  Timer? _resendTicker;

  bool get _verifying =>
      _action == AuthAction.verifySignup ||
      _action == AuthAction.verifyRecovery;
  OtpPurpose get _purpose => _action == AuthAction.verifyRecovery
      ? OtpPurpose.recovery
      : OtpPurpose.signup;

  @override
  void initState() {
    super.initState();
    _action = widget.updatePassword
        ? AuthAction.updatePassword
        : AuthAction.signIn;
  }

  @override
  void dispose() {
    _resendTicker?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  void _change(AuthAction action) {
    ref.read(authControllerProvider.notifier).clear();
    _resendTicker?.cancel();
    _code.clear();
    _password.clear();
    _confirm.clear();
    setState(() {
      _action = action;
      _message = null;
      _pendingEmail = null;
    });
  }

  void _startTicker() {
    _resendTicker?.cancel();
    _resendTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_verifying ||
          ref
                  .read(authControllerProvider.notifier)
                  .resendSeconds(_pendingEmail ?? '', _purpose) ==
              0) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final result = await ref
        .read(authControllerProvider.notifier)
        .submit(
          _action,
          email: _pendingEmail ?? _email.text.trim(),
          password: _password.text,
          name: _name.text,
          code: _code.text,
        );
    if (!mounted || result == null) return;
    if (result.navigate) {
      showNotice(context, result.message);
      context.go(safeDestination(widget.next));
      return;
    }
    if (result.nextAction != null) {
      _password.clear();
      _confirm.clear();
      _code.clear();
      setState(() {
        _pendingEmail ??= _email.text.trim();
        _action = result.nextAction!;
        _message = result.message;
      });
      if (_verifying) _startTicker();
    } else {
      setState(() => _message = result.message);
    }
  }

  Future<void> _resend({bool fromSignIn = false}) async {
    final email = fromSignIn ? _email.text.trim() : _pendingEmail!;
    final error = validateEmail(email);
    if (error != null) {
      showNotice(context, error);
      return;
    }
    final purpose = fromSignIn ? OtpPurpose.signup : _purpose;
    final sent = await ref
        .read(authControllerProvider.notifier)
        .resend(email, purpose: purpose);
    if (!mounted || !sent) return;
    _code.clear();
    _password.clear();
    _confirm.clear();
    setState(() {
      _pendingEmail = email;
      _action = purpose == OtpPurpose.signup
          ? AuthAction.verifySignup
          : AuthAction.verifyRecovery;
      _message = purpose == OtpPurpose.signup
          ? 'If this email still needs verification, check your latest email for a code. Already verified? Sign in with your password.'
          : 'If an account exists for this email, a new password reset code has been sent.';
    });
    _startTicker();
  }

  void _enterExistingRecoveryCode() {
    final error = validateEmail(_email.text);
    if (error != null) {
      showNotice(context, error);
      return;
    }
    ref.read(authControllerProvider.notifier).clear();
    setState(() {
      _pendingEmail = _email.text.trim();
      _action = AuthAction.verifyRecovery;
      _message = null;
    });
    _startTicker();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(authRepositoryProvider);
    // Observe session changes when an external recovery link opens the app.
    ref.watch(currentUserProvider);
    final state = ref.watch(authControllerProvider);
    final signUp = _action == AuthAction.signUp;
    final requestingReset = _action == AuthAction.reset;
    final updating =
        _action == AuthAction.updatePassword ||
        _action == AuthAction.completeRecovery;
    final loading = state.isLoading;
    final seconds = _verifying
        ? ref
              .read(authControllerProvider.notifier)
              .resendSeconds(_pendingEmail ?? '', _purpose)
        : 0;
    final title = _verifying
        ? 'Check your email.'
        : updating
        ? 'A fresh start.'
        : requestingReset
        ? 'Forgot your password?'
        : signUp
        ? 'Your next build awaits.'
        : 'Welcome back.';

    Widget body;
    if (!repo.isConfigured) {
      body = InfoPanel(
        icon: Icons.cloud_outlined,
        title: 'Connect your marketplace',
        message: 'This APK is running in preview mode. Supabase configuration is needed for registration and sign-in.',
        action: FilledButton(
          onPressed: () => context.push('/setup'),
          child: const Text('View connection instructions'),
        ),
      );
    } else if (updating && repo.currentUserId == null) {
      body = InfoPanel(
        icon: Icons.lock_outline,
        title: 'Verify your email first',
        message: 'Request a password reset code and verify it before setting a new password.',
        action: FilledButton(
          onPressed: () => _change(AuthAction.reset),
          child: const Text('Request a reset code'),
        ),
      );
    } else {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _verifying
                          ? Icons.mark_email_read_outlined
                          : Icons.memory,
                      color: blue,
                      size: 42,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _verifying
                          ? _purpose == OtpPurpose.signup
                                ? 'If this email needs verification, enter the 6-digit code from your inbox:'
                                : 'Enter the 6-digit password reset code sent to:'
                          : updating
                          ? 'Choose a new password for your account.'
                          : requestingReset
                          ? 'We’ll email you a code to reset your password.'
                          : 'One account. Buy parts, sell parts, build something great.',
                    ),
                    if (_verifying) ...[
                      const SizedBox(height: 6),
                      Text(
                        _pendingEmail!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (signUp) ...[
                      TextFormField(
                        key: const Key('auth-name'),
                        controller: _name,
                        enabled: !loading,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter your display name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!updating && !_verifying) ...[
                      TextFormField(
                        key: const Key('auth-email'),
                        controller: _email,
                        enabled: !loading,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                        ),
                        validator: validateEmail,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_verifying) ...[
                      TextFormField(
                        key: const Key('auth-otp'),
                        controller: _code,
                        enabled: !loading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                          hintText: '6-digit code',
                        ),
                        style: const TextStyle(
                          letterSpacing: 6,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                        validator: validateOtp,
                        onFieldSubmitted: loading ? null : (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Use the latest code. If it has expired, request another one.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!requestingReset && !_verifying) ...[
                      TextFormField(
                        key: const Key('auth-password'),
                        controller: _password,
                        obscureText: _obscure,
                        enabled: !loading,
                        autofillHints: [
                          signUp || updating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: updating ? 'New password' : 'Password',
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: signUp || updating
                            ? validatePassword
                            : (value) => value == null || value.isEmpty
                                  ? 'Enter your password.'
                                  : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (signUp || updating) ...[
                      TextFormField(
                        key: const Key('auth-confirm'),
                        controller: _confirm,
                        obscureText: _obscure,
                        enabled: !loading,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                        validator: (value) =>
                            value != _password.text ||
                                value == null ||
                                value.isEmpty
                            ? 'Passwords must match.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _message!,
                          style: const TextStyle(color: Color(0xFF247150)),
                        ),
                      ),
                    if (state.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          state.error.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('auth-submit'),
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _verifying
                                    ? 'Verify code'
                                    : updating
                                    ? 'Update password'
                                    : requestingReset
                                    ? 'Send reset code'
                                    : signUp
                                    ? 'Create account'
                                    : 'Sign in',
                              ),
                      ),
                    ),
                    if (_verifying) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          key: const Key('auth-resend'),
                          onPressed: loading || seconds > 0
                              ? null
                              : () => _resend(),
                          child: Text(
                            seconds > 0
                                ? 'Resend code in ${seconds}s'
                                : 'Resend code',
                          ),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: loading
                              ? null
                              : () => _change(
                                  _purpose == OtpPurpose.signup
                                      ? AuthAction.signUp
                                      : AuthAction.reset,
                                ),
                          child: const Text('Use a different email'),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: loading
                              ? null
                              : () => _change(AuthAction.signIn),
                          child: const Text('Back to sign in'),
                        ),
                      ),
                    ] else if (!updating) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: loading
                              ? null
                              : () => _change(
                                  signUp || requestingReset
                                      ? AuthAction.signIn
                                      : AuthAction.signUp,
                                ),
                          child: Text(
                            signUp || requestingReset
                                ? 'Back to sign in'
                                : 'New here? Create an account',
                          ),
                        ),
                      ),
                      if (requestingReset)
                        Center(
                          child: TextButton(
                            onPressed: loading
                                ? null
                                : _enterExistingRecoveryCode,
                            child: const Text('I already have a reset code'),
                          ),
                        ),
                      if (!signUp && !requestingReset) ...[
                        Center(
                          child: TextButton(
                            onPressed: loading
                                ? null
                                : () => _change(AuthAction.reset),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: loading
                                ? null
                                : () => _resend(fromSignIn: true),
                            child: const Text('Verify email / resend code'),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/account'),
        title: const Text('COMPARTS account'),
      ),
      body: body,
    );
  }
}
