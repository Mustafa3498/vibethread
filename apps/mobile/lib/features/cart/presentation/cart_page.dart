import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/net_image.dart';
import '../../checkout/presentation/checkout_page.dart';
import '../domain/cart.dart';
import 'cart_bloc.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: BlocConsumer<CartBloc, CartState>(
        listenWhen: (prev, curr) => curr.toast != null && curr.toast != prev.toast,
        listener: (context, state) => showToast(context, state.toast!),
        builder: (context, state) {
          final cart = state.cart;

          if (cart == null) {
            if (state.status == CartStatus.failure) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load your cart.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                      onPressed: () => context.read<CartBloc>().add(const CartStarted()),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          if (cart.isEmpty) return const _EmptyCart();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final line in cart.items) ...[
                      _CartLineTile(line: line, busy: state.busy),
                      const Divider(height: 28),
                    ],
                    _ShippingProgress(cart: cart),
                    const SizedBox(height: 16),
                    _Summary(cart: cart),
                  ],
                ),
              ),
              _CheckoutBar(cart: cart, busy: state.busy),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Your cart is empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add something you like and it will show up here, on every device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CONTINUE SHOPPING'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.busy});

  final CartLine line;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CartBloc>();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 78, height: 98, child: NetImage(line.imageUrl)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${line.color} · ${line.size}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 4),
              _LineNote(line: line),
              const SizedBox(height: 8),
              Row(
                children: [
                  _QtyStepper(
                    quantity: line.quantity,
                    canIncrease: line.canIncrease && !busy,
                    canDecrease: !busy,
                    onChanged: (q) => bloc.add(CartQuantityChanged(line.variantId, q)),
                  ),
                  const Spacer(),
                  Text(
                    formatPrice(line.lineTotal),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
          onPressed: busy ? null : () => bloc.add(CartItemRemoved(line.variantId)),
        ),
      ],
    );
  }
}

class _LineNote extends StatelessWidget {
  const _LineNote({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    String? text;
    Color color = AppColors.danger;

    switch (line.issue) {
      case 'UNAVAILABLE':
        text = 'No longer available';
      case 'OUT_OF_STOCK':
        text = 'Sold out. Remove it to continue';
      case 'EXCEEDS_STOCK':
        text = 'Only ${line.available} left. Reduce the quantity';
      default:
        if (line.lowStock) {
          text = 'Only ${line.available} left';
          color = AppColors.amber;
        }
    }

    if (text == null) return const SizedBox.shrink();
    return Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600));
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.quantity,
    required this.canIncrease,
    required this.canDecrease,
    required this.onChanged,
  });

  final int quantity;
  final bool canIncrease;
  final bool canDecrease;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(quantity == 1 ? Icons.delete_outline : Icons.remove, size: 18),
            onPressed: canDecrease ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 18),
            onPressed: canIncrease ? () => onChanged(quantity + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _ShippingProgress extends StatelessWidget {
  const _ShippingProgress({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    if (cart.freeShippingThreshold <= 0) return const SizedBox.shrink();

    final qualifies = cart.amountToFreeShipping <= 0;
    final progress = (cart.subtotal / cart.freeShippingThreshold).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            qualifies
                ? 'You have free shipping'
                : 'Add ${formatPrice(cart.amountToFreeShipping)} more for free shipping',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: qualifies ? AppColors.olive : AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: AppColors.olive,
              backgroundColor: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row('Subtotal', formatPrice(cart.subtotal)),
        const SizedBox(height: 8),
        _row('Shipping', cart.shippingFee == 0 ? 'Free' : formatPrice(cart.shippingFee)),
        const Divider(height: 24),
        _row('Total', formatPrice(cart.total), bold: true),
      ],
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

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.cart, required this.busy});

  final Cart cart;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final blocked = cart.hasIssues;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (blocked)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Some items need your attention before checkout.',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            Row(
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
                    onPressed: (blocked || busy)
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()),
                            ),
                    child: const Text('CHECKOUT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
