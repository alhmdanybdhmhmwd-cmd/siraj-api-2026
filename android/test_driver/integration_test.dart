import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('artifacts/barq-ui-screenshots');
  await directory.create(recursive: true);
  var written = 0;

  await integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes,
        [Map<String, Object?>? args]) async {
      final safeName = screenshotName
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
      if (screenshotBytes.isEmpty) return false;
      await File('${directory.path}/$safeName.png')
          .writeAsBytes(screenshotBytes, flush: true);
      written++;
      return true;
    },
  );

  if (written < 8) {
    throw StateError('Expected at least 8 screenshots, received $written.');
  }
  await File('${directory.path}/README.txt').writeAsString(
    'BARQ actual Flutter UI screenshots.\n'
    'Captured in an Android emulator from the app widgets on branch '
    '${Platform.environment['GITHUB_REF_NAME'] ?? 'unknown'}.\n'
    'Demo fixtures are synthetic and do not contain real account data.\n'
    'Some pages require further navigation coverage; this pack is not a claim '
    'that every interactive subpage has been captured.\n',
  );
}
