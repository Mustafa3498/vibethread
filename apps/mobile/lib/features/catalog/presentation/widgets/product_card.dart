import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/net_image.dart';
import '../../domain/entities/catalog_item.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.item, required this.onTap});

  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = item.price;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(item.imageUrl),
                  if (item.promoTag != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Pill(
                        label: item.promoTag!.toUpperCase(),
                        background: AppColors.olive,
                        foreground: AppColors.onOlive,
                      ),
                    ),
                  if (!item.inStock)
                    const _SoldOutOverlay()
                  else if (item.lowStock)
                    const Positioned(
                      bottom: 8,
                      left: 8,
                      child: _Pill(
                        label: 'LOW STOCK',
                        background: AppColors.amber,
                        foreground: AppColors.onOlive,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          if (price != null)
            Row(
              children: [
                Text(
                  formatPrice(price),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.hasDiscount) ...[
                  const SizedBox(width: 6),
                  Text(
                    formatPrice(item.basePrice!),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 6),
          _ColorDots(item: item),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SoldOutOverlay extends StatelessWidget {
  const _SoldOutOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: const Center(
        child: Text(
          'SOLD OUT',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ColorDots extends StatelessWidget {
  const _ColorDots({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    const maxDots = 4;
    final shown = item.colors.take(maxDots).toList(growable: false);
    final extra = item.colors.length - shown.length;

    return SizedBox(
      height: 14,
      child: Row(
        children: [
          for (final c in shown)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorFromHex(c.hex),
                border: Border.all(color: AppColors.outline),
              ),
            ),
          if (extra > 0)
            Text(
              '+$extra',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}
