import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/toast.dart';
import '../data/order_repository.dart';
import '../domain/order.dart';

const String _evOrderUpdated = 'order:updated';

enum OrdersStatus { loading, ready, failure }

// ───────────────────────── order history ─────────────────────────

class OrdersState extends Equatable {
  const OrdersState({
    this.status = OrdersStatus.loading,
    this.orders = const [],
    this.errorMessage,
  });

  final OrdersStatus status;
  final List<Order> orders;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, orders, errorMessage];
}

class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit({required OrderRepository repository, required SocketService socket})
      : _repository = repository,
        super(const OrdersState()) {
    // A shopkeeper moved one of my orders: refresh quietly.
    _sub = socket
        .on<Map<dynamic, dynamic>>(_evOrderUpdated)
        .listen((_) => load(silent: true));
  }

  final OrderRepository _repository;
  StreamSubscription<Map<dynamic, dynamic>>? _sub;

  Future<void> load({bool silent = false}) async {
    if (!silent) emit(const OrdersState());
    try {
      final orders = await _repository.listMine();
      if (isClosed) return;
      emit(OrdersState(status: OrdersStatus.ready, orders: orders));
    } on ApiException catch (e) {
      if (isClosed || silent) return;
      emit(OrdersState(status: OrdersStatus.failure, errorMessage: e.message));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

// ───────────────────────── one order ─────────────────────────

class OrderDetailState extends Equatable {
  const OrderDetailState({
    this.status = OrdersStatus.loading,
    this.order,
    this.busy = false,
    this.errorMessage,
    this.toast,
  });

  final OrdersStatus status;
  final Order? order;

  /// Cancelling is in progress.
  final bool busy;
  final String? errorMessage;
  final Toast? toast;

  OrderDetailState copyWith({
    OrdersStatus? status,
    Order? order,
    bool? busy,
    String? errorMessage,
    Toast? toast,
  }) {
    return OrderDetailState(
      status: status ?? this.status,
      order: order ?? this.order,
      busy: busy ?? this.busy,
      errorMessage: errorMessage ?? this.errorMessage,
      toast: toast ?? this.toast,
    );
  }

  @override
  List<Object?> get props => [status, order, busy, errorMessage, toast];
}

class OrderDetailCubit extends Cubit<OrderDetailState> {
  OrderDetailCubit({
    required OrderRepository repository,
    required SocketService socket,
    required String orderId,
  })  : _repository = repository,
        _orderId = orderId,
        super(const OrderDetailState()) {
    _sub = socket.on<Map<dynamic, dynamic>>(_evOrderUpdated).listen((m) {
      if (m['id']?.toString() == _orderId) load(silent: true);
    });
  }

  final OrderRepository _repository;
  final String _orderId;
  StreamSubscription<Map<dynamic, dynamic>>? _sub;

  Future<void> load({bool silent = false}) async {
    if (!silent) emit(const OrderDetailState());
    try {
      final order = await _repository.getById(_orderId);
      if (isClosed) return;
      emit(state.copyWith(status: OrdersStatus.ready, order: order));
    } on ApiException catch (e) {
      if (isClosed || silent) return;
      emit(state.copyWith(status: OrdersStatus.failure, errorMessage: e.message));
    }
  }

  Future<void> cancel() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      final order = await _repository.cancel(_orderId);
      if (isClosed) return;
      emit(
        state.copyWith(
          order: order,
          busy: false,
          toast: Toast.info('Order cancelled'),
        ),
      );
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(busy: false, toast: Toast.error(e.message)));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
