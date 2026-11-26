import 'package:flutter_test/flutter_test.dart';
import 'package:barq_admin/security.dart'
    show isValidAdminApiBase, normalizeAdminApiBase, createOidcNonce, googleOidcRedirectUri;

void main() {
  test('accepts only the shared Admin route or its host origin', () {
    expect(isValidAdminApiBase('https://admin.example.com'), isTrue);
    expect(isValidAdminApiBase('https://admin.example.com/admin'), isTrue);
    expect(isValidAdminApiBase('https://admin.example.com/api/v1'), isFalse);
    expect(normalizeAdminApiBase('https://admin.example.com'), 'https://admin.example.com/admin');
    expect(normalizeAdminApiBase('https://admin.example.com/admin'), 'https://admin.example.com/admin');
  });

  test('rejects insecure or ambiguous Admin API URLs', () {
    expect(isValidAdminApiBase('http://admin.example.com'), isFalse);
    expect(isValidAdminApiBase('admin.example.com'), isFalse);
    expect(isValidAdminApiBase('https:///missing-host'), isFalse);
    expect(isValidAdminApiBase('https://user:pass@admin.example.com'), isFalse);
    expect(
      isValidAdminApiBase('https://admin.example.com?token=secret'),
      isFalse,
    );
    expect(isValidAdminApiBase('https://admin.example.com#fragment'), isFalse);
    expect(isValidAdminApiBase(''), isFalse);
  });

  test('creates a strong nonce and canonical Google native redirect URI', () {
    final first = createOidcNonce();
    final second = createOidcNonce();
    expect(first, isNot(equals(second)));
    expect(first.length, greaterThanOrEqualTo(40));
    expect(
      googleOidcRedirectUri('1234567890-abcdef.apps.googleusercontent.com'),
      'com.googleusercontent.apps.1234567890-abcdef:/oauth2redirect',
    );
    expect(
      () => googleOidcRedirectUri('not-a-google-client-id'),
      throwsArgumentError,
    );
  });
}
