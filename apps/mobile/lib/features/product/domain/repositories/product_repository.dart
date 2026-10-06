import '../entities/product_detail.dart';

class ProductException implements Exception {
  const ProductException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ProductException($statusCode): $message';
}

abstract interface class ProductRepository {
  Future<ProductDetail> getProduct(String slug);
}
