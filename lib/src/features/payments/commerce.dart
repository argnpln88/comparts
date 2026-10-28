import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets.dart';
import '../auth/data/auth_repository.dart';
import 'payments.dart';
import 'review_photos.dart';

class SellerCenterScreen extends ConsumerWidget {
  const SellerCenterScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(fallback: '/account'),
      title: const Text('Seller Center'),
    ),
    body: ref.watch(currentUserProvider).asData?.value == null
        ? const AuthPrompt(
            title: 'Sign in to manage your shop',
            next: '/selling',
            icon: Icons.storefront_outlined,
          )
        : ref
              .watch(sellerProfileProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => InfoPanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your shop',
                  message: 'Check your connection and try again.',
                  action: FilledButton(
                    onPressed: () => ref.invalidate(sellerProfileProvider),
                    child: const Text('Try again'),
                  ),
                ),
                data: (shop) => shop == null || shop['status'] != 'approved'
                    ? const InfoPanel(
                        icon: Icons.storefront_outlined,
                        title: 'Seller access required',
                        message: 'Sign in with an approved seller account to manage orders and dispatch parcels. Buyer accounts can shop and track their purchases in Orders.',
                      )
                    : ref
                          .watch(sellerOrdersProvider)
                          .when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (_, _) => InfoPanel(
                              icon: Icons.cloud_off_outlined,
                              title: 'Could not load seller orders',
                              message: 'Pull to refresh or try again.',
                              action: FilledButton(
                                onPressed: () =>
                                    ref.invalidate(sellerOrdersProvider),
                                child: const Text('Try again'),
                              ),
                            ),
                            data: (orders) => RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(sellerOrdersProvider);
                                await ref.read(sellerOrdersProvider.future);
                              },
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: [
                                  Text(
                                    shop['shop_name'] as String,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Manage orders, dispatch parcels and read buyer feedback.',
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        label: Text(
                                          '${orders.where((o) => o['fulfillment'] == 'delivery' && o['fulfillment_status'] == 'processing' && ['paid', 'cod_pending'].contains(o['status'])).length} to ship',
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          '${orders.where((o) => o['fulfillment_status'] == 'shipped').length} on delivery',
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          '${orders.where((o) => o['fulfillment_status'] == 'delivered').length} completed',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Shop orders',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  if (orders.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                        'New orders will appear here when a buyer places a purchase.',
                                      ),
                                    ),
                                  for (final order in orders)
                                    Card(
                                      child: ListTile(
                                        leading: Icon(
                                          order['fulfillment_status'] ==
                                                  'shipped'
                                              ? Icons.local_shipping_outlined
                                              : Icons.inventory_2_outlined,
                                        ),
                                        title: Text(
                                          order['product_name'] as String,
                                        ),
                                        subtitle: Text(
                                          '${orderSummary(order)}\n${order['quantity']} item(s) · ${pesos(order['total_centavos'] as num)}',
                                        ),
                                        isThreeLine: true,
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: () => context.push(
                                          '/orders/${order['id']}',
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Open a ready-to-ship order to enter its courier and tracking number. Buyers confirm receipt after delivery.',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
  );
}

class ProductReviewsPanel extends ConsumerWidget {
  const ProductReviewsPanel({super.key, required this.productId});
  final String productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(productReviewsProvider(productId))
      .when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
        error: (_, _) => TextButton.icon(
          onPressed: () => ref.invalidate(productReviewsProvider(productId)),
          icon: const Icon(Icons.refresh),
          label: const Text('Load customer reviews'),
        ),
        data: (summary) {
          final reviews = summary['reviews'] as List? ?? [];
          final count = (summary['count'] as num?)?.toInt() ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ratings & reviews',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (count == 0)
                const Text(
                  'No reviews yet. Reviews are available after a buyer confirms receipt.',
                )
              else ...[
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFDB9E19)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${summary['average']} / 5 · $count verified purchase${count == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final review in reviews)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${'★' * (review['rating'] as num).toInt()} · ${review['reviewer_name']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(review['review_notes'] as String),
                        ReviewPhotos(
                          paths: List<String>.from(
                            review['photo_paths'] as List? ?? [],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Verified purchase',
                          style: TextStyle(
                            color: Color(0xFF247150),
                            fontSize: 12,
                          ),
                        ),
                        const Divider(),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      );
}
