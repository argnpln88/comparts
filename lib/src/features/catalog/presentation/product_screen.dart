import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_config.dart';
import '../../../core/app_theme.dart';
import '../../../shared/widgets.dart';
import '../application/catalog_providers.dart';
import 'part_art.dart';
import '../../auth/data/auth_repository.dart';
import '../../payments/payments.dart';
import '../../payments/commerce.dart';

class ProductScreen extends ConsumerWidget {
  const ProductScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(),
      title: const Text('The details'),
    ),
    body: ref
        .watch(productProvider(id))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => InfoPanel(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn’t load this part',
            message: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(productProvider(id)),
              child: const Text('Try again'),
            ),
          ),
          data: (product) {
            if (product == null) {
              return const InfoPanel(
                icon: Icons.inventory_2_outlined,
                title: 'Listing unavailable',
                message: 'This listing may have been paused or removed.',
              );
            }
            final preview = ref.watch(appConfigProvider).isPreview;
            return ListView(
              children: [
                const PreviewNotice(),
                SizedBox(
                  height: 260,
                  child: PartArt(
                    category: product.category,
                    imageUrl: product.imageUrl,
                    large: true,
                  ),
                ),
                if (product.imageUrl == null || product.imageIsIllustration)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Category illustration',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${product.brand.toUpperCase()}  /  ${product.condition.toUpperCase()}',
                        style: const TextStyle(
                          color: blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        product.price,
                        style: const TextStyle(
                          color: blue,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.stock > 0
                            ? '${product.stock} in stock'
                            : 'Sold out',
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            HostedAvatar(
                              imageUrl: product.sellerLogoUrl,
                              fallbackIcon: Icons.storefront_outlined,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.seller,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const Text(
                                    'Independent seller',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'About this part',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(product.description),
                      const SizedBox(height: 24),
                      Text(
                        'Specifications',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      for (final entry in product.specs.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Warranty & returns',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(product.warranty),
                      const SizedBox(height: 24),
                      if (!preview)
                        ProductReviewsPanel(productId: product.id)
                      else
                        const Text('No reviews in preview'),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: preview || product.stock < 1
                              ? null
                              : () => context.push('/checkout/${product.id}'),
                          child: Text(
                            preview
                                ? 'Purchases unavailable in preview'
                                : 'Buy now',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        preview
                            ? 'Connect your marketplace backend to enable account features. This sample listing cannot be purchased.'
                            : 'Choose cash on delivery or online payment at checkout. Track delivery and confirm receipt in Orders.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      if (!preview)
                        TextButton.icon(
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Add to cart'),
                          onPressed: product.stock < 1
                              ? null
                              : () async {
                                  if (ref
                                          .read(supabaseClientProvider)
                                          ?.auth
                                          .currentUser ==
                                      null) {
                                    context.push(
                                      '/auth?next=${Uri.encodeComponent('/product/${product.id}')}',
                                    );
                                    return;
                                  }
                                  try {
                                    await ref
                                        .read(paymentRepositoryProvider)
                                        .addToCart(product.id);
                                    ref.invalidate(cartProvider);
                                    if (context.mounted) {
                                      showNotice(context, 'Added to cart');
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      showNotice(
                                        context,
                                        'Could not add this item. Try again.',
                                      );
                                    }
                                  }
                                },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
  );
}
