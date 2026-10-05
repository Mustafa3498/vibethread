import '../../domain/entities/catalog_item.dart';
import '../../domain/entities/catalog_page.dart';

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v); // Prisma Decimal -> string
  return null;
}

String? _firstImageUrl(Map<String, dynamic> json) {
  final direct = json['imageUrl'] ?? json['image'] ?? json['thumbnail'];
  if (direct is String && direct.isNotEmpty) return direct;

  final images = json['images'];
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first is String) return first;
    if (first is Map && first['url'] is String) return first['url'] as String;
  }
  return null;
}

class CatalogItemModel extends CatalogItem {
  const CatalogItemModel({
    required super.id,
    required super.title,
    super.description,
    super.authorName,
    super.createdAt,
    super.price,
    super.imageUrl,
  });

  factory CatalogItemModel.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return CatalogItemModel(
      id: json['id'].toString(), // int or uuid
      title: (json['title'] ?? json['name'])?.toString() ?? '',
      description: json['description'] as String?,
      authorName: (json['authorName'] ??
          (author is Map ? author['username'] : null)) as String?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      price: _toDouble(json['price'] ?? json['basePrice']),
      imageUrl: _firstImageUrl(json),
    );
  }
}

class CatalogPageModel extends CatalogPage {
  const CatalogPageModel({
    required super.items,
    required super.page,
    required super.hasMore,
  });

  /// Accepts `{ data: [...] }`, `{ items: [...] }`, `{ products: [...] }` or
  /// `{ data: { items: [...] } }`, with optional `pagination` metadata
  /// (`hasMore` or `totalPages`). Without metadata, a full page implies more.
  factory CatalogPageModel.fromResponse(
    dynamic body, {
    required int page,
    required int limit,
  }) {
    final map = body as Map<String, dynamic>;

    dynamic raw = map['data'] ?? map['items'] ?? map['products'];
    if (raw is Map) raw = raw['items'] ?? raw['products'] ?? raw['data'];
    final list = (raw as List?) ?? const <dynamic>[];

    final items = list
        .map((e) => CatalogItemModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);

    final meta = map['pagination'] ?? map['meta'];
    bool? hasMore;
    if (meta is Map) {
      if (meta['hasMore'] is bool) {
        hasMore = meta['hasMore'] as bool;
      } else if (meta['totalPages'] is int) {
        hasMore = page < (meta['totalPages'] as int);
      }
    }

    return CatalogPageModel(
      items: items,
      page: page,
      hasMore: hasMore ?? items.length >= limit,
    );
  }
}
