import 'package:flutter_test/flutter_test.dart';
import 'package:barq_admin/security.dart'
    show
        isValidAdminApiBase,
        createOidcNonce,
        googleOidcRedirectUri,
        shouldSyncOnResume;

void main() {
  test('accepts HTTPS Admin API URLs with an optional path', () {
    expect(isValidAdminApiBase('https://admin.example.com'), isTrue);
    expect(isValidAdminApiBase('https://admin.example.com/api/v1'), isTrue);
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

  test(
    'throttles rapid foreground resume syncs without blocking later refreshes',
    () {
      final first = DateTime.utc(2026, 11, 25, 0, 0);
      expect(shouldSyncOnResume(null, first), isTrue);
      expect(
        shouldSyncOnResume(first, first.add(const Duration(seconds: 20))),
        isFalse,
      );
      expect(
        shouldSyncOnResume(first, first.add(const Duration(seconds: 45))),
        isTrue,
      );
      expect(
        shouldSyncOnResume(first, first.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        shouldSyncOnResume(
          first,
          first.add(const Duration(seconds: 10)),
          minimumInterval: Duration.zero,
        ),
        isTrue,
      );
    },
  );
}
