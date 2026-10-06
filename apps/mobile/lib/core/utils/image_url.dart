/// placehold.co serves SVG unless the URL has an image extension, and Flutter
/// cannot render SVG with Image.network. The seed data uses placehold.co
/// placeholders, so ask for PNG. Real image URLs are returned unchanged.
String resolveImageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'placehold.co') return url;

  final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  final hasExtension = RegExp(
    r'\.(png|jpe?g|gif|webp|avif|svg)$',
    caseSensitive: false,
  ).hasMatch(last);
  if (hasExtension) return url;

  return uri.replace(path: '${uri.path}.png').toString();
}
