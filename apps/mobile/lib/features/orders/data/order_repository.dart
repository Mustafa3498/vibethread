import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';
import '../domain/order.dart';

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

/// Parses an order object from `/api/orders` (also used right after placing one).
Order parseOrder(Map<dynamic, dynamic> raw) {
  final j = Map<String, dynamic>.from(raw);
  final address = Map<String, dynamic>.from(j['address'] as Map);
  final items = (j['items'] as List? ?? const <dynamic>[]).whereType<Map>();

  return Order(
    id: j['id'].toString(),
    orderNumber: j['orderNumber'].toString(),
    status: j['status'].toString(),
    statusLabel: j['statusLabel']?.toString() ?? j['status'].toString(),
    paymentStatus: j['paymentStatus']?.toString() ?? '',
    paymentMethod: j['paymentMethod'] as String?,
    subtotal: _d(j['subtotal']),
    shippingFee: _d(j['shippingFee']),
    total: _d(j['total']),
    estimatedDelivery: DateTime.tryParse('${j['estimatedDelivery']}')?.toLocal(),
    trackingNumber: j['trackingNumber'] as String?,
    courier: j['courier'] as String?,
    placedAt: DateTime.tryParse('${j['placedAt']}')?.toLocal() ?? DateTime.now(),
    canCancel: j['canCancel'] == true,
    address: OrderAddress(
      line1: address['line1']?.toString() ?? '',
      line2: address['line2'] as String?,
      city: address['city']?.toString() ?? '',
      state: address['state'] as String?,
      postalCode: address['postalCode'] as String?,
      label: address['label'] as String?,
    ),
    items: items
        .map(
          (e) => OrderItem(
            id: e['id'].toString(),
            productName: e['productName']?.toString() ?? '',
            color: e['color']?.toString() ?? '',
            size: e['size']?.toString() ?? '',
            unitPrice: _d(e['unitPrice']),
            quantity: _i(e['quantity']),
            lineTotal: _d(e['lineTotal']),
            slug: e['slug'] as String?,
            imageUrl: e['imageUrl'] as String?,
          ),
        )
        .toList(growable: false),
  );
}

class OrderRepository {
  OrderRepository(this._dio);

  final Dio _dio;

  /// Newest first (first 30 orders).
  Future<List<Order>> listMine() => guardApi(() async {
        final res = await _dio.get<dynamic>(
          '/api/orders',
          queryParameters: {'page': 1, 'pageSize': 30},
        );
        final items = ((res.data as Map)['items'] as List? ?? const <dynamic>[]);
        return items
            .whereType<Map>()
            .map(parseOrder)
            .toList(growable: false);
      });

  Future<Order> getById(String id) => guardApi(() async {
        final res = await _dio.get<dynamic>('/api/orders/$id');
        return parseOrder(unwrap(res.data, 'order'));
      });

  Future<Order> cancel(String id) => guardApi(() async {
        final res = await _dio.post<dynamic>('/api/orders/$id/cancel');
        return parseOrder(unwrap(res.data, 'order'));
      });
}
