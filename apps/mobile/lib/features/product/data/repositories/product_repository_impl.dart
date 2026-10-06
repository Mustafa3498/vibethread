import 'package:dio/dio.dart';

import '../../../../core/errors/dio_error_message.dart';
import '../../domain/entities/product_detail.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_remote_datasource.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._remote);

  final ProductRemoteDataSource _remote;

  @override
  Future<ProductDetail> getProduct(String slug) async {
    try {
      return await _remote.fetchProduct(slug);
    } on DioException catch (e) {
      throw ProductException(
        messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    } on TypeError {
      throw const ProductException('Unexpected response from the server.');
    } on FormatException {
      throw const ProductException('Unexpected response from the server.');
    }
  }
}
