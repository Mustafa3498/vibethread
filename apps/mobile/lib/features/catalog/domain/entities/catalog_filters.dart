import 'package:equatable/equatable.dart';

enum CatalogSort {
  newest('newest', 'Newest'),
  trending('trending', 'Trending'),
  priceAsc('price_asc', 'Price: low to high'),
  priceDesc('price_desc', 'Price: high to low');

  const CatalogSort(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Server-side filters for `GET /api/products`.
class CatalogFilters extends Equatable {
  const CatalogFilters({
    this.sort = CatalogSort.newest,
    this.weather,
    this.inStockOnly = false,
  });

  final CatalogSort sort;

  /// hot | mild | cold | rainy | humid
  final String? weather;
  final bool inStockOnly;

  CatalogFilters copyWith({
    CatalogSort? sort,
    String? weather,
    bool clearWeather = false,
    bool? inStockOnly,
  }) {
    return CatalogFilters(
      sort: sort ?? this.sort,
      weather: clearWeather ? null : (weather ?? this.weather),
      inStockOnly: inStockOnly ?? this.inStockOnly,
    );
  }

  Map<String, dynamic> toQuery() => {
        'sort': sort.apiValue,
        if (weather != null) 'weather': weather,
        if (inStockOnly) 'inStock': 'true',
      };

  @override
  List<Object?> get props => [sort, weather, inStockOnly];
}
