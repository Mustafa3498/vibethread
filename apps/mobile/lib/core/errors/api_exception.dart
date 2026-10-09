import 'package:dio/dio.dart';

import 'dio_error_message.dart';

/// Any failed backend call, with a message that is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Runs [run] and converts transport / parsing failures into [ApiException].
Future<T> guardApi<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on DioException catch (e) {
    throw ApiException(messageFromDio(e), statusCode: e.response?.statusCode);
  } on TypeError {
    throw const ApiException('Unexpected response from the server.');
  } on FormatException {
    throw const ApiException('Unexpected response from the server.');
  }
}

/// `{ "cart": {...} }` -> the inner map.
Map<String, dynamic> unwrap(dynamic body, String key) {
  return Map<String, dynamic>.from((body as Map)[key] as Map);
}
