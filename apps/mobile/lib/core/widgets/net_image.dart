import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/image_url.dart';

/// Network image with a neutral placeholder for loading / missing / broken.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) return const _Placeholder();

    return Image.network(
      resolveImageUrl(source),
      fit: fit,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _Placeholder(),
      errorBuilder: (context, error, stack) =>
          const _Placeholder(icon: Icons.broken_image_outlined),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.icon = Icons.checkroom});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceHigh,
      child: Center(child: Icon(icon, color: AppColors.textMuted, size: 32)),
    );
  }
}
