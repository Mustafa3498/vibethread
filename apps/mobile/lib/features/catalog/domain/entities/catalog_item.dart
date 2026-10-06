import 'package:equatable/equatable.dart';

import '../../../../core/models/color_option.dart';

/// A product card as shown in the storefront grid.
class CatalogItem extends Equatable {
  const CatalogItem({
    required this.id,
    required this.slug,
    required this.title,
    this.categoryName,
    this.price,
    this.basePrice,
    this.salePrice,
    this.imageUrl,
    this.promoTag,
    this.inStock = true,
    this.lowStock = false,
    this.colors = const [],
    this.sizes = const [],
  });

  final String id;
  final String slug;
  final String title;
  final String? categoryName;

  /// Effective price (cheapest active variant).
  final double? price;
  final double? basePrice;
  final double? salePrice;
  final String? imageUrl;
  final String? promoTag;
  final bool inStock;
  final bool lowStock;
  final List<ColorOption> colors;
  final List<String> sizes;

  bool get hasDiscount =>
      price != null && basePrice != null && basePrice! > price!;

  @override
  List<Object?> get props => [
        id,
        slug,
        title,
        categoryName,
        price,
        basePrice,
        salePrice,
        imageUrl,
        promoTag,
        inStock,
        lowStock,
        colors,
        sizes,
      ];
}
