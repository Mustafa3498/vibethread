import 'package:dio/dio.dart';

/// Maps a [DioException] to a user-safe message.
///
/// Backend error shape: `{ "error": { "code": "...", "message": "..." } }`.
String messageFromDio(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final error = data['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    if (data['message'] is String) return data['message'] as String;
  }
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return 'Unable to reach the server. Check your connection.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
