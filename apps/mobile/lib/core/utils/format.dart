import 'package:flutter/material.dart';

/// "Rs 2,499" (no decimals for whole amounts). Change [currency] in one place
/// if the store uses another currency.
String formatPrice(num value, {String currency = 'Rs'}) {
  final whole = value == value.roundToDouble();
  final fixed = whole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  final decimals = parts.length > 1 ? '.${parts[1]}' : '';
  return '$currency $buffer$decimals';
}

/// "#5b6340" or "5b6340" -> Color. Falls back to grey on bad input.
Color colorFromHex(String? hex, {Color fallback = const Color(0xFF777777)}) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}

/// "M" -> "Medium" (used in urgency messages like "Only 2 left in Medium").
String sizeLabel(String size) {
  const labels = {
    'XXS': 'Double Extra Small',
    'XS': 'Extra Small',
    'S': 'Small',
    'M': 'Medium',
    'L': 'Large',
    'XL': 'Extra Large',
    'XXL': '2X Large',
    '2XL': '2X Large',
  };
  return labels[size.toUpperCase()] ?? size;
}
