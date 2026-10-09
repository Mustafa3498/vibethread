import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';

/// "Estimated delivery Fri, 9 Oct · in 1d 22h 14m", ticking every 30 seconds.
class DeliveryCountdown extends StatefulWidget {
  const DeliveryCountdown({super.key, required this.target});

  final DateTime target;

  @override
  State<DeliveryCountdown> createState() => _DeliveryCountdownState();
}

class _DeliveryCountdownState extends State<DeliveryCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
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
    final remaining = widget.target.difference(DateTime.now());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.olive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.olive.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, color: AppColors.olive),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimated delivery ${formatDay(widget.target)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining.isNegative ? 'Arriving any moment' : 'in ${formatRemaining(remaining)}',
                  style: const TextStyle(color: AppColors.olive, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
