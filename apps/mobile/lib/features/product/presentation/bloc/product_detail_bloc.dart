import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/socket_service.dart';
import '../../domain/entities/product_detail.dart';
import '../../domain/repositories/product_repository.dart';

part 'product_detail_event.dart';
part 'product_detail_state.dart';

// Socket event names (must match packages/shared SOCKET_EVENTS).
const String _evWatch = 'product:watch';
const String _evUnwatch = 'product:unwatch';
const String _evStock = 'stock:updated';
const String _evProductUpdated = 'product:updated';

class ProductDetailBloc extends Bloc<ProductDetailEvent, ProductDetailState> {
  ProductDetailBloc({
    required ProductRepository repository,
    required SocketService socket,
    Future<void> Function()? refreshSession,
  })  : _repository = repository,
        _socket = socket,
        _refreshSession = refreshSession,
        super(const ProductDetailState()) {
    on<ProductDetailStarted>(_onStarted);
    on<ProductDetailReloaded>(_onReloaded);
    on<ProductColorSelected>(_onColorSelected);
    on<ProductSizeSelected>(_onSizeSelected);
    on<ProductStockChanged>(_onStockChanged);
    on<ProductLiveStatusChanged>(
      (event, emit) => emit(state.copyWith(liveConnected: event.connected)),
    );
  }

  final ProductRepository _repository;
  final SocketService _socket;

  /// Refreshes the stored access token (public catalog calls never do), so the
  /// socket does not connect with an expired token.
  final Future<void> Function()? _refreshSession;

  String? _slug;
  String? _watchedProductId;
  StreamSubscription<Map<dynamic, dynamic>>? _stockSub;
  StreamSubscription<Map<dynamic, dynamic>>? _updatedSub;
  StreamSubscription<SocketStatus>? _statusSub;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _onStarted(
    ProductDetailStarted event,
    Emitter<ProductDetailState> emit,
  ) async {
    _slug = event.slug;
    emit(state.copyWith(status: ProductDetailStatus.loading, clearError: true));

    try {
      final product = await _repository.getProduct(event.slug);
      emit(
        state.copyWith(
          status: ProductDetailStatus.success,
          product: product,
          selectedColor: _defaultColor(product),
          clearSize: true,
          clearError: true,
        ),
      );
      _startLive(product.id);
    } on ProductException catch (e) {
      emit(
        state.copyWith(
          status: ProductDetailStatus.failure,
          errorMessage: e.message,
        ),
      );
    }
  }

  Future<void> _onReloaded(
    ProductDetailReloaded event,
    Emitter<ProductDetailState> emit,
  ) async {
    final slug = _slug;
    if (slug == null) return;

    // Retry after a failed first load.
    if (state.product == null) {
      await _onStarted(ProductDetailStarted(slug), emit);
      return;
    }

    try {
      final product = await _repository.getProduct(slug);

      // Keep the shopper's choices if they still exist.
      var color = state.selectedColor;
      if (color == null || !product.colors.any((c) => c.name == color)) {
        color = _defaultColor(product);
      }
      final size = state.selectedSize;
      final keepSize = size != null &&
          product.variants.any((v) => v.color == color && v.size == size);

      emit(
        state.copyWith(
          product: product,
          selectedColor: color,
          selectedSize: keepSize ? size : null,
          clearSize: !keepSize,
        ),
      );
    } on ProductException {
      // Silent: keep showing the data we already have.
    }
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  void _onColorSelected(
    ProductColorSelected event,
    Emitter<ProductDetailState> emit,
  ) {
    final product = state.product;
    if (product == null) return;

    // Keep the chosen size only if it exists and is in stock in the new colour.
    final size = state.selectedSize;
    final keepSize = size != null &&
        product.variants.any(
          (v) => v.color == event.color && v.size == size && v.inStock,
        );

    emit(
      state.copyWith(
        selectedColor: event.color,
        selectedSize: keepSize ? size : null,
        clearSize: !keepSize,
      ),
    );
  }

  void _onSizeSelected(
    ProductSizeSelected event,
    Emitter<ProductDetailState> emit,
  ) {
    ProductVariant? variant;
    for (final v in state.variantsForColor) {
      if (v.size == event.size) {
        variant = v;
        break;
      }
    }
    if (variant == null || !variant.inStock) return;

    emit(state.copyWith(selectedSize: event.size));
  }

  void _onStockChanged(
    ProductStockChanged event,
    Emitter<ProductDetailState> emit,
  ) {
    final product = state.product;
    if (product == null) return;

    final variants = [
      for (final v in product.variants)
        v.id == event.variantId
            ? v.copyWith(available: event.available, lowStock: event.lowStock)
            : v,
    ];
    emit(state.copyWith(product: product.copyWith(variants: variants)));
  }

  String? _defaultColor(ProductDetail product) {
    for (final c in product.colors) {
      final hasStock =
          product.variants.any((v) => v.color == c.name && v.inStock);
      if (hasStock) return c.name;
    }
    return product.colors.isNotEmpty ? product.colors.first.name : null;
  }

  // ---------------------------------------------------------------------------
  // Live updates (Socket.io)
  // ---------------------------------------------------------------------------

  void _startLive(String productId) {
    _stopLive();
    _watchedProductId = productId;

    _stockSub = _socket.on<Map<dynamic, dynamic>>(_evStock).listen((m) {
      if (m['productId']?.toString() != productId) return;
      final available = m['available'];
      if (available is! num) return;
      add(
        ProductStockChanged(
          variantId: m['variantId'].toString(),
          available: available.toInt(),
          lowStock: m['lowStock'] == true,
        ),
      );
    });

    // Price / promo / status changed: refetch the product.
    _updatedSub =
        _socket.on<Map<dynamic, dynamic>>(_evProductUpdated).listen((m) {
      if (m['productId']?.toString() == productId) {
        add(const ProductDetailReloaded());
      }
    });

    // Rooms are lost on reconnect, so join again every time we connect.
    _statusSub = _socket.statusStream.listen((status) {
      final connected = status == SocketStatus.connected;
      add(ProductLiveStatusChanged(connected: connected));
      if (connected) _emitSafely(_evWatch, productId);
    });

    if (_socket.isConnected) {
      add(const ProductLiveStatusChanged(connected: true));
      _emitSafely(_evWatch, productId);
    } else {
      unawaited(_connectWithFreshToken());
    }
  }

  Future<void> _connectWithFreshToken() async {
    try {
      await _refreshSession?.call();
      if (!isClosed) await _socket.reconnect();
    } catch (_) {
      // Live updates are optional; the page works without them.
    }
  }

  void _stopLive() {
    _stockSub?.cancel();
    _updatedSub?.cancel();
    _statusSub?.cancel();
    _stockSub = null;
    _updatedSub = null;
    _statusSub = null;

    final id = _watchedProductId;
    _watchedProductId = null;
    if (id != null) _emitSafely(_evUnwatch, id);
  }

  void _emitSafely(String event, String data) {
    try {
      _socket.emit(event, data);
    } catch (_) {
      // Socket not created yet / already closed: live updates are optional.
    }
  }

  @override
  Future<void> close() {
    _stopLive();
    return super.close();
  }
}
