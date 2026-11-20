import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barq/main.dart';

void main() {
  test('international phone normalization supports Arabic digits and 00 prefix', () {
    expect(normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    expect(normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    expect(normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    expect(normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    expect(normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
  });

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

  test('profile photo path is resolved for group payloads with snake_case fields', () {
    expect(
      profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    expect(profilePhotoPath({'id': 'without-photo'}), isEmpty);
    expect(
      profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });

  testWidgets('public profile page shows the selected contact details', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PublicProfilePage(
        person: {
          'id': 'friend-1',
          'display_name': 'صديق برق',
          'username': 'barq_friend',
          'phone': '+967700000001',
        },
        currentUserId: 'current-user',
        canMessage: true,
      ),
    ));

    expect(find.text('الملف الشخصي'), findsOneWidget);
    expect(find.text('صديق برق'), findsOneWidget);
    expect(find.text('@barq_friend'), findsNWidgets(2));
    expect(find.text('+967700000001'), findsOneWidget);
    expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    expect(find.text('إرسال رسالة'), findsOneWidget);
  });

  testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PublicProfilePage(
        person: {
          'user': {
            'id': 'friend-2',
            'display_name': 'عضو المجموعة',
            'username': 'group_member',
          },
        },
        currentUserId: 'current-user',
      ),
    ));

    expect(find.text('عضو المجموعة'), findsOneWidget);
    expect(find.text('@group_member'), findsNWidgets(2));
    expect(find.text('إرسال رسالة'), findsNothing);
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
