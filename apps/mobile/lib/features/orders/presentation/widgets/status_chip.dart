import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/order.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (order.isCancelled) {
      color = AppColors.danger;
    } else if (order.isDelivered) {
      color = AppColors.olive;
    } else {
      color = AppColors.amber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        order.statusLabel.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
