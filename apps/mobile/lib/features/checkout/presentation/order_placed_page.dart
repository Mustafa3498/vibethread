import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_detail_page.dart';
import '../../orders/presentation/widgets/delivery_countdown.dart';

class OrderPlacedScreen extends StatelessWidget {
  const OrderPlacedScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final eta = order.estimatedDelivery;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            const Icon(Icons.check_circle_outline, size: 72, color: AppColors.olive),
            const SizedBox(height: 20),
            const Text(
              'Order placed',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              order.orderNumber,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 28),
            if (eta != null) DeliveryCountdown(target: eta),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line('Items', '${order.itemCount}'),
                  const SizedBox(height: 8),
                  _line('Pay on delivery', formatPrice(order.total), bold: true),
                  const SizedBox(height: 8),
                  _line('Deliver to', order.address.formatted),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderDetailScreen(orderId: order.id),
                ),
              ),
              child: const Text('VIEW ORDER'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('CONTINUE SHOPPING'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: AppColors.textMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
