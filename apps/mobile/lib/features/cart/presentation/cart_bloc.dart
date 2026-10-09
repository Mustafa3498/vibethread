import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/toast.dart';
import '../data/cart_repository.dart';
import '../domain/cart.dart';

const String _evCartSync = 'cart:sync';

enum CartStatus { initial, loading, ready, failure }

class CartState extends Equatable {
  const CartState({
    this.status = CartStatus.initial,
    this.cart,
    this.busy = false,
    this.toast,
  });

  final CartStatus status;
  final Cart? cart;

  /// A cart change is in flight (disables the buttons that would repeat it).
  final bool busy;
  final Toast? toast;

  int get itemCount => cart?.itemCount ?? 0;

  CartState copyWith({
    CartStatus? status,
    Cart? cart,
    bool? busy,
    Toast? toast,
  }) {
    return CartState(
      status: status ?? this.status,
      cart: cart ?? this.cart,
      busy: busy ?? this.busy,
      toast: toast ?? this.toast,
    );
  }

  @override
  List<Object?> get props => [status, cart, busy, toast];
}

sealed class CartEvent extends Equatable {
  const CartEvent();

  @override
  List<Object?> get props => [];
}

final class CartStarted extends CartEvent {
  const CartStarted();
}

final class CartItemAdded extends CartEvent {
  const CartItemAdded(this.variantId, {this.quantity = 1});

  final String variantId;
  final int quantity;

  @override
  List<Object?> get props => [variantId, quantity];
}

final class CartQuantityChanged extends CartEvent {
  const CartQuantityChanged(this.variantId, this.quantity);

  final String variantId;
  final int quantity;

  @override
  List<Object?> get props => [variantId, quantity];
}

final class CartItemRemoved extends CartEvent {
  const CartItemRemoved(this.variantId);

  final String variantId;

  @override
  List<Object?> get props => [variantId];
}

/// The server pushed a new cart (another device changed it, or checkout/order happened).
final class CartSynced extends CartEvent {
  const CartSynced(this.cart);

  final Cart cart;

  @override
  List<Object?> get props => [cart];
}

/// Signed out: forget the cart.
final class CartReset extends CartEvent {
  const CartReset();
}

class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc({required CartRepository repository, required SocketService socket})
      : _repository = repository,
        super(const CartState()) {
    on<CartStarted>(_onStarted, transformer: restartable());
    on<CartItemAdded>(_onAdded, transformer: sequential());
    on<CartQuantityChanged>(_onQuantity, transformer: sequential());
    on<CartItemRemoved>(_onRemoved, transformer: sequential());
    on<CartSynced>(
      (event, emit) => emit(state.copyWith(status: CartStatus.ready, cart: event.cart)),
    );
    on<CartReset>((event, emit) => emit(const CartState()));

    // Live cart across devices. The socket service keeps this stream alive over reconnects.
    _syncSub = socket.on<Map<dynamic, dynamic>>(_evCartSync).listen((payload) {
      try {
        add(CartSynced(parseCart(payload)));
      } catch (_) {
        // Ignore a malformed payload; the next change fixes it.
      }
    });
  }

  final CartRepository _repository;
  StreamSubscription<Map<dynamic, dynamic>>? _syncSub;

  Future<void> _onStarted(CartStarted event, Emitter<CartState> emit) async {
    if (state.cart == null) emit(state.copyWith(status: CartStatus.loading));
    try {
      final cart = await _repository.getCart();
      emit(state.copyWith(status: CartStatus.ready, cart: cart));
    } on ApiException {
      if (state.cart == null) emit(state.copyWith(status: CartStatus.failure));
    }
  }

  Future<void> _onAdded(CartItemAdded event, Emitter<CartState> emit) async {
    emit(state.copyWith(busy: true));
    try {
      final cart = await _repository.addItem(event.variantId, quantity: event.quantity);
      emit(
        state.copyWith(
          status: CartStatus.ready,
          cart: cart,
          busy: false,
          toast: Toast.info('Added to cart'),
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, toast: Toast.error(e.message)));
    }
  }

  Future<void> _onQuantity(CartQuantityChanged event, Emitter<CartState> emit) async {
    emit(state.copyWith(busy: true));
    try {
      final cart = await _repository.setQuantity(event.variantId, event.quantity);
      emit(state.copyWith(status: CartStatus.ready, cart: cart, busy: false));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, toast: Toast.error(e.message)));
    }
  }

  Future<void> _onRemoved(CartItemRemoved event, Emitter<CartState> emit) async {
    emit(state.copyWith(busy: true));
    try {
      final cart = await _repository.removeItem(event.variantId);
      emit(state.copyWith(status: CartStatus.ready, cart: cart, busy: false));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, toast: Toast.error(e.message)));
    }
  }

  @override
  Future<void> close() {
    _syncSub?.cancel();
    return super.close();
  }
}
