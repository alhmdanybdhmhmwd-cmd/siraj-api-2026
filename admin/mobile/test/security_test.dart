import 'package:flutter_test/flutter_test.dart';
import 'package:barq_admin/security.dart';

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
    expect(isValidAdminApiBase('https://admin.example.com?token=secret'), isFalse);
    expect(isValidAdminApiBase('https://admin.example.com#fragment'), isFalse);
    expect(isValidAdminApiBase(''), isFalse);
  });
}
