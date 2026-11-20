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

  testWidgets('public profile page shows the selected contact details', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PublicProfilePage(
        person: {
          'id': 'friend-1',
          'display_name': 'صديق برق',
          'username': 'barq_friend',
          'phone': '+967700000001',
        },
        currentUserId: 'current-user',
      ),
    ));

    expect(find.text('الملف الشخصي'), findsOneWidget);
    expect(find.text('صديق برق'), findsOneWidget);
    expect(find.text('@barq_friend'), findsOneWidget);
    expect(find.text('+967700000001'), findsOneWidget);
    expect(find.text('إرسال رسالة'), findsOneWidget);
  });

  test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
}
