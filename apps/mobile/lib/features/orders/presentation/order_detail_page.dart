import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/net_image.dart';
import '../data/order_repository.dart';
import '../domain/order.dart';
import 'orders_cubit.dart';
import 'widgets/delivery_countdown.dart';
import 'widgets/status_chip.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OrderDetailCubit>(
      create: (ctx) => OrderDetailCubit(
        repository: ctx.read<OrderRepository>(),
        socket: ctx.read<SocketService>(),
        orderId: orderId,
      )..load(),
      child: BlocListener<OrderDetailCubit, OrderDetailState>(
        listenWhen: (prev, curr) => curr.toast != null && curr.toast != prev.toast,
        listener: (context, state) => showToast(context, state.toast!),
        child: Scaffold(
          appBar: AppBar(title: const Text('Order details')),
          body: BlocBuilder<OrderDetailCubit, OrderDetailState>(
            builder: (context, state) {
              final order = state.order;

              if (order == null) {
                if (state.status == OrdersStatus.failure) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.errorMessage ?? 'Could not load this order.'),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                          onPressed: () => context.read<OrderDetailCubit>().load(),
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.orderNumber,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      StatusChip(order: order),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Placed ${formatDate(order.placedAt)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 20),
                  if (!order.isCancelled && !order.isDelivered && order.estimatedDelivery != null) ...[
                    DeliveryCountdown(target: order.estimatedDelivery!),
                    const SizedBox(height: 20),
                  ],
                  _Timeline(order: order),
                  if (order.trackingNumber != null) ...[
                    const SizedBox(height: 16),
                    _InfoBox(
                      icon: Icons.local_shipping_outlined,
                      title: order.courier == null ? 'Tracking number' : '${order.courier} tracking number',
                      body: order.trackingNumber!,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _SectionTitle('ITEMS'),
                  const SizedBox(height: 10),
                  for (final item in order.items) _ItemRow(item: item),
                  const Divider(height: 28),
                  _row('Subtotal', formatPrice(order.subtotal)),
                  const SizedBox(height: 6),
                  _row('Shipping', order.shippingFee == 0 ? 'Free' : formatPrice(order.shippingFee)),
                  const SizedBox(height: 10),
                  _row('Total', formatPrice(order.total), bold: true),
                  const SizedBox(height: 24),
                  const _SectionTitle('DELIVERY ADDRESS'),
                  const SizedBox(height: 8),
                  Text(order.address.formatted, style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 24),
                  const _SectionTitle('PAYMENT'),
                  const SizedBox(height: 8),
                  Text(
                    order.paymentMethod == 'COD'
                        ? 'Cash on delivery · ${order.paymentStatus == 'PAID' ? 'paid' : 'pay when it arrives'}'
                        : (order.paymentMethod ?? '-'),
                  ),
                  if (order.canCancel) ...[
                    const SizedBox(height: 32),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: state.busy ? null : () => _confirmCancel(context),
                      child: state.busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('CANCEL ORDER'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final cubit = context.read<OrderDetailCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Cancel this order?'),
        content: const Text('The items go back on the shelf and you will not be charged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('KEEP ORDER'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CANCEL ORDER'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.cancel();
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 56, height: 70, child: NetImage(item.imageUrl)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${item.color} · ${item.size} · Qty ${item.quantity}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(formatPrice(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 2),
                SelectableText(body, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placed -> Packing -> Ready to ship -> Shipped -> Delivered.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});

  final Order order;

  static const _stages = ['Order placed', 'Packing', 'Ready to ship', 'Shipped', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    if (order.isCancelled) {
      return _InfoBox(
        icon: Icons.cancel_outlined,
        title: 'Status',
        body: order.status == 'RETURNED' ? 'This order was returned' : 'This order was cancelled',
      );
    }

    final current = order.stage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _stages.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _Dot(done: i < current || (i == current && order.isDelivered), active: i == current),
                    if (i < _stages.length - 1)
                      Container(
                        width: 2,
                        height: 26,
                        color: i < current ? AppColors.olive : AppColors.outline,
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    _stages[i],
                    style: TextStyle(
                      fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                      color: i <= current ? AppColors.text : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return const Icon(Icons.check_circle, size: 22, color: AppColors.olive);
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.olive.withValues(alpha: 0.25) : Colors.transparent,
        border: Border.all(
          color: active ? AppColors.olive : AppColors.outline,
          width: 2,
        ),
      ),
    );
  }
}
