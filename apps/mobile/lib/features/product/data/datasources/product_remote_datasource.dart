import 'package:dio/dio.dart';

import '../../../../core/network/auth_interceptor.dart';
import '../../domain/entities/product_detail.dart';
import '../models/product_detail_model.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource(this._dio);

  final Dio _dio;

  /// Public endpoint: `GET /api/products/:slug` -> `{ product: {...} }`.
  Future<ProductDetail> fetchProduct(String slug) async {
    final res = await _dio.get<dynamic>(
      '/api/products/${Uri.encodeComponent(slug)}',
      options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
    );
    final body = res.data as Map<String, dynamic>;
    return parseProductDetail(
      Map<String, dynamic>.from(body['product'] as Map),
    );
  }
}
