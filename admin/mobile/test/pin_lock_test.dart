import 'package:flutter_test/flutter_test.dart';
import 'package:barq_admin/pin_lock.dart' show deriveAdminPinVerifier;

void main() {
  test('PIN verifier is deterministic for the same PIN and salt', () {
    final salt = List<int>.generate(16, (index) => index);
    final first = deriveAdminPinVerifier('123456', salt);
    final second = deriveAdminPinVerifier('123456', salt);
    expect(first, hasLength(32));
    expect(first, equals(second));
  });

  test('different PINs or salts produce different verifiers', () {
    final salt = List<int>.generate(16, (index) => index);
    final otherSalt = List<int>.generate(16, (index) => index + 1);
    final original = deriveAdminPinVerifier('123456', salt);
    expect(deriveAdminPinVerifier('654321', salt), isNot(equals(original)));
    expect(deriveAdminPinVerifier('123456', otherSalt), isNot(equals(original)));
  });
}
