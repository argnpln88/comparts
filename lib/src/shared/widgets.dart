import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback = '/'});
  final String fallback;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('app-back'),
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(fallback);
        }
      } else {
        Navigator.of(context).maybePop();
      }
    },
  );
}

class HostedAvatar extends StatelessWidget {
  const HostedAvatar({
    super.key,
    this.imageUrl,
    this.fallbackIcon = Icons.person_outline,
    this.backgroundColor = const Color(0xFFEAF0FF),
    this.iconColor = blue,
  });
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color backgroundColor, iconColor;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(imageUrl ?? '');
    final fallback = Icon(fallbackIcon, color: iconColor);
    return CircleAvatar(
      radius: 22,
      backgroundColor: backgroundColor,
      child: uri?.scheme == 'https' && uri!.host.isNotEmpty
          ? ClipOval(
              child: Image.network(
                imageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : fallback,
              ),
            )
          : fallback,
    );
  }
}

class ModalTitle extends StatelessWidget {
  const ModalTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        key: const Key('modal-back'),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    ],
  );
}

class PreviewNotice extends ConsumerWidget {
  const PreviewNotice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appConfigProvider).isPreview) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFEAF0FF),
      child: const Text(
        'PREVIEW  ·  Sample listings. Purchases are unavailable.',
        style: TextStyle(
          color: Color(0xFF254990),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFEAF0FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: blue),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    ),
  );
}

class AuthPrompt extends StatelessWidget {
  const AuthPrompt({
    super.key,
    required this.title,
    required this.next,
    required this.icon,
  });
  final String title, next;
  final IconData icon;
  @override
  Widget build(BuildContext context) => InfoPanel(
    icon: icon,
    title: title,
    message: 'One account for your next build and your next sale. Sign in to continue.',
    action: FilledButton(
      onPressed: () => context.push('/auth?next=${Uri.encodeComponent(next)}'),
      child: const Text('Sign in or create account'),
    ),
  );
}

void showNotice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
