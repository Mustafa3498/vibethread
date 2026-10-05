import 'package:dio/dio.dart';

import '../../../../core/network/auth_interceptor.dart';
import '../models/catalog_item_model.dart';

class CatalogRemoteDataSource {
  CatalogRemoteDataSource(this._dio);

  final Dio _dio;

  /// Public endpoint: skips the Bearer header and the 401-refresh logic, so
  /// an expired access token can never break browsing.
  Future<CatalogPageModel> fetchCatalog({
    required int page,
    required int limit,
    String? query,
  }) async {
    final res = await _dio.get<dynamic>(
      '/api/catalog',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (query != null && query.isNotEmpty) 'q': query,
      },
      options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
    );
    return CatalogPageModel.fromResponse(res.data, page: page, limit: limit);
  }
}
