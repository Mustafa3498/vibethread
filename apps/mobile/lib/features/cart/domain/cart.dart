import 'package:equatable/equatable.dart';

class CartLine extends Equatable {
  const CartLine({
    required this.id,
    required this.variantId,
    required this.slug,
    required this.name,
    required this.color,
    this.colorHex,
    required this.size,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.available,
    required this.maxQuantity,
    required this.lowStock,
    this.issue,
  });

  final String id;
  final String variantId;
  final String slug;
  final String name;
  final String color;
  final String? colorHex;
  final String size;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;
  final double lineTotal;

  /// Units the shopper can still have (includes their own checkout hold).
  final int available;
  final int maxQuantity;
  final bool lowStock;

  /// null | UNAVAILABLE | OUT_OF_STOCK | EXCEEDS_STOCK
  final String? issue;

  bool get canIncrease => quantity < maxQuantity;

  @override
  List<Object?> get props => [
        id,
        variantId,
        slug,
        name,
        color,
        colorHex,
        size,
        imageUrl,
        unitPrice,
        quantity,
        lineTotal,
        available,
        maxQuantity,
        lowStock,
        issue,
      ];
}

class Cart extends Equatable {
  const Cart({
    required this.id,
    this.items = const [],
    this.itemCount = 0,
    this.subtotal = 0,
    this.shippingFee = 0,
    this.total = 0,
    this.freeShippingThreshold = 0,
    this.amountToFreeShipping = 0,
    this.holdExpiresAt,
    this.hasIssues = false,
    this.holdMinutes,
  });

  final String id;
  final List<CartLine> items;
  final int itemCount;
  final double subtotal;
  final double shippingFee;
  final double total;
  final double freeShippingThreshold;
  final double amountToFreeShipping;

  /// Set while checkout has stock reserved for this cart.
  final DateTime? holdExpiresAt;
  final bool hasIssues;
  final int? holdMinutes;

  bool get isEmpty => items.isEmpty;

  @override
  List<Object?> get props => [
        id,
        items,
        itemCount,
        subtotal,
        shippingFee,
        total,
        freeShippingThreshold,
        amountToFreeShipping,
        holdExpiresAt,
        hasIssues,
        holdMinutes,
      ];
}
