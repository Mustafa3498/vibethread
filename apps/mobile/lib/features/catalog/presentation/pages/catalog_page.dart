import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../product/presentation/pages/product_detail_page.dart';
import '../../domain/entities/catalog_filters.dart';
import '../../domain/entities/catalog_item.dart';
import '../bloc/catalog_bloc.dart';
import '../widgets/product_card.dart';

/// Storefront home: search, filters, product grid.
/// (Named `CatalogScreen` so it does not clash with the `CatalogPage`
/// pagination entity in the domain layer.)
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    context.read<CatalogBloc>().add(const CatalogStarted());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 400;
    if (nearEnd) {
      context.read<CatalogBloc>().add(const CatalogLoadMoreRequested());
    }
  }

  void _openProduct(CatalogItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(slug: item.slug),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<CatalogBloc, CatalogState>(
          listenWhen: (prev, curr) =>
              curr.errorMessage != null &&
              curr.errorMessage != prev.errorMessage &&
              curr.items.isNotEmpty,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          },
          builder: (context, state) {
            return RefreshIndicator(
              color: AppColors.olive,
              onRefresh: () async {
                context.read<CatalogBloc>().add(const CatalogRefreshed());
                await Future<void>.delayed(const Duration(milliseconds: 700));
              },
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _Header(onLogout: _logout)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onChanged: (q) => context
                            .read<CatalogBloc>()
                            .add(CatalogSearchChanged(q)),
                        decoration: const InputDecoration(
                          hintText: 'Search the collection',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FilterBar(
                      filters: state.filters,
                      onChanged: (f) => context
                          .read<CatalogBloc>()
                          .add(CatalogFiltersChanged(f)),
                    ),
                  ),
                  ..._buildBody(context, state),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _logout() =>
      context.read<AuthBloc>().add(const AuthLogoutRequested());

  List<Widget> _buildBody(BuildContext context, CatalogState state) {
    if (state.status == CatalogStatus.initial ||
        (state.status == CatalogStatus.loading && state.items.isEmpty)) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state.status == CatalogStatus.failure && state.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
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
                        .read<CatalogBloc>()
                        .add(const CatalogStarted()),
                    child: const Text('RETRY'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (state.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'No products match your filters.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ),
      ];
    }

    final items = state.items;
    return [
      SliverLayoutBuilder(
        builder: (context, constraints) {
          // 16px side padding x2 + 12px gap between the two columns.
          final cellWidth = (constraints.crossAxisExtent - 32 - 12) / 2;
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 12,
                mainAxisExtent: cellWidth * 1.25 + 78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProductCard(
                  item: items[i],
                  onTap: () => _openProduct(items[i]),
                ),
                childCount: items.length,
              ),
            ),
          );
        },
      ),
      if (state.isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          const Text(
            'VIBETHREAD',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

const Map<String, String> _weatherLabels = {
  'hot': '☀️ Hot',
  'mild': '🌤 Mild',
  'cold': '❄️ Cold',
  'rainy': '🌧 Rainy',
  'humid': '💧 Humid',
};

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filters, required this.onChanged});

  final CatalogFilters filters;
  final ValueChanged<CatalogFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Center(
            child: PopupMenuButton<CatalogSort>(
              initialValue: filters.sort,
              color: AppColors.surfaceHigh,
              onSelected: (sort) => onChanged(filters.copyWith(sort: sort)),
              itemBuilder: (_) => [
                for (final sort in CatalogSort.values)
                  PopupMenuItem<CatalogSort>(
                    value: sort,
                    child: Text(sort.label),
                  ),
              ],
              child: _SortChip(
                label: filters.sort.label,
                active: filters.sort != CatalogSort.newest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'In stock',
            selected: filters.inStockOnly,
            onTap: () =>
                onChanged(filters.copyWith(inStockOnly: !filters.inStockOnly)),
          ),
          for (final entry in _weatherLabels.entries) ...[
            const SizedBox(width: 8),
            _chip(
              label: entry.value,
              selected: filters.weather == entry.key,
              onTap: () => onChanged(
                filters.weather == entry.key
                    ? filters.copyWith(clearWeather: true)
                    : filters.copyWith(weather: entry.key),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Center(
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: active
            ? AppColors.olive.withValues(alpha: 0.22)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_vert, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
