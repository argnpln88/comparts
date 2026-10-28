import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/product.dart';
import 'sample_products.dart';

class CatalogPage {
  const CatalogPage(this.items, this.hasNext);
  final List<Product> items;
  final bool hasNext;
}

class CatalogRepository {
  CatalogRepository(this.client, {this.preview = false});
  final SupabaseClient? client;
  final bool preview;
  static const pageSize = 20;
  Future<CatalogPage> fetch(CatalogQuery filters) async {
    final offset = filters.page * pageSize;
    if (preview) {
      final items = sampleProducts
          .where(
            (p) =>
                (filters.category == null || p.category == filters.category) &&
                (filters.condition == null ||
                    p.condition == filters.condition) &&
                p.name.toLowerCase().contains(filters.search.toLowerCase()),
          )
          .toList();
      if (filters.sort != CatalogSort.newest) {
        items.sort(
          (a, b) => filters.sort == CatalogSort.priceLow
              ? a.priceCentavos.compareTo(b.priceCentavos)
              : b.priceCentavos.compareTo(a.priceCentavos),
        );
      }
      return CatalogPage(
        items.skip(offset).take(pageSize).toList(),
        items.length > offset + pageSize,
      );
    }
    if (client == null) {
      throw StateError('Backend configuration is unavailable.');
    }
    var query = client!
        .from('products')
        .select('*, seller_profiles(shop_name,logo_url)')
        .eq('status', 'published');
    if (filters.category != null) {
      query = query.eq('category_id', filters.category!.name);
    }
    if (filters.condition != null) {
      query = query.eq('condition', filters.condition!);
    }
    if (filters.search.isNotEmpty) {
      final escaped = filters.search
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      query = query.ilike('name', '%$escaped%');
    }
    final rows = await query
        .order(
          filters.sort == CatalogSort.newest ? 'created_at' : 'price_centavos',
          ascending: filters.sort == CatalogSort.priceLow,
        )
        .order('id')
        .range(offset, offset + pageSize);
    return CatalogPage(
      rows.take(pageSize).map(Product.fromJson).toList(),
      rows.length > pageSize,
    );
  }

  Future<Product?> get(String id) async {
    if (preview) return sampleProducts.where((p) => p.id == id).firstOrNull;
    if (client == null) {
      throw StateError('Backend configuration is unavailable.');
    }
    final row = await client!
        .from('products')
        .select('*, seller_profiles(shop_name,logo_url)')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Product.fromJson(row);
  }
}
