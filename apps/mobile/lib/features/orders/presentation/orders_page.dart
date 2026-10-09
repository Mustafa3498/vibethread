import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/net_image.dart';
import '../data/order_repository.dart';
import '../domain/order.dart';
import 'order_detail_page.dart';
import 'orders_cubit.dart';
import 'widgets/status_chip.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OrdersCubit>(
      create: (ctx) => OrdersCubit(
        repository: ctx.read<OrderRepository>(),
        socket: ctx.read<SocketService>(),
      )..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('My orders')),
        body: BlocBuilder<OrdersCubit, OrdersState>(
          builder: (context, state) {
            if (state.status == OrdersStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.status == OrdersStatus.failure) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.errorMessage ?? 'Could not load your orders.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                      onPressed: () => context.read<OrdersCubit>().load(),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              );
            }

            if (state.orders.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textMuted),
                      SizedBox(height: 16),
                      Text('No orders yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
                      Text(
                        'Your orders will appear here after checkout.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }

            return RefreshIndicator(
              color: AppColors.olive,
              onRefresh: () => context.read<OrdersCubit>().load(silent: true),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: state.orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _OrderCard(order: state.orders[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final thumbs = order.items.take(3).toList(growable: false);
    final extra = order.items.length - thumbs.length;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: order.id)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                ),
                StatusChip(order: order),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Placed ${formatDate(order.placedAt)} · ${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final item in thumbs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(width: 48, height: 60, child: NetImage(item.imageUrl)),
                    ),
                  ),
                if (extra > 0)
                  Text('+$extra', style: const TextStyle(color: AppColors.textMuted)),
                const Spacer(),
                Text(
                  formatPrice(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
