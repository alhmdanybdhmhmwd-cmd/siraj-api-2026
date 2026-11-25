import 'dart:convert';
import 'dart:math';

const String _configuredBarqApiGatewayOrigin = String.fromEnvironment(
  'BARQ_API_BASE',
  defaultValue: 'https://siraj-api-2026.vercel.app',
);
const String _fallbackPublicApiGatewayOrigin =
    'https://siraj-api-2026.vercel.app';

String _resolveAdminGatewayOrigin() {
  final value = _configuredBarqApiGatewayOrigin.trim();
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
    return _fallbackPublicApiGatewayOrigin;
  }
  return value.replaceFirst(RegExp('/+$'), '');
}

final String defaultAdminApiBase = '${_resolveAdminGatewayOrigin()}/api/admin';

String resolveAdminApiBase(String? configured) {
  final value = configured?.trim() ?? '';
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase() ?? '';
  // Migrate old direct Cloudflare endpoints to the public Vercel gateway.
  if (value.isEmpty || host == 'workers.dev' || host.endsWith('.workers.dev')) {
    return defaultAdminApiBase;
  }
  return value;
}

bool isValidAdminApiBase(String value) {
  final uri = Uri.tryParse(value.trim());
  final host = uri?.host.toLowerCase() ?? '';
  return uri != null &&
      uri.scheme == 'https' &&
      host.isNotEmpty &&
      host != 'workers.dev' &&
      !host.endsWith('.workers.dev') &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

String createOidcNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String googleOidcRedirectUri(String clientId) {
  final clean = clientId.trim();
  if (!clean.endsWith('.apps.googleusercontent.com')) {
    throw ArgumentError('invalid_google_client_id');
  }
  final clientPrefix = clean.substring(0, clean.indexOf('.'));
  if (clientPrefix.isEmpty ||
      !RegExp(r'^[0-9]+-[A-Za-z0-9_-]+$').hasMatch(clientPrefix)) {
    throw ArgumentError('invalid_google_client_id');
  }
  return 'com.googleusercontent.apps.$clientPrefix:/oauth2redirect';
}
