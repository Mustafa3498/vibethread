import 'package:equatable/equatable.dart';

class Address extends Equatable {
  const Address({
    required this.id,
    this.label,
    required this.line1,
    this.line2,
    required this.city,
    this.state,
    this.postalCode,
    this.isDefault = false,
  });

  final String id;
  final String? label;
  final String line1;
  final String? line2;
  final String city;
  final String? state;
  final String? postalCode;
  final bool isDefault;

  String get formatted {
    final parts = <String>[
      line1,
      if (line2 != null && line2!.isNotEmpty) line2!,
      city,
      [if (state != null && state!.isNotEmpty) state!, if (postalCode != null && postalCode!.isNotEmpty) postalCode!]
          .join(' '),
    ].where((p) => p.trim().isNotEmpty);
    return parts.join(', ');
  }

  @override
  List<Object?> get props => [id, label, line1, line2, city, state, postalCode, isDefault];
}

/// What the "add address" form collects.
class AddressDraft {
  const AddressDraft({
    this.label,
    required this.line1,
    this.line2,
    required this.city,
    this.state,
    this.postalCode,
  });

  final String? label;
  final String line1;
  final String? line2;
  final String city;
  final String? state;
  final String? postalCode;

  /// Only non-empty fields are sent (the API rejects nothing here, but keeps data tidy).
  Map<String, dynamic> toJson() {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return {
      if (clean(label) != null) 'label': clean(label),
      'line1': line1.trim(),
      if (clean(line2) != null) 'line2': clean(line2),
      'city': city.trim(),
      if (clean(state) != null) 'state': clean(state),
      if (clean(postalCode) != null) 'postalCode': clean(postalCode),
    };
  }
}
