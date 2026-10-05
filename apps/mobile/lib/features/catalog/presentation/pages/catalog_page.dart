import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/catalog_item.dart';
import '../bloc/catalog_bloc.dart';

/// Main catalog screen. (Named `CatalogScreen` so it does not clash with the
/// `CatalogPage` pagination entity in the domain layer.)
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _scroll = ScrollController();

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
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300;
    if (nearEnd) {
      context.read<CatalogBloc>().add(const CatalogLoadMoreRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthLogoutRequested()),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (q) =>
                  context.read<CatalogBloc>().add(CatalogSearchChanged(q)),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: BlocConsumer<CatalogBloc, CatalogState>(
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
          if (state.status == CatalogStatus.initial ||
              (state.status == CatalogStatus.loading && state.items.isEmpty)) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == CatalogStatus.failure && state.items.isEmpty) {
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
                          .read<CatalogBloc>()
                          .add(const CatalogStarted()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.isEmpty) {
            return const Center(child: Text('No products found.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<CatalogBloc>().add(const CatalogRefreshed());
            },
            child: ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _CatalogTile(item: state.items[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final description = item.description;
    final price = item.price;
    final imageUrl = item.imageUrl;

    return ListTile(
      leading: imageUrl == null
          ? const CircleAvatar(child: Icon(Icons.checkroom))
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const CircleAvatar(child: Icon(Icons.checkroom)),
              ),
            ),
      title: Text(item.title),
      subtitle: description == null || description.isEmpty
          ? null
          : Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: price == null ? null : Text(price.toStringAsFixed(2)),
    );
  }
}
