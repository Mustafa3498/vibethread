import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/catalog_filters.dart';
import '../../domain/entities/catalog_item.dart';
import '../../domain/repositories/catalog_repository.dart';

part 'catalog_event.dart';
part 'catalog_state.dart';

class CatalogBloc extends Bloc<CatalogEvent, CatalogState> {
  CatalogBloc(this._repository) : super(const CatalogState()) {
    on<CatalogStarted>(_onStarted, transformer: droppable());
    on<CatalogRefreshed>(_onRefreshed, transformer: restartable());
    on<CatalogLoadMoreRequested>(_onLoadMore, transformer: droppable());
    on<CatalogSearchChanged>(_onSearchChanged, transformer: restartable());
    on<CatalogFiltersChanged>(_onFiltersChanged, transformer: restartable());
  }

  final CatalogRepository _repository;

  static const int _pageSize = 20;
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  Future<void> _onStarted(
    CatalogStarted event,
    Emitter<CatalogState> emit,
  ) =>
      _loadFirstPage(emit, showLoader: true);

  Future<void> _onRefreshed(
    CatalogRefreshed event,
    Emitter<CatalogState> emit,
  ) =>
      _loadFirstPage(emit, showLoader: false);

  Future<void> _onSearchChanged(
    CatalogSearchChanged event,
    Emitter<CatalogState> emit,
  ) async {
    final query = event.query.trim();

    // Debounce: `restartable()` cancels this handler if a newer keystroke
    // arrives during the delay, so `emit.isDone` becomes true.
    await Future<void>.delayed(_searchDebounce);
    if (emit.isDone || query == state.query) return;

    emit(
      state.copyWith(
        query: query,
        status: CatalogStatus.loading,
        items: const [],
        page: 0,
        hasMore: true,
        isLoadingMore: false,
        clearError: true,
      ),
    );
    await _loadFirstPage(emit, showLoader: false);
  }

  Future<void> _onFiltersChanged(
    CatalogFiltersChanged event,
    Emitter<CatalogState> emit,
  ) async {
    if (event.filters == state.filters) return;

    emit(
      state.copyWith(
        filters: event.filters,
        status: CatalogStatus.loading,
        items: const [],
        page: 0,
        hasMore: true,
        isLoadingMore: false,
        clearError: true,
      ),
    );
    await _loadFirstPage(emit, showLoader: false);
  }

  Future<void> _onLoadMore(
    CatalogLoadMoreRequested event,
    Emitter<CatalogState> emit,
  ) async {
    if (state.status != CatalogStatus.success ||
        !state.hasMore ||
        state.isLoadingMore) {
      return;
    }

    final query = state.query;
    final filters = state.filters;
    final nextPage = state.page + 1;
    emit(state.copyWith(isLoadingMore: true, clearError: true));

    try {
      final result = await _repository.getCatalog(
        page: nextPage,
        limit: _pageSize,
        query: query,
        filters: filters,
      );
      // Drop stale results if a refresh/search/filter replaced the list.
      if (emit.isDone ||
          query != state.query ||
          filters != state.filters ||
          state.page + 1 != nextPage) {
        return;
      }
      emit(
        state.copyWith(
          items: [...state.items, ...result.items],
          page: result.page,
          hasMore: result.hasMore,
          isLoadingMore: false,
        ),
      );
    } on CatalogException catch (e) {
      if (emit.isDone || query != state.query || filters != state.filters) {
        return;
      }
      emit(state.copyWith(isLoadingMore: false, errorMessage: e.message));
    }
  }

  Future<void> _loadFirstPage(
    Emitter<CatalogState> emit, {
    required bool showLoader,
  }) async {
    final query = state.query;
    final filters = state.filters;
    if (showLoader) {
      emit(state.copyWith(status: CatalogStatus.loading, clearError: true));
    }

    try {
      final result = await _repository.getCatalog(
        page: 1,
        limit: _pageSize,
        query: query,
        filters: filters,
      );
      if (emit.isDone || query != state.query || filters != state.filters) {
        return;
      }
      emit(
        state.copyWith(
          status: CatalogStatus.success,
          items: result.items,
          page: result.page,
          hasMore: result.hasMore,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } on CatalogException catch (e) {
      if (emit.isDone || query != state.query || filters != state.filters) {
        return;
      }
      emit(
        state.copyWith(
          status: CatalogStatus.failure,
          isLoadingMore: false,
          errorMessage: e.message,
        ),
      );
    }
  }
}
