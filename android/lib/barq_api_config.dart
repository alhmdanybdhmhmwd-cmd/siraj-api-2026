const String defaultBarqApiBase = 'https://siraj-api-2026.vercel.app';

String resolveBarqApiBase(
  String configured, {
  String fallback = defaultBarqApiBase,
}) {
  final value = configured.trim();
  if (value.isEmpty) return fallback;
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase() ?? '';
  if (uri == null ||
      uri.scheme != 'https' ||
      host.isEmpty ||
      host == 'workers.dev' ||
      host.endsWith('.workers.dev') ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return fallback;
  }
  return value.replaceFirst(RegExp(r'/+$'), '');
}

String resolveBarqRealtimeUrl(String configured) {
  final value = configured.trim();
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase() ?? '';
  if (uri == null ||
      uri.scheme != 'wss' ||
      host.isEmpty ||
      host == 'workers.dev' ||
      host.endsWith('.workers.dev') ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return '';
  }
  return value;
}
