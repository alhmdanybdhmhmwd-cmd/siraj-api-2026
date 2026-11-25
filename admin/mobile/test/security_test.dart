import 'package:flutter_test/flutter_test.dart';
import 'package:barq_admin/security.dart'
    show
        isValidAdminApiBase,
        resolveAdminApiBase,
        defaultAdminApiBase,
        createOidcNonce,
        googleOidcRedirectUri;

void main() {
  test('accepts HTTPS Admin API URLs with an optional path', () {
    expect(isValidAdminApiBase('https://admin.example.com'), isTrue);
    expect(isValidAdminApiBase('https://admin.example.com/api/v1'), isTrue);
    expect(isValidAdminApiBase(defaultAdminApiBase), isTrue);
  });

  test('rejects insecure or ambiguous Admin API URLs', () {
    expect(isValidAdminApiBase('http://admin.example.com'), isFalse);
    expect(
      isValidAdminApiBase('https://siraj-api.alhmdanybdhmhmwd.workers.dev'),
      isFalse,
    );
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

  test(
    'migrates empty and direct workers.dev settings to the public gateway',
    () {
      expect(resolveAdminApiBase(null), defaultAdminApiBase);
      expect(resolveAdminApiBase(''), defaultAdminApiBase);
      expect(
        resolveAdminApiBase('https://siraj-api.alhmdanybdhmhmwd.workers.dev'),
        defaultAdminApiBase,
      );
      expect(
        resolveAdminApiBase('https://admin.example.com/custom'),
        'https://admin.example.com/custom',
      );
    },
  );

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
