import '../../../../core/models/color_option.dart';
import '../../domain/entities/catalog_item.dart';
import '../../domain/entities/catalog_page.dart';

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// One product card from `GET /api/products`:
/// `{ id, name, slug, category:{name}, promoTag, basePrice, salePrice, price,
///    thumbnail, colors:[{color,colorHex}], sizes:[..], inStock, lowStock }`.
class CatalogItemModel extends CatalogItem {
  const CatalogItemModel({
    required super.id,
    required super.slug,
    required super.title,
    super.categoryName,
    super.price,
    super.basePrice,
    super.salePrice,
    super.imageUrl,
    super.promoTag,
    super.inStock,
    super.lowStock,
    super.colors,
    super.sizes,
  });

  factory CatalogItemModel.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final rawColors = json['colors'];
    final rawSizes = json['sizes'];

    return CatalogItemModel(
      id: json['id'].toString(),
      slug: json['slug']?.toString() ?? '',
      title: json['name']?.toString() ?? '',
      categoryName: category is Map ? category['name'] as String? : null,
      price: _toDouble(json['price']),
      basePrice: _toDouble(json['basePrice']),
      salePrice: _toDouble(json['salePrice']),
      imageUrl: json['thumbnail'] as String?,
      promoTag: json['promoTag'] as String?,
      inStock: json['inStock'] as bool? ?? true,
      lowStock: json['lowStock'] as bool? ?? false,
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
    );
  }
}

class CatalogPageModel extends CatalogPage {
  const CatalogPageModel({
    required super.items,
    required super.page,
    required super.hasMore,
  });

  /// Backend shape: `{ items: [...], total, page, pageSize, totalPages }`.
  factory CatalogPageModel.fromResponse(
    dynamic body, {
    required int page,
    required int limit,
  }) {
    final map = body as Map<String, dynamic>;
    final raw = (map['items'] as List?) ?? const <dynamic>[];

    final items = raw
        .map(
          (e) => CatalogItemModel.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(growable: false);

    final totalPages = map['totalPages'];
    final hasMore =
        totalPages is int ? page < totalPages : items.length >= limit;

    return CatalogPageModel(items: items, page: page, hasMore: hasMore);
  }
}
