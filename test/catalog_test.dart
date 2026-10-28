import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rigmarket/src/features/catalog/data/catalog_repository.dart';
import 'package:rigmarket/src/features/catalog/domain/product.dart';

void main() {
  test('live catalog keeps Supabase product image, illustration flag and seller logo', () async {
    const image =
        'https://project.supabase.co/storage/v1/object/public/comparts-sample-media/categories/cpu.png';
    const logo =
        'https://project.supabase.co/storage/v1/object/public/comparts-sample-media/branding/shop-logo.png';
    final client = SupabaseClient(
      'https://project.supabase.co',
      'sb_publishable_fixture',
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['select'], contains('logo_url'));
        return http.Response(
          jsonEncode([
            {
              'id': 'product1',
              'name': 'Ryzen 5 7600',
              'brand': 'AMD',
              'category_id': 'cpu',
              'price_centavos': 1099500,
              'condition': 'new',
              'stock': 4,
              'specifications': {},
              'image_url': image,
              'image_is_illustration': true,
              'seller_profiles': {'shop_name': 'COMPARTS', 'logo_url': logo},
            },
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final page = await CatalogRepository(client).fetch(const CatalogQuery());
    expect(page.items.single.imageUrl, image);
    expect(page.items.single.imageIsIllustration, isTrue);
    expect(page.items.single.sellerLogoUrl, logo);
    expect(page.items.single.seller, 'COMPARTS');
  });
  final preview = CatalogRepository(null, preview: true);
  test('sample catalog covers all ten categories and is paginated', () async {
    final page = await preview.fetch(const CatalogQuery());
    expect(page.items.length, 20);
    expect(page.items.map((p) => p.category).toSet().length, 10);
    expect(page.hasNext, isFalse);
    expect((await preview.fetch(const CatalogQuery(page: 1))).items, isEmpty);
  });
  test('search, category, condition and ordering combine', () async {
    final page = await preview.fetch(
      const CatalogQuery(
        category: PartCategory.gpu,
        condition: 'used',
        search: 'radeon',
        sort: CatalogSort.priceLow,
      ),
    );
    expect(page.items.single.name, 'Radeon RX 6600');
    final sorted = await preview.fetch(
      const CatalogQuery(
        category: PartCategory.cpu,
        sort: CatalogSort.priceLow,
      ),
    );
    expect(sorted.items.first.name, 'Core i5-12400F');
  });
  test(
    'unconfigured live repository fails without substituting sample data',
    () async {
      expect(
        () => CatalogRepository(null).fetch(const CatalogQuery()),
        throwsStateError,
      );
    },
  );
  test(
    'product lookup handles missing and centavo amounts format correctly',
    () async {
      expect(await preview.get('missing'), isNull);
      final product = await preview.get('1');
      expect(product!.priceCentavos, 1099500);
      expect(product.price, '₱10,995');
    },
  );
}
