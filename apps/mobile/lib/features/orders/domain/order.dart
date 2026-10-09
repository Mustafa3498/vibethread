import 'package:equatable/equatable.dart';

class OrderAddress extends Equatable {
  const OrderAddress({
    required this.line1,
    this.line2,
    required this.city,
    this.state,
    this.postalCode,
    this.label,
  });

  final String line1;
  final String? line2;
  final String city;
  final String? state;
  final String? postalCode;
  final String? label;

  /// "House 12, Street 4, Block 7, Karachi, Sindh 75300"
  String get formatted {
    final parts = <String>[
      line1,
      if (line2 != null && line2!.isNotEmpty) line2!,
      city,
      [if (state != null && state!.isNotEmpty) state!, if (postalCode != null && postalCode!.isNotEmpty) postalCode!]
          .join(' '),
    ].where((p) => p.trim().isNotEmpty);
    return parts.join(', ');
  }

  @override
  List<Object?> get props => [line1, line2, city, state, postalCode, label];
}

class OrderItem extends Equatable {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.color,
    required this.size,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.slug,
    this.imageUrl,
  });

  final String id;
  final String productName;
  final String color;
  final String size;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final String? slug;
  final String? imageUrl;

  @override
  List<Object?> get props =>
      [id, productName, color, size, unitPrice, quantity, lineTotal, slug, imageUrl];
}

class Order extends Equatable {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.paymentStatus,
    this.paymentMethod,
    required this.subtotal,
    required this.shippingFee,
    required this.total,
    this.estimatedDelivery,
    this.trackingNumber,
    this.courier,
    required this.placedAt,
    required this.canCancel,
    required this.address,
    required this.items,
  });

  final String id;
  final String orderNumber;

  /// PENDING_PAYMENT (= "Placed" for cash on delivery) | PAID | PACKING | READY_TO_SHIP |
  /// SHIPPED | DELIVERED | CANCELLED | RETURNED
  final String status;
  final String statusLabel;
  final String paymentStatus;
  final String? paymentMethod;
  final double subtotal;
  final double shippingFee;
  final double total;
  final DateTime? estimatedDelivery;
  final String? trackingNumber;
  final String? courier;
  final DateTime placedAt;
  final bool canCancel;
  final OrderAddress address;
  final List<OrderItem> items;

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  bool get isCancelled => status == 'CANCELLED' || status == 'RETURNED';
  bool get isDelivered => status == 'DELIVERED';

  /// Position on the delivery timeline (0..4), or -1 for cancelled / returned.
  int get stage {
    switch (status) {
      case 'PENDING_PAYMENT':
      case 'PAID':
        return 0;
      case 'PACKING':
        return 1;
      case 'READY_TO_SHIP':
        return 2;
      case 'SHIPPED':
        return 3;
      case 'DELIVERED':
        return 4;
      default:
        return -1;
    }
  }

  @override
  List<Object?> get props => [
        id,
        orderNumber,
        status,
        statusLabel,
        paymentStatus,
        paymentMethod,
        subtotal,
        shippingFee,
        total,
        estimatedDelivery,
        trackingNumber,
        courier,
        placedAt,
        canCancel,
        address,
        items,
      ];
}
