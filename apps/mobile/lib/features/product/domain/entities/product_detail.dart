import 'package:equatable/equatable.dart';

import '../../../../core/models/color_option.dart';

class ProductImage extends Equatable {
  const ProductImage({
    required this.id,
    required this.url,
    this.color,
    this.altText,
  });

  final String id;
  final String url;

  /// null = shared image, shown for every colour.
  final String? color;
  final String? altText;

  @override
  List<Object?> get props => [id, url, color, altText];
}

class ProductVariant extends Equatable {
  const ProductVariant({
    required this.id,
    required this.sku,
    required this.color,
    this.colorHex,
    required this.size,
    required this.price,
    required this.available,
    required this.lowStock,
  });

  final String id;
  final String sku;
  final String color;
  final String? colorHex;
  final String size;
  final double price;

  /// quantity - reserved. Never exposes exact stock or cost.
  final int available;
  final bool lowStock;

  bool get inStock => available > 0;

  ProductVariant copyWith({int? available, bool? lowStock}) {
    return ProductVariant(
      id: id,
      sku: sku,
      color: color,
      colorHex: colorHex,
      size: size,
      price: price,
      available: available ?? this.available,
      lowStock: lowStock ?? this.lowStock,
    );
  }

  @override
  List<Object?> get props =>
      [id, sku, color, colorHex, size, price, available, lowStock];
}

class ProductDetail extends Equatable {
  const ProductDetail({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.fabric,
    this.careNotes,
    this.categoryName,
    this.basePrice,
    this.salePrice,
    this.promoTag,
    this.tags = const [],
    this.images = const [],
    this.colors = const [],
    this.sizes = const [],
    this.variants = const [],
  });

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? fabric;
  final String? careNotes;
  final String? categoryName;
  final double? basePrice;
  final double? salePrice;
  final String? promoTag;
  final List<String> tags;
  final List<ProductImage> images;
  final List<ColorOption> colors;
  final List<String> sizes;
  final List<ProductVariant> variants;

  ProductDetail copyWith({List<ProductVariant>? variants}) {
    return ProductDetail(
      id: id,
      slug: slug,
      name: name,
      description: description,
      fabric: fabric,
      careNotes: careNotes,
      categoryName: categoryName,
      basePrice: basePrice,
      salePrice: salePrice,
      promoTag: promoTag,
      tags: tags,
      images: images,
      colors: colors,
      sizes: sizes,
      variants: variants ?? this.variants,
    );
  }

  @override
  List<Object?> get props => [
        id,
        slug,
        name,
        description,
        fabric,
        careNotes,
        categoryName,
        basePrice,
        salePrice,
        promoTag,
        tags,
        images,
        colors,
        sizes,
        variants,
      ];
}
