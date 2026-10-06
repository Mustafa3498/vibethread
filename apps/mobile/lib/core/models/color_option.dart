import 'package:equatable/equatable.dart';

/// A product colour: display name + optional hex ("#5b6340").
class ColorOption extends Equatable {
  const ColorOption({required this.name, this.hex});

  final String name;
  final String? hex;

  @override
  List<Object?> get props => [name, hex];
}
