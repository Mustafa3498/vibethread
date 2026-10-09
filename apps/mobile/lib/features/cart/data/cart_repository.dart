import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';
import '../domain/cart.dart';

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

/// Parses the cart object returned by `/api/cart`, `/api/checkout` and the
/// `cart:sync` socket event.
Cart parseCart(Map<dynamic, dynamic> raw) {
  final json = Map<String, dynamic>.from(raw);
  final rawItems = json['items'];
  final hold = json['hold'];

  return Cart(
    id: json['id'].toString(),
    items: rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => _parseLine(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const [],
    itemCount: _i(json['itemCount']),
    subtotal: _d(json['subtotal']),
    shippingFee: _d(json['shippingFee']),
    total: _d(json['total']),
    freeShippingThreshold: _d(json['freeShippingThreshold']),
    amountToFreeShipping: _d(json['amountToFreeShipping']),
    holdExpiresAt: hold is Map
        ? DateTime.tryParse('${hold['expiresAt']}')?.toLocal()
        : null,
    hasIssues: json['hasIssues'] == true,
    holdMinutes: json['holdMinutes'] == null ? null : _i(json['holdMinutes']),
  );
}

CartLine _parseLine(Map<String, dynamic> j) {
  return CartLine(
    id: j['id'].toString(),
    variantId: j['variantId'].toString(),
    slug: j['slug']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    color: j['color']?.toString() ?? '',
    colorHex: j['colorHex'] as String?,
    size: j['size']?.toString() ?? '',
    imageUrl: j['imageUrl'] as String?,
    unitPrice: _d(j['unitPrice']),
    quantity: _i(j['quantity']),
    lineTotal: _d(j['lineTotal']),
    available: _i(j['available']),
    maxQuantity: _i(j['maxQuantity']),
    lowStock: j['lowStock'] == true,
    issue: j['issue'] as String?,
  );
}

/// All cart endpoints need the signed-in user (Bearer token + refresh handled
/// by the Dio interceptor).
class CartRepository {
  CartRepository(this._dio);

  final Dio _dio;

  Future<Cart> getCart() => guardApi(() async {
        final res = await _dio.get<dynamic>('/api/cart');
        return parseCart(unwrap(res.data, 'cart'));
      });

  Future<Cart> addItem(String variantId, {int quantity = 1}) => guardApi(() async {
        final res = await _dio.post<dynamic>(
          '/api/cart/items',
          data: {'variantId': variantId, 'quantity': quantity},
        );
        return parseCart(unwrap(res.data, 'cart'));
      });

  /// quantity 0 removes the line.
  Future<Cart> setQuantity(String variantId, int quantity) => guardApi(() async {
        final res = await _dio.patch<dynamic>(
          '/api/cart/items/$variantId',
          data: {'quantity': quantity},
        );
        return parseCart(unwrap(res.data, 'cart'));
      });

  Future<Cart> removeItem(String variantId) => guardApi(() async {
        final res = await _dio.delete<dynamic>('/api/cart/items/$variantId');
        return parseCart(unwrap(res.data, 'cart'));
      });

  /// Holds the cart's stock for ~15 minutes and returns the cart with `holdExpiresAt`.
  Future<Cart> startCheckout() => guardApi(() async {
        final res = await _dio.post<dynamic>('/api/checkout');
        return parseCart(unwrap(res.data, 'checkout'));
      });
}
