import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/color_option.dart';
import '../../../../core/services/socket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/product_detail.dart';
import '../../domain/repositories/product_repository.dart';
import '../bloc/product_detail_bloc.dart';

/// Product page: gallery with zoom, colour + size selection and a live
/// urgency banner ("Only 2 items left in Medium") fed by Socket.io.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProductDetailBloc>(
      create: (ctx) => ProductDetailBloc(
        repository: ctx.read<ProductRepository>(),
        socket: ctx.read<SocketService>(),
        refreshSession: () => ctx.read<AuthRepository>().hasSession(),
      )..add(ProductDetailStarted(slug)),
      child: const _ProductDetailView(),
    );
  }
}

class _ProductDetailView extends StatelessWidget {
  const _ProductDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductDetailBloc, ProductDetailState>(
      builder: (context, state) {
        final product = state.product;

        return Scaffold(
          appBar: AppBar(
            actions: [
              if (product != null) _LivePill(connected: state.liveConnected),
              const SizedBox(width: 12),
            ],
          ),
          body: _buildBody(context, state),
          bottomNavigationBar:
              product == null ? null : _AddToCartBar(state: state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ProductDetailState state) {
    final product = state.product;

    if (product == null) {
      if (state.status == ProductDetailStatus.failure) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.errorMessage ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context
                      .read<ProductDetailBloc>()
                      .add(const ProductDetailReloaded()),
                  child: const Text('RETRY'),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final bloc = context.read<ProductDetailBloc>();
    final price = state.displayPrice;
    final basePrice = product.basePrice;
    final showStrike = price != null && basePrice != null && basePrice > price;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Gallery(
          key: ValueKey<String?>(state.selectedColor),
          images: state.galleryImages,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.categoryName != null)
                Text(
                  product.categoryName!.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 2,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (price != null)
                    Text(
                      formatPrice(price),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (showStrike) ...[
                    const SizedBox(width: 10),
                    Text(
                      formatPrice(basePrice),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  if (product.promoTag != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.olive,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        product.promoTag!.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.onOlive,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              _StockBanner(state: state),
              const SizedBox(height: 24),
              _SectionLabel(
                'COLOR',
                trailing: state.selectedColor,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in product.colors)
                    _ColorSwatch(
                      option: c,
                      selected: c.name == state.selectedColor,
                      onTap: () => bloc.add(ProductColorSelected(c.name)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('SIZE'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final v in state.variantsForColor)
                    _SizeBox(
                      variant: v,
                      selected: v.size == state.selectedSize,
                      onTap: () => bloc.add(ProductSizeSelected(v.size)),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              const Divider(),
              if (_has(product.description))
                _InfoSection(title: 'Description', body: product.description!),
              if (_has(product.fabric))
                _InfoSection(title: 'Fabric', body: product.fabric!),
              if (_has(product.careNotes))
                _InfoSection(title: 'Care', body: product.careNotes!),
            ],
          ),
        ),
      ],
    );
  }

  bool _has(String? s) => s != null && s.trim().isNotEmpty;
}

// -----------------------------------------------------------------------------
// Live indicator + urgency banner
// -----------------------------------------------------------------------------

class _LivePill extends StatelessWidget {
  const _LivePill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.olive : AppColors.textMuted;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? 'LIVE' : 'OFFLINE',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _StockBanner extends StatelessWidget {
  const _StockBanner({required this.state});

  final ProductDetailState state;

  @override
  Widget build(BuildContext context) {
    final v = state.selectedVariant;

    final String text;
    final Color color;
    final IconData icon;

    if (v == null) {
      text = 'Select a size to see live availability';
      color = AppColors.textMuted;
      icon = Icons.straighten;
    } else if (!v.inStock) {
      text = 'Sold out in ${sizeLabel(v.size)}';
      color = AppColors.danger;
      icon = Icons.block;
    } else if (v.lowStock) {
      final noun = v.available == 1 ? 'item' : 'items';
      text = 'Only ${v.available} $noun left in ${sizeLabel(v.size)}';
      color = AppColors.amber;
      icon = Icons.local_fire_department_outlined;
    } else {
      text = 'In stock in ${sizeLabel(v.size)}';
      color = AppColors.olive;
      icon = Icons.check_circle_outline;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey<String>(text),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Selectors
// -----------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.textMuted,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(trailing!, style: const TextStyle(fontSize: 13)),
        ],
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: option.name,
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.olive : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorFromHex(option.hex),
              border: Border.all(color: AppColors.outline),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeBox extends StatelessWidget {
  const _SizeBox({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final ProductVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soldOut = !variant.inStock;
    final textColor = selected
        ? AppColors.onOlive
        : (soldOut ? AppColors.textMuted : AppColors.text);

    return GestureDetector(
      onTap: soldOut ? null : onTap,
      child: Container(
        width: 64,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.olive : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.olive : AppColors.outline,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              variant.size,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                decoration: soldOut ? TextDecoration.lineThrough : null,
              ),
            ),
            if (variant.lowStock && !soldOut && !selected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Add to cart bar (cart backend comes in the next step)
// -----------------------------------------------------------------------------

class _AddToCartBar extends StatelessWidget {
  const _AddToCartBar({required this.state});

  final ProductDetailState state;

  @override
  Widget build(BuildContext context) {
    final v = state.selectedVariant;

    String label;
    bool enabled;
    if (v == null) {
      label = 'SELECT A SIZE';
      enabled = false;
    } else if (!v.inStock) {
      label = 'SOLD OUT';
      enabled = false;
    } else {
      label = 'ADD TO CART';
      enabled = true;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: enabled
              ? () {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          'Cart arrives in the next update (${v!.color} / ${v.size}).',
                        ),
                      ),
                    );
                }
              : null,
          child: Text(label),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Gallery + full-screen zoom
// -----------------------------------------------------------------------------

class _Gallery extends StatefulWidget {
  const _Gallery({super.key, required this.images});

  final List<ProductImage> images;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openZoom(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ZoomViewer(
          images: widget.images,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;

    if (images.isEmpty) {
      return const AspectRatio(aspectRatio: 4 / 5, child: NetImage(null));
    }

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => _openZoom(i),
              child: NetImage(images[i].url),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.zoom_out_map, size: 16),
            ),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AppColors.text
                            : AppColors.text.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomViewer extends StatefulWidget {
  const _ZoomViewer({required this.images, required this.initialIndex});

  final List<ProductImage> images;
  final int initialIndex;

  @override
  State<_ZoomViewer> createState() => _ZoomViewerState();
}

class _ZoomViewerState extends State<_ZoomViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: NetImage(widget.images[i].url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
