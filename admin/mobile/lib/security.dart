bool isValidAdminApiBase(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/admin') &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

String normalizeAdminApiBase(String value) {
  final clean = value.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(clean);
  if (uri == null || !isValidAdminApiBase(clean)) {
    throw ArgumentError('invalid_admin_api_base');
  }
  return uri.path == '/admin' ? clean : '$clean/admin';
}
