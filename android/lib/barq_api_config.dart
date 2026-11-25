const String defaultBarqApiBase = 'https://siraj-api-2026.vercel.app';

String resolveBarqApiBase(
  String configured, {
  String fallback = defaultBarqApiBase,
}) {
  final value = configured.trim();
  if (value.isEmpty) return fallback;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      (uri.host.toLowerCase() == 'workers.dev' || uri.host.toLowerCase().endsWith('.workers.dev')) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return fallback;
  }
  return value.replaceFirst(RegExp(r'/+$'), '');
}
