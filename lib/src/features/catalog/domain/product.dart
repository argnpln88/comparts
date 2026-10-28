import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum PartCategory {
  cpu('CPUs', Icons.memory_outlined),
  motherboard('Motherboards', Icons.developer_board_outlined),
  gpu('Graphics cards', Icons.videogame_asset_outlined),
  ram('RAM', Icons.view_week_outlined),
  storage('SSDs & HDDs', Icons.storage_outlined),
  psu('Power supplies', Icons.power_outlined),
  casePart('Cases', Icons.dns_outlined),
  cooler('Coolers & fans', Icons.air_outlined),
  monitor('Monitors', Icons.desktop_windows_outlined),
  peripherals('Peripherals', Icons.keyboard_outlined);

  const PartCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.priceCentavos,
    required this.seller,
    required this.condition,
    required this.stock,
    required this.specs,
    this.description = '',
    this.warranty = '',
    this.imageUrl,
    this.imageIsIllustration = false,
    this.sellerLogoUrl,
  });
  final String id, name, brand, seller, condition, description, warranty;
  final PartCategory category;
  final int priceCentavos, stock;
  final Map<String, String> specs;
  final String? imageUrl;
  final bool imageIsIllustration;
  final String? sellerLogoUrl;
  String get price => NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: priceCentavos % 100 == 0 ? 0 : 2,
  ).format(priceCentavos / 100);
  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String,
    category: PartCategory.values.byName(json['category_id'] as String),
    priceCentavos: (json['price_centavos'] as num).toInt(),
    seller:
        (json['seller_profiles'] as Map<String, dynamic>)['shop_name']
            as String,
    condition: json['condition'] as String,
    stock: (json['stock'] as num).toInt(),
    specs: (json['specifications'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value.toString()),
    ),
    description: json['description'] as String? ?? '',
    warranty: json['warranty'] as String? ?? '',
    imageUrl: json['image_url'] as String?,
    imageIsIllustration: json['image_is_illustration'] == true,
    sellerLogoUrl:
        (json['seller_profiles'] as Map<String, dynamic>)['logo_url']
            as String?,
  );
}

enum CatalogSort { newest, priceLow, priceHigh }

class CatalogQuery {
  const CatalogQuery({
    this.search = '',
    this.category,
    this.condition,
    this.sort = CatalogSort.newest,
    this.page = 0,
  });
  final String search;
  final PartCategory? category;
  final String? condition;
  final CatalogSort sort;
  final int page;
  CatalogQuery copyWith({
    String? search,
    PartCategory? category,
    String? condition,
    CatalogSort? sort,
    int? page,
    bool clearCategory = false,
    bool clearCondition = false,
  }) => CatalogQuery(
    search: search ?? this.search,
    category: clearCategory ? null : category ?? this.category,
    condition: clearCondition ? null : condition ?? this.condition,
    sort: sort ?? this.sort,
    page: page ?? 0,
  );
}
