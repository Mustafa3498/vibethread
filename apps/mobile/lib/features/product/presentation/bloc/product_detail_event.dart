part of 'product_detail_bloc.dart';

sealed class ProductDetailEvent extends Equatable {
  const ProductDetailEvent();

  @override
  List<Object?> get props => [];
}

final class ProductDetailStarted extends ProductDetailEvent {
  const ProductDetailStarted(this.slug);

  final String slug;

  @override
  List<Object?> get props => [slug];
}

/// Silent refetch (product changed on the server) or retry after a failure.
final class ProductDetailReloaded extends ProductDetailEvent {
  const ProductDetailReloaded();
}

final class ProductColorSelected extends ProductDetailEvent {
  const ProductColorSelected(this.color);

  final String color;

  @override
  List<Object?> get props => [color];
}

final class ProductSizeSelected extends ProductDetailEvent {
  const ProductSizeSelected(this.size);

  final String size;

  @override
  List<Object?> get props => [size];
}

/// `stock:updated` received over the socket.
final class ProductStockChanged extends ProductDetailEvent {
  const ProductStockChanged({
    required this.variantId,
    required this.available,
    required this.lowStock,
  });

  final String variantId;
  final int available;
  final bool lowStock;

  @override
  List<Object?> get props => [variantId, available, lowStock];
}

final class ProductLiveStatusChanged extends ProductDetailEvent {
  const ProductLiveStatusChanged({required this.connected});

  final bool connected;

  @override
  List<Object?> get props => [connected];
}
