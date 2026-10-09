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

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Fri, 9 Oct"
String formatDay(DateTime value) {
  final d = value.toLocal();
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// "9 Oct 2026"
String formatDate(DateTime value) {
  final d = value.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// 14:05 (minutes:seconds) for the stock-hold timer.
String formatCountdown(Duration remaining) {
  final total = remaining.isNegative ? 0 : remaining.inSeconds;
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// "1d 22h 14m" for the delivery countdown.
String formatRemaining(Duration remaining) {
  if (remaining.isNegative || remaining.inMinutes == 0) return 'any moment now';
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (remaining.inHours > 0) return '${remaining.inHours}h ${minutes}m';
  return '${remaining.inMinutes}m';
}
