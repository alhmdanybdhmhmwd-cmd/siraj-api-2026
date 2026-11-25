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
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.host.toLowerCase().endsWith('.workers.dev') ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return _fallbackPublicApiGatewayOrigin;
  }
  return value.replaceFirst(RegExp(r'/+

String resolveAdminApiBase(String? configured) {
  final value = configured?.trim() ?? '';
  final uri = Uri.tryParse(value);
  // Older builds stored the Cloudflare workers.dev URL directly. Migrate
  // those installations to the same public Vercel gateway used by BARQ.
  if (value.isEmpty ||
      (uri?.host.toLowerCase().endsWith('.workers.dev') ?? false)) {
    return defaultAdminApiBase;
  }
  return value;
}

bool isValidAdminApiBase(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !uri.host.toLowerCase().endsWith('.workers.dev') &&
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
), '');
}

final String defaultAdminApiBase = '${_resolveAdminGatewayOrigin()}/api/admin';

String resolveAdminApiBase(String? configured) {
  final value = configured?.trim() ?? '';
  final uri = Uri.tryParse(value);
  // Older builds stored the Cloudflare workers.dev URL directly. Migrate
  // those installations to the same public Vercel gateway used by BARQ.
  if (value.isEmpty ||
      (uri?.host.toLowerCase().endsWith('.workers.dev') ?? false)) {
    return defaultAdminApiBase;
  }
  return value;
}

bool isValidAdminApiBase(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !uri.host.toLowerCase().endsWith('.workers.dev') &&
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
