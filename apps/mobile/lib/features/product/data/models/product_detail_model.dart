import '../../../../core/models/color_option.dart';
import '../../domain/entities/product_detail.dart';

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Parses the `product` object of `GET /api/products/:slug`.
ProductDetail parseProductDetail(Map<String, dynamic> json) {
  final category = json['category'];
  final rawImages = json['images'];
  final rawColors = json['colors'];
  final rawSizes = json['sizes'];
  final rawVariants = json['variants'];
  final rawTags = json['tags'];

  return ProductDetail(
    id: json['id'].toString(),
    slug: json['slug']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    description: json['description'] as String?,
    fabric: json['fabric'] as String?,
    careNotes: json['careNotes'] as String?,
    categoryName: category is Map ? category['name'] as String? : null,
    basePrice: _toDouble(json['basePrice']),
    salePrice: _toDouble(json['salePrice']),
    promoTag: json['promoTag'] as String?,
    tags: rawTags is List
        ? rawTags.map((t) => t.toString()).toList(growable: false)
        : const [],
    images: rawImages is List
        ? rawImages
            .whereType<Map>()
            .map(
              (i) => ProductImage(
                id: i['id'].toString(),
                url: i['url'].toString(),
                color: i['color'] as String?,
                altText: i['altText'] as String?,
              ),
            )
            .toList(growable: false)
        : const [],
    colors: rawColors is List
        ? rawColors
            .whereType<Map>()
            .map(
              (c) => ColorOption(
                name: c['color'].toString(),
                hex: c['colorHex'] as String?,
              ),
            )
            .toList(growable: false)
        : const [],
    sizes: rawSizes is List
        ? rawSizes.map((s) => s.toString()).toList(growable: false)
        : const [],
    variants: rawVariants is List
        ? rawVariants
            .whereType<Map>()
            .map(
              (v) => ProductVariant(
                id: v['id'].toString(),
                sku: v['sku']?.toString() ?? '',
                color: v['color'].toString(),
                colorHex: v['colorHex'] as String?,
                size: v['size'].toString(),
                price: _toDouble(v['price']) ?? 0,
                available: (v['available'] as num?)?.toInt() ?? 0,
                lowStock: v['lowStock'] as bool? ?? false,
              ),
            )
            .toList(growable: false)
        : const [],
  );
}
