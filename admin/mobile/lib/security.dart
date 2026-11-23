import 'dart:convert';
import 'dart:math';

bool isValidAdminApiBase(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
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
