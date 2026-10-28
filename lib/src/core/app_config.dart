import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

const appName = 'COMPARTS';

class AppConfig {
  const AppConfig({this.supabaseUrl = '', this.publishableKey = ''});
  const AppConfig.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String supabaseUrl;
  final String publishableKey;
  bool get isConfigured => supabaseUrl.isNotEmpty && publishableKey.isNotEmpty;
  bool get isPreview => supabaseUrl.isEmpty && publishableKey.isEmpty;

  String? get validationError {
    if (isPreview) return null;
    if (!isConfigured) {
      return 'Both the Supabase URL and publishable key are required.';
    }
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.contains('YOUR_')) {
      return 'Enter your real HTTPS Supabase project URL in the build configuration.';
    }
    if (publishableKey.startsWith('sb_publishable_')) return null;
    try {
      final parts = publishableKey.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (payload is Map && payload['role'] == 'anon') return null;
      }
    } catch (_) {
      // Reject malformed and privileged credentials before making requests.
    }
    return 'Use a Supabase publishable key. Backend secret and service-role keys are forbidden in the app.';
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
final startupErrorProvider = Provider<String?>((ref) => null);
