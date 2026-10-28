import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';

class CatalogFilters extends Notifier<CatalogQuery> {
  @override
  CatalogQuery build() => const CatalogQuery();
  void set(CatalogQuery query) => state = query;
}

final catalogFiltersProvider = NotifierProvider<CatalogFilters, CatalogQuery>(
  CatalogFilters.new,
);
final catalogRepositoryProvider = Provider(
  (ref) => CatalogRepository(
    ref.watch(supabaseClientProvider),
    preview: ref.watch(appConfigProvider).isPreview,
  ),
);
final catalogProvider = FutureProvider(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .fetch(ref.watch(catalogFiltersProvider)),
);
final productProvider = FutureProvider.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).get(id),
);
