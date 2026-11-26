import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Uint8List deriveAdminPinVerifier(String pin, List<int> salt) {
  final hmac = crypto.Hmac(crypto.sha256, utf8.encode(pin));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var iteration = 1; iteration < 20000; iteration++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < result.length; index++) {
      result[index] ^= block[index];
    }
  }
  return Uint8List.fromList(result);
}

bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var mismatch = 0;
  for (var index = 0; index < left.length; index++) {
    mismatch |= left[index] ^ right[index];
  }
  return mismatch == 0;
}

Future<bool> showAdminPinDialog(
  BuildContext context,
  FlutterSecureStorage secure, {
  required bool setup,
}) async {
  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  var errorMessage = '';
  var failedAttempts = 0;
  DateTime? lockedUntil;
  final saltValue = await secure.read(key: 'barq_admin_pin_salt');
  final verifierValue = await secure.read(key: 'barq_admin_pin_verifier');
  final salt = saltValue == null ? <int>[] : base64Url.decode(saltValue);
  final expected =
      verifierValue == null ? <int>[] : base64Url.decode(verifierValue);

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(setup ? 'إنشاء رمز قفل الهاتف' : 'افتح BARQ Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              setup
                  ? 'أنشئ رمزًا من 6 إلى 12 رقمًا لهذا الهاتف فقط. سيُطلب عند فتح التطبيق والعودة إليه.'
                  : 'أدخل رمز القفل المحلي لهذا الهاتف للمتابعة.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'رمز القفل'),
            ),
            if (setup)
              TextField(
                controller: confirmController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration:
                    const InputDecoration(labelText: 'تأكيد رمز القفل'),
              ),
            if (errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final pin = pinController.text;
              if (setup) {
                final validDigits = pin.codeUnits.every(
                  (unit) => unit >= 48 && unit <= 57,
                );
                if (pin.length < 6 || pin.length > 12 || !validDigits) {
                  setDialogState(
                    () => errorMessage = 'استخدم 6 إلى 12 رقمًا',
                  );
                  return;
                }
                if (pin != confirmController.text) {
                  setDialogState(
                    () => errorMessage = 'الرمزان غير متطابقين',
                  );
                  return;
                }
                final random = Random.secure();
                final newSalt =
                    List<int>.generate(16, (_) => random.nextInt(256));
                final derived = deriveAdminPinVerifier(pin, newSalt);
                await secure.write(
                  key: 'barq_admin_pin_salt',
                  value: base64UrlEncode(newSalt),
                );
                await secure.write(
                  key: 'barq_admin_pin_verifier',
                  value: base64UrlEncode(derived),
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
                return;
              }

              final until = lockedUntil;
              if (until != null && DateTime.now().isBefore(until)) {
                final seconds =
                    until.difference(DateTime.now()).inSeconds + 1;
                setDialogState(
                  () => errorMessage =
                      'انتظر ' + seconds.toString() + ' ثانية ثم حاول',
                );
                return;
              }
              final supplied = deriveAdminPinVerifier(pin, salt);
              if (!_constantTimeBytesEqual(supplied, expected)) {
                failedAttempts++;
                if (failedAttempts >= 5) {
                  failedAttempts = 0;
                  lockedUntil =
                      DateTime.now().add(const Duration(seconds: 30));
                  setDialogState(
                    () => errorMessage = 'محاولات كثيرة؛ انتظر 30 ثانية',
                  );
                } else {
                  setDialogState(
                    () => errorMessage = 'رمز القفل غير صحيح',
                  );
                }
                return;
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(setup ? 'حفظ رمز القفل' : 'فتح التطبيق'),
          ),
        ],
      ),
    ),
  );

  pinController.dispose();
  confirmController.dispose();
  return accepted == true;
}
