import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_theme.dart';
import '../../../shared/widgets.dart';
import '../application/catalog_providers.dart';
import '../domain/product.dart';
import 'part_art.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  Timer? _debounce;
  late final TextEditingController _search;
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(catalogFiltersProvider).search,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(catalogFiltersProvider);
    final catalog = ref.watch(catalogProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(catalogProvider);
        await ref.read(catalogProvider.future);
      },
      child: CustomScrollView(
        key: const PageStorageKey('catalog-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GOOD PARTS. GREAT BUILDS.',
                    style: TextStyle(
                      color: blue,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your next build\nstarts here.',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Discover PC parts from independent sellers.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('catalog-search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search CPUs, graphics cards, RAM…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _debounce?.cancel();
                          _search.clear();
                          ref
                              .read(catalogFiltersProvider.notifier)
                              .set(
                                ref
                                    .read(catalogFiltersProvider)
                                    .copyWith(search: ''),
                              );
                        },
                      ),
                    ),
                    onChanged: (value) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        ref
                            .read(catalogFiltersProvider.notifier)
                            .set(
                              ref
                                  .read(catalogFiltersProvider)
                                  .copyWith(search: value.trim()),
                            );
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A little upgrade.\nA whole new possibility.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Explore the components',
                                style: TextStyle(
                                  color: Color(0xFFB4CAE9),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Browse categories',
                          onPressed: () => context.go('/categories'),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Find your next part',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sort and filter',
                        onPressed: () => _filters(context),
                        icon: const Icon(Icons.tune),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All parts'),
                      selected: query.category == null,
                      onSelected: (_) => ref
                          .read(catalogFiltersProvider.notifier)
                          .set(query.copyWith(clearCategory: true)),
                    ),
                  ),
                  for (final category in PartCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category.label),
                        selected: query.category == category,
                        onSelected: (_) => ref
                            .read(catalogFiltersProvider.notifier)
                            .set(query.copyWith(category: category)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (query.condition != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text('Condition: ${query.condition}'),
                    onDeleted: () => ref
                        .read(catalogFiltersProvider.notifier)
                        .set(query.copyWith(clearCondition: true)),
                  ),
                ),
              ),
            ),
          ...catalog.when(
            loading: () => [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverGrid.builder(
                  itemCount: 4,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 275,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (_, _) => Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5EAF3),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
            error: (_, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: InfoPanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Couldn’t load the catalog',
                  message: 'Check your connection and Supabase catalog setup, then try again.',
                  action: FilledButton(
                    onPressed: () => ref.invalidate(catalogProvider),
                    child: const Text('Try again'),
                  ),
                ),
              ),
            ],
            data: (page) => [
              if (page.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: InfoPanel(
                    icon: Icons.search_off,
                    title: 'No parts found',
                    message: 'Try a different search or clear your filters.',
                    action: OutlinedButton(
                      onPressed: () {
                        _search.clear();
                        ref
                            .read(catalogFiltersProvider.notifier)
                            .set(const CatalogQuery());
                      },
                      child: const Text('Clear filters'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final columns =
                          constraints.crossAxisExtent < 350 || scale > 1.4
                          ? 1
                          : (constraints.crossAxisExtent / 220).ceil().clamp(
                              2,
                              4,
                            );
                      return SliverGrid.builder(
                        itemCount: page.items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: 280 + ((scale - 1).clamp(0, 2) * 130),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder: (_, index) =>
                            _ProductCard(product: page.items[index]),
                      );
                    },
                  ),
                ),
              if (query.page > 0 || page.hasNext)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton(
                          onPressed: query.page == 0
                              ? null
                              : () => ref
                                    .read(catalogFiltersProvider.notifier)
                                    .set(query.copyWith(page: query.page - 1)),
                          child: const Text('Previous'),
                        ),
                        Text('Page ${query.page + 1}'),
                        OutlinedButton(
                          onPressed: page.hasNext
                              ? () => ref
                                    .read(catalogFiltersProvider.notifier)
                                    .set(query.copyWith(page: query.page + 1))
                              : null,
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Text(
                    'Made for your next build.\nPrices in Philippine pesos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _filters(BuildContext context) async {
    final current = ref.read(catalogFiltersProvider);
    var condition = current.condition;
    var sort = current.sort;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, update) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModalTitle('Make it your build'),
              const SizedBox(height: 24),
              const Text('Condition'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in <String?>[
                    null,
                    'new',
                    'used',
                    'refurbished',
                  ])
                    ChoiceChip(
                      label: Text(value ?? 'Any'),
                      selected: value == condition,
                      onSelected: (_) => update(() => condition = value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<CatalogSort>(
                initialValue: sort,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items: const [
                  DropdownMenuItem(
                    value: CatalogSort.newest,
                    child: Text('Newest listings'),
                  ),
                  DropdownMenuItem(
                    value: CatalogSort.priceLow,
                    child: Text('Price: low to high'),
                  ),
                  DropdownMenuItem(
                    value: CatalogSort.priceHigh,
                    child: Text('Price: high to low'),
                  ),
                ],
                onChanged: (value) => update(() => sort = value!),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ref
                        .read(catalogFiltersProvider.notifier)
                        .set(
                          current.copyWith(
                            condition: condition,
                            clearCondition: condition == null,
                            sort: sort,
                          ),
                        );
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Show parts'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final Product product;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push('/product/${product.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 116,
            width: double.infinity,
            child: PartArt(
              category: product.category,
              imageUrl: product.imageUrl,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.condition.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF496384),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    product.price,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: blue,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.seller,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.stock > 0 ? 'In stock' : 'Sold out',
                    style: TextStyle(
                      fontSize: 10,
                      color: product.stock > 0
                          ? const Color(0xFF247150)
                          : const Color(0xFF9B3D3D),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Every part of your build.',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text('Explore the essentials, one component at a time.'),
      const SizedBox(height: 20),
      for (final category in PartCategory.values)
        Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Icon(category.icon, color: blue),
            title: Text(category.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref
                  .read(catalogFiltersProvider.notifier)
                  .set(CatalogQuery(category: category));
              context.go('/');
            },
          ),
        ),
    ],
  );
}
