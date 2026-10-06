part of 'product_detail_bloc.dart';

enum ProductDetailStatus { loading, success, failure }

final class ProductDetailState extends Equatable {
  const ProductDetailState({
    this.status = ProductDetailStatus.loading,
    this.product,
    this.selectedColor,
    this.selectedSize,
    this.liveConnected = false,
    this.errorMessage,
  });

  final ProductDetailStatus status;
  final ProductDetail? product;
  final String? selectedColor;
  final String? selectedSize;

  /// True while the socket is connected and this product room is watched.
  final bool liveConnected;
  final String? errorMessage;

  /// Variants of the selected colour, in the product's size order.
  List<ProductVariant> get variantsForColor {
    final p = product;
    final c = selectedColor;
    if (p == null || c == null) return const [];

    final list = p.variants.where((v) => v.color == c).toList();
    int rank(String size) {
      final i = p.sizes.indexOf(size);
      return i == -1 ? 999 : i;
    }

    list.sort((a, b) => rank(a.size).compareTo(rank(b.size)));
    return list;
  }

  ProductVariant? get selectedVariant {
    final size = selectedSize;
    if (size == null) return null;
    for (final v in variantsForColor) {
      if (v.size == size) return v;
    }
    return null;
  }

  /// Images for the selected colour (plus shared ones); all images if none match.
  List<ProductImage> get galleryImages {
    final p = product;
    if (p == null) return const [];
    final c = selectedColor;
    if (c == null) return p.images;

    final matching = p.images
        .where((i) => i.color == null || i.color!.toLowerCase() == c.toLowerCase())
        .toList(growable: false);
    return matching.isEmpty ? p.images : matching;
  }

  /// Price of the selected variant, else the cheapest active variant.
  double? get displayPrice {
    final v = selectedVariant;
    if (v != null) return v.price;

    final p = product;
    if (p == null) return null;
    if (p.variants.isEmpty) return p.salePrice ?? p.basePrice;
    return p.variants.map((e) => e.price).reduce((a, b) => a < b ? a : b);
  }

  ProductDetailState copyWith({
    ProductDetailStatus? status,
    ProductDetail? product,
    String? selectedColor,
    String? selectedSize,
    bool clearSize = false,
    bool? liveConnected,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProductDetailState(
      status: status ?? this.status,
      product: product ?? this.product,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedSize: clearSize ? null : (selectedSize ?? this.selectedSize),
      liveConnected: liveConnected ?? this.liveConnected,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        product,
        selectedColor,
        selectedSize,
        liveConnected,
        errorMessage,
      ];
}
