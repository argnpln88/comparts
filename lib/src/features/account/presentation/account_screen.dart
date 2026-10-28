import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_config.dart';
import '../../../core/app_theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/auth_repository.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).asData?.value;
    final preview = ref.watch(appConfigProvider).isPreview;
    final avatar = user?.userMetadata?['avatar_url'];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HostedAvatar(
                imageUrl: avatar is String ? avatar : null,
                backgroundColor: Color(0xFF365174),
                iconColor: Colors.white,
              ),
              const SizedBox(height: 18),
              Text(
                user == null
                    ? 'Make it your marketplace.'
                    : 'Hello, ${user.userMetadata?['display_name'] ?? 'builder'}.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user?.email ?? 'Find the parts. Build the possibilities.',
                style: const TextStyle(color: Color(0xFFBFCEE2)),
              ),
              if (user == null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.push('/auth'),
                  child: const Text('Sign in / Create account'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Your corner', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Your orders'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/orders'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Seller Center'),
                subtitle: const Text('Manage shop orders and deliveries'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/selling'),
              ),
              if (user != null) ...[
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/auth/update-password'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('About your app', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  preview ? Icons.science_outlined : Icons.cloud_done_outlined,
                ),
                title: Text(preview ? 'Preview mode' : 'Supabase configured'),
                subtitle: Text(
                  preview
                      ? 'Sample catalog · no purchases'
                      : 'Account and catalog connection configured',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/setup'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About COMPARTS'),
                subtitle: const Text(
                  'Version 0.4.6 · Expanded sample catalog',
                ),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: appName,
                  applicationVersion: '0.4.5',
                  applicationIcon: const Icon(
                    Icons.memory,
                    color: blue,
                    size: 40,
                  ),
                  children: const [
                    Text(
                      'A Philippine marketplace for PC components. Order with cash on delivery or online payment, track seller delivery updates, confirm receipt and review your purchases with item photos. Courier updates and cash collection are recorded manually.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (user != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
              } catch (_) {
                if (context.mounted) {
                  showNotice(
                    context,
                    'Could not sign out. Check your connection and try again.',
                  );
                }
              }
            },
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Built for the next thing you build.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    );
  }
}

class PendingFeatureScreen extends ConsumerWidget {
  const PendingFeatureScreen({super.key, required this.feature});
  final String feature;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).asData?.value;
    final path = feature == 'Cart'
        ? '/cart'
        : feature == 'Orders'
        ? '/orders'
        : '/selling';
    final icon = feature == 'Cart'
        ? Icons.shopping_bag_outlined
        : feature == 'Orders'
        ? Icons.inventory_2_outlined
        : Icons.storefront_outlined;
    if (user == null) {
      return AuthPrompt(
        title: feature == 'Selling'
            ? 'Your shop starts here.'
            : 'Your ${feature.toLowerCase()}, all together.',
        next: path,
        icon: icon,
      );
    }
    return InfoPanel(
      icon: icon,
      title: '$feature is coming next',
      message: feature == 'Selling'
          ? 'Seller onboarding, approval and listing management are planned for the seller stage. Your buyer account will also be your seller account.'
          : 'This first build includes the catalog and account flow. ${feature == 'Cart' ? 'Persistent carts and secure checkout' : 'Payment and fulfillment tracking'} will be enabled with the order backend.',
      action: OutlinedButton(
        onPressed: () => context.go('/'),
        child: const Text('Explore parts'),
      ),
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(fallback: '/account'),
      title: const Text('Connect COMPARTS'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'From preview to your marketplace.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text(
          'The preview APK needs no account configuration. To use real sign-in and catalog data, configure and rebuild it with your Supabase project.',
        ),
        const SizedBox(height: 24),
        for (final item in [
          (
            '1',
            'Create a Supabase project',
            'Enable email/password authentication and configure email delivery.',
          ),
          (
            '2',
            'Apply the foundation migration',
            'Use the SQL file in supabase/migrations. This enables profiles and approved public catalog reads.',
          ),
          (
            '3',
            'Add the auth redirect',
            'Allow com.rigmarket.rigmarket://auth/callback in Supabase Authentication → URL Configuration.',
          ),
          (
            '4',
            'Configure the Flutter build',
            'Copy config/mobile.dev.example.json to config/mobile.dev.json and enter your project URL and publishable key.',
          ),
          (
            '5',
            'Run or build again',
            'Use the commands in README.md. Xendit payment secrets belong only in backend function secrets.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFEAF0FF),
                  child: Text(
                    item.$1,
                    style: const TextStyle(
                      color: blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(item.$3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Text(
          'Full setup: docs/SUPABASE_XENDIT_SETUP.md\nCurrent implementation: docs/IMPLEMENTATION_STATUS.md',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    ),
  );
}
