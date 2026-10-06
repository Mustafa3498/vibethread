part of 'catalog_bloc.dart';

enum CatalogStatus { initial, loading, success, failure }

final class CatalogState extends Equatable {
  const CatalogState({
    this.status = CatalogStatus.initial,
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.query = '',
    this.filters = const CatalogFilters(),
    this.errorMessage,
  });

  final CatalogStatus status;
  final List<CatalogItem> items;

  /// Last page successfully loaded (0 = nothing loaded yet).
  final int page;
  final bool hasMore;
  final bool isLoadingMore;
  final String query;
  final CatalogFilters filters;

  /// On `failure` with a non-empty [items] list (failed refresh), keep showing
  /// the grid and surface this in a snackbar instead of an error screen.
  final String? errorMessage;

  bool get isEmpty => status == CatalogStatus.success && items.isEmpty;

  CatalogState copyWith({
    CatalogStatus? status,
    List<CatalogItem>? items,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
    String? query,
    CatalogFilters? filters,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CatalogState(
      status: status ?? this.status,
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      query: query ?? this.query,
      filters: filters ?? this.filters,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props =>
      [status, items, page, hasMore, isLoadingMore, query, filters, errorMessage];
}
