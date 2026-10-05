import 'catalog_item.dart';

class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<CatalogItem> items;
  final int page;
  final bool hasMore;
}
