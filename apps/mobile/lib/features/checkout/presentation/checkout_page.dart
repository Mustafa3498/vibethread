import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/tracking/tracking_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/toast.dart';
import '../../cart/data/cart_repository.dart';
import '../../cart/domain/cart.dart';
import '../data/checkout_repository.dart';
import '../domain/address.dart';
import 'address_form_sheet.dart';
import 'checkout_bloc.dart';
import 'order_placed_page.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CheckoutBloc>(
      create: (ctx) => CheckoutBloc(
        cartRepository: ctx.read<CartRepository>(),
        repository: ctx.read<CheckoutRepository>(),
      )..add(const CheckoutStarted()),
      child: const _CheckoutView(),
    );
  }
}

class _CheckoutView extends StatelessWidget {
  const _CheckoutView();

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // CHECKOUT_START: once per visit, when the priced cart + hold arrive
        BlocListener<CheckoutBloc, CheckoutState>(
          listenWhen: (prev, curr) =>
              prev.cart == null && curr.cart != null && curr.status != CheckoutStatus.failure,
          listener: (context, state) {
            final t = context.read<TrackingService>()..setPage('checkout');
            for (final l in state.cart!.items) {
              t.track(TrackType.checkoutStart,
                  variantId: l.variantId, page: 'checkout', meta: {'qty': l.quantity});
            }
          },
        ),
        BlocListener<CheckoutBloc, CheckoutState>(
          listenWhen: (prev, curr) => curr.toast != null && curr.toast != prev.toast,
          listener: (context, state) => showToast(context, state.toast!),
        ),
        BlocListener<CheckoutBloc, CheckoutState>(
          listenWhen: (prev, curr) =>
              prev.status != curr.status && curr.status == CheckoutStatus.placed,
          listener: (context, state) {
            final order = state.order;
            if (order == null) return;
            final t = context.read<TrackingService>();
            for (final l in state.cart?.items ?? const []) {
              t.track(TrackType.checkoutComplete,
                  variantId: l.variantId, page: 'checkout', meta: {'qty': l.quantity});
            }
            unawaited(t.flush());
            // Back stack becomes: catalog -> order confirmation.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => OrderPlacedScreen(order: order)),
              (route) => route.isFirst,
            );
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: BlocBuilder<CheckoutBloc, CheckoutState>(
          builder: (context, state) {
            if (state.status == CheckoutStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            final cart = state.cart;
            if (state.status == CheckoutStatus.failure || cart == null) {
              return _CheckoutError(message: state.errorMessage);
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _HoldBanner(expiresAt: cart.holdExpiresAt),
                      const SizedBox(height: 24),
                      const _SectionTitle('DELIVERY ADDRESS'),
                      const SizedBox(height: 10),
                      for (final a in state.addresses) ...[
                        _AddressCard(
                          address: a,
                          selected: a.id == state.selectedAddressId,
                          onTap: () =>
                              context.read<CheckoutBloc>().add(CheckoutAddressSelected(a.id)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(state.addresses.isEmpty ? 'Add delivery address' : 'Add new address'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: AppColors.text,
                          side: const BorderSide(color: AppColors.outline),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _addAddress(context),
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle('CONTACT NUMBER'),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: state.phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 0300 1234567',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        onChanged: (v) =>
                            context.read<CheckoutBloc>().add(CheckoutPhoneChanged(v)),
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle('PAYMENT'),
                      const SizedBox(height: 10),
                      const _CodCard(),
                      const SizedBox(height: 24),
                      const _SectionTitle('ORDER SUMMARY'),
                      const SizedBox(height: 10),
                      _OrderSummary(cart: cart),
                    ],
                  ),
                ),
                _PlaceOrderBar(cart: cart, placing: state.status == CheckoutStatus.placing),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addAddress(BuildContext context) async {
    final bloc = context.read<CheckoutBloc>();
    final draft = await showAddressSheet(context);
    if (draft != null) bloc.add(CheckoutAddressCreated(draft));
  }
}

class _CheckoutError extends StatelessWidget {
  const _CheckoutError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message ?? 'Could not start checkout.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
              onPressed: () => context.read<CheckoutBloc>().add(const CheckoutStarted()),
              child: const Text('TRY AGAIN'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to cart'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// "Your items are reserved for 14:32", ticking every second.
class _HoldBanner extends StatefulWidget {
  const _HoldBanner({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  State<_HoldBanner> createState() => _HoldBannerState();
}

class _HoldBannerState extends State<_HoldBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = widget.expiresAt;
    if (expiresAt == null) return const SizedBox.shrink();

    final remaining = expiresAt.difference(DateTime.now());
    final expired = remaining.isNegative || remaining.inSeconds == 0;
    final urgent = !expired && remaining.inMinutes < 3;
    final color = expired
        ? AppColors.danger
        : (urgent ? AppColors.amber : AppColors.olive);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              expired
                  ? 'Reservation expired'
                  : 'Your items are reserved for ${formatCountdown(remaining)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          if (expired)
            TextButton(
              onPressed: () => context.read<CheckoutBloc>().add(const CheckoutHoldRefreshed()),
              child: const Text('RESERVE AGAIN'),
            ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.selected, required this.onTap});

  final Address address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.olive : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppColors.olive : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (address.label != null && address.label!.isNotEmpty)
                    Text(
                      address.label!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  Text(
                    address.formatted,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodCard extends StatelessWidget {
  const _CodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.olive, width: 2),
      ),
      child: const Row(
        children: [
          Icon(Icons.payments_outlined, color: AppColors.olive),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cash on delivery', style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  'Pay the courier when your order arrives.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: AppColors.olive),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final line in cart.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${line.quantity} × ${line.name} (${line.color}, ${line.size})',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(formatPrice(line.lineTotal), style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          const Divider(height: 20),
          _row('Subtotal', formatPrice(cart.subtotal)),
          const SizedBox(height: 6),
          _row('Shipping', cart.shippingFee == 0 ? 'Free' : formatPrice(cart.shippingFee)),
          const Divider(height: 20),
          _row('Total', formatPrice(cart.total), bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style.copyWith(color: bold ? null : AppColors.textMuted)),
        Text(value, style: style),
      ],
    );
  }
}

class _PlaceOrderBar extends StatelessWidget {
  const _PlaceOrderBar({required this.cart, required this.placing});

  final Cart cart;
  final bool placing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Total', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                Text(
                  formatPrice(cart.total),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: FilledButton(
                onPressed: placing
                    ? null
                    : () => context.read<CheckoutBloc>().add(const CheckoutPlaceRequested()),
                child: placing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('PLACE ORDER'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
