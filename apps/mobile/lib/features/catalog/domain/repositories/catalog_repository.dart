import '../entities/catalog_page.dart';

class CatalogException implements Exception {
  const CatalogException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CatalogException($statusCode): $message';
}

abstract interface class CatalogRepository {
  Future<CatalogPage> getCatalog({
    int page = 1,
    int limit = 20,
    String? query,
  });
}
