import 'package:dio/dio.dart';

import '../../../../core/errors/dio_error_message.dart';
import '../../domain/entities/catalog_filters.dart';
import '../../domain/entities/catalog_page.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/catalog_remote_datasource.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._remote);

  final CatalogRemoteDataSource _remote;

  @override
  Future<CatalogPage> getCatalog({
    int page = 1,
    int limit = 20,
    String? query,
    CatalogFilters filters = const CatalogFilters(),
  }) async {
    try {
      return await _remote.fetchCatalog(
        page: page,
        limit: limit,
        query: query,
        filters: filters,
      );
    } on DioException catch (e) {
      throw CatalogException(
        messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    } on TypeError {
      throw const CatalogException('Unexpected response from the server.');
    } on FormatException {
      throw const CatalogException('Unexpected response from the server.');
    }
  }
}
