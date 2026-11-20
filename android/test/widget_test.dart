import 'package:flutter_test/flutter_test.dart';
import 'package:barq/main.dart';

void main() {
  test('message merge deduplicates by id and keeps chronological order', () {
    final merged = mergeMessages(
      [
        {'id': 'm2', 'created_at': '2026-11-19 10:02:00', 'body': 'second'},
        {'id': 'm1', 'created_at': '2026-11-19 10:01:00', 'body': 'first'},
      ],
      [
        {'id': 'm2', 'created_at': '2026-11-19 10:02:00', 'body': 'second updated'},
        {'id': 'm3', 'created_at': '2026-11-19 10:03:00', 'body': 'third'},
      ],
    );

    expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    expect(merged[1]['body'], 'second updated');
  });

  test('field helper supports API snake_case and camelCase fields', () {
    expect(field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    expect(field({}, ['username'], 'مستخدم'), 'مستخدم');
  });
}
