import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      final raw = data['screenshots'];
      if (raw is! List) {
        throw StateError('Integration test returned no screenshot collection.');
      }
      final directory = Directory('artifacts/barq-ui-screenshots');
      await directory.create(recursive: true);
      var written = 0;
      for (final item in raw) {
        if (item is! Map) continue;
        final name = (item['screenshotName'] ?? item['name'] ?? 'screen-$written')
            .toString()
            .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
        final value = item['bytes'];
        final bytes = value is String
            ? base64Decode(value)
            : value is List
                ? value.cast<int>()
                : null;
        if (bytes == null || bytes.isEmpty) continue;
        await File('${directory.path}/$name.png').writeAsBytes(bytes, flush: true);
        written++;
      }
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
    },
  );
}
