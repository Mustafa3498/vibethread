import 'package:equatable/equatable.dart';

class CatalogItem extends Equatable {
  const CatalogItem({
    required this.id,
    required this.title,
    this.description,
    this.authorName,
    this.createdAt,
    this.price,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String? description;
  final String? authorName;
  final DateTime? createdAt;
  final double? price;
  final String? imageUrl;

  @override
  List<Object?> get props =>
      [id, title, description, authorName, createdAt, price, imageUrl];
}
