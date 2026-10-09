import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order.dart';
import '../domain/address.dart';

Address _parseAddress(Map<dynamic, dynamic> raw) {
  final j = Map<String, dynamic>.from(raw);
  return Address(
    id: j['id'].toString(),
    label: j['label'] as String?,
    line1: j['line1']?.toString() ?? '',
    line2: j['line2'] as String?,
    city: j['city']?.toString() ?? '',
    state: j['state'] as String?,
    postalCode: j['postalCode'] as String?,
    isDefault: j['isDefault'] == true,
  );
}

/// Addresses, the contact number and placing the order (cash on delivery).
/// Holding stock for checkout lives in CartRepository.startCheckout.
class CheckoutRepository {
  CheckoutRepository(this._dio);

  final Dio _dio;

  Future<List<Address>> getAddresses() => guardApi(() async {
        final res = await _dio.get<dynamic>('/api/addresses');
        final items = ((res.data as Map)['items'] as List? ?? const <dynamic>[]);
        return items.whereType<Map>().map(_parseAddress).toList(growable: false);
      });

  Future<Address> createAddress(AddressDraft draft) => guardApi(() async {
        final res = await _dio.post<dynamic>('/api/addresses', data: draft.toJson());
        return _parseAddress(unwrap(res.data, 'address'));
      });

  /// The phone number saved on the account (null if none yet).
  Future<String?> getSavedPhone() => guardApi(() async {
        final res = await _dio.get<dynamic>('/api/auth/me');
        final user = (res.data as Map)['user'];
        if (user is! Map) return null;
        final phone = user['phone'];
        return phone is String && phone.isNotEmpty ? phone : null;
      });

  Future<Order> placeOrder({required String addressId, required String phone}) =>
      guardApi(() async {
        final res = await _dio.post<dynamic>(
          '/api/orders',
          data: {'addressId': addressId, 'paymentMethod': 'COD', 'phone': phone},
        );
        return parseOrder(unwrap(res.data, 'order'));
      });
}
