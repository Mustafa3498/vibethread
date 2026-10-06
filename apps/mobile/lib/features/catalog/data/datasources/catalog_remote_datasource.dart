import 'package:dio/dio.dart';

import '../../../../core/network/auth_interceptor.dart';
import '../../domain/entities/catalog_filters.dart';
import '../models/catalog_item_model.dart';

class CatalogRemoteDataSource {
  CatalogRemoteDataSource(this._dio);

  final Dio _dio;

  /// Public endpoint (`GET /api/products`, ACTIVE products only): skips the
  /// Bearer header and the 401-refresh logic. The backend names the page size
  /// `pageSize` (max 48).
  Future<CatalogPageModel> fetchCatalog({
    required int page,
    required int limit,
    String? query,
    CatalogFilters filters = const CatalogFilters(),
  }) async {
    final res = await _dio.get<dynamic>(
      '/api/products',
      queryParameters: {
        'page': page,
        'pageSize': limit,
        if (query != null && query.isNotEmpty) 'q': query,
        ...filters.toQuery(),
      },
      options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
    );
    return CatalogPageModel.fromResponse(res.data, page: page, limit: limit);
  }
}
