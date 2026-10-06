part of 'catalog_bloc.dart';

sealed class CatalogEvent extends Equatable {
  const CatalogEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load (shows full-screen loader).
final class CatalogStarted extends CatalogEvent {
  const CatalogStarted();
}

/// Pull-to-refresh: keeps the current list visible while reloading.
final class CatalogRefreshed extends CatalogEvent {
  const CatalogRefreshed();
}

/// Infinite scroll: fired when the grid nears its end.
final class CatalogLoadMoreRequested extends CatalogEvent {
  const CatalogLoadMoreRequested();
}

/// Fired on every keystroke; the bloc debounces it.
final class CatalogSearchChanged extends CatalogEvent {
  const CatalogSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Sort / weather / in-stock changed.
final class CatalogFiltersChanged extends CatalogEvent {
  const CatalogFiltersChanged(this.filters);

  final CatalogFilters filters;

  @override
  List<Object?> get props => [filters];
}
