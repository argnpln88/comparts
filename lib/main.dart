import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/core/app_config.dart';
import 'src/features/auth/data/auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromEnvironment();
  SupabaseClient? client;
  String? startupError = config.validationError;
  if (config.isConfigured && startupError == null) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
      );
      client = Supabase.instance.client;
    } catch (_) {
      startupError = 'Could not initialize the connection. Check your app configuration and restart.';
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        supabaseClientProvider.overrideWithValue(client),
        startupErrorProvider.overrideWithValue(startupError),
      ],
      child: const RigMarketApp(),
    ),
  );
}
