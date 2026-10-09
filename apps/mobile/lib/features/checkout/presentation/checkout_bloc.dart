import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/utils/toast.dart';
import '../../cart/data/cart_repository.dart';
import '../../cart/domain/cart.dart';
import '../../orders/domain/order.dart';
import '../data/checkout_repository.dart';
import '../domain/address.dart';

enum CheckoutStatus { loading, ready, placing, placed, failure }

class CheckoutState extends Equatable {
  const CheckoutState({
    this.status = CheckoutStatus.loading,
    this.cart,
    this.addresses = const [],
    this.selectedAddressId,
    this.phone = '',
    this.order,
    this.errorMessage,
    this.toast,
  });

  final CheckoutStatus status;

  /// The cart with its stock hold (`holdExpiresAt`).
  final Cart? cart;
  final List<Address> addresses;
  final String? selectedAddressId;
  final String phone;
  final Order? order;

  /// Shown full-screen when the first load fails.
  final String? errorMessage;
  final Toast? toast;

  CheckoutState copyWith({
    CheckoutStatus? status,
    Cart? cart,
    List<Address>? addresses,
    String? selectedAddressId,
    String? phone,
    Order? order,
    String? errorMessage,
    Toast? toast,
  }) {
    return CheckoutState(
      status: status ?? this.status,
      cart: cart ?? this.cart,
      addresses: addresses ?? this.addresses,
      selectedAddressId: selectedAddressId ?? this.selectedAddressId,
      phone: phone ?? this.phone,
      order: order ?? this.order,
      errorMessage: errorMessage ?? this.errorMessage,
      toast: toast ?? this.toast,
    );
  }

  @override
  List<Object?> get props =>
      [status, cart, addresses, selectedAddressId, phone, order, errorMessage, toast];
}

sealed class CheckoutEvent extends Equatable {
  const CheckoutEvent();

  @override
  List<Object?> get props => [];
}

final class CheckoutStarted extends CheckoutEvent {
  const CheckoutStarted();
}

final class CheckoutAddressSelected extends CheckoutEvent {
  const CheckoutAddressSelected(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class CheckoutAddressCreated extends CheckoutEvent {
  const CheckoutAddressCreated(this.draft);

  final AddressDraft draft;
}

final class CheckoutPhoneChanged extends CheckoutEvent {
  const CheckoutPhoneChanged(this.phone);

  final String phone;

  @override
  List<Object?> get props => [phone];
}

/// The 15-minute hold ran out: reserve the items again.
final class CheckoutHoldRefreshed extends CheckoutEvent {
  const CheckoutHoldRefreshed();
}

final class CheckoutPlaceRequested extends CheckoutEvent {
  const CheckoutPlaceRequested();
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc({
    required CartRepository cartRepository,
    required CheckoutRepository repository,
  })  : _cartRepository = cartRepository,
        _repository = repository,
        super(const CheckoutState()) {
    on<CheckoutStarted>(_onStarted);
    on<CheckoutAddressSelected>(
      (event, emit) => emit(state.copyWith(selectedAddressId: event.id)),
    );
    on<CheckoutAddressCreated>(_onAddressCreated);
    on<CheckoutPhoneChanged>(
      (event, emit) => emit(state.copyWith(phone: event.phone)),
    );
    on<CheckoutHoldRefreshed>(_onHoldRefreshed);
    on<CheckoutPlaceRequested>(_onPlace);
  }

  final CartRepository _cartRepository;
  final CheckoutRepository _repository;

  Future<void> _onStarted(CheckoutStarted event, Emitter<CheckoutState> emit) async {
    emit(const CheckoutState());
    try {
      // Reserves the cart's stock for ~15 minutes.
      final cart = await _cartRepository.startCheckout();
      final addresses = await _repository.getAddresses();
      final phone = await _repository.getSavedPhone();

      emit(
        state.copyWith(
          status: CheckoutStatus.ready,
          cart: cart,
          addresses: addresses,
          selectedAddressId: _defaultAddress(addresses),
          phone: phone ?? '',
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(status: CheckoutStatus.failure, errorMessage: e.message));
    }
  }

  String? _defaultAddress(List<Address> addresses) {
    if (addresses.isEmpty) return null;
    for (final a in addresses) {
      if (a.isDefault) return a.id;
    }
    return addresses.first.id;
  }

  Future<void> _onAddressCreated(
    CheckoutAddressCreated event,
    Emitter<CheckoutState> emit,
  ) async {
    try {
      final created = await _repository.createAddress(event.draft);
      final addresses = await _repository.getAddresses();
      emit(state.copyWith(addresses: addresses, selectedAddressId: created.id));
    } on ApiException catch (e) {
      emit(state.copyWith(toast: Toast.error(e.message)));
    }
  }

  Future<void> _onHoldRefreshed(
    CheckoutHoldRefreshed event,
    Emitter<CheckoutState> emit,
  ) async {
    try {
      final cart = await _cartRepository.startCheckout();
      emit(state.copyWith(cart: cart, toast: Toast.info('Your items are reserved again')));
    } on ApiException catch (e) {
      emit(state.copyWith(toast: Toast.error(e.message)));
    }
  }

  Future<void> _onPlace(CheckoutPlaceRequested event, Emitter<CheckoutState> emit) async {
    if (state.status == CheckoutStatus.placing) return;

    final addressId = state.selectedAddressId;
    final phone = state.phone.trim();
    if (addressId == null) {
      emit(state.copyWith(toast: Toast.error('Choose or add a delivery address')));
      return;
    }
    if (phone.length < 7) {
      emit(state.copyWith(toast: Toast.error('Enter a phone number the courier can call')));
      return;
    }

    emit(state.copyWith(status: CheckoutStatus.placing));
    try {
      final order = await _repository.placeOrder(addressId: addressId, phone: phone);
      emit(state.copyWith(status: CheckoutStatus.placed, order: order));
    } on ApiException catch (e) {
      emit(state.copyWith(status: CheckoutStatus.ready, toast: Toast.error(e.message)));
    }
  }
}
