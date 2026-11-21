import 'package:material_ui/material_ui.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart';
import 'package:barq/barq_identity.dart';

void main() {
  test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    expect(barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), isNull);
    expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), isNull);
  });

  test('Nearby requests only permissions supported by the Android API level', () {
    expect(barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    expect(barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    expect(barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    expect(barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    expect(barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    expect(barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
  });

  test('Nearby payload transfer treats failure and cancellation as failed', () {
    expect(barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), isTrue);
    expect(barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), isTrue);
    expect(barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), isFalse);
    expect(barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), isFalse);
    expect(barqNearbyPayloadTransferFailed(PayloadStatus.NONE), isFalse);
  });

  test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), isTrue);
    expect(isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), isFalse);
    expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), isFalse);
    expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), isFalse);
    expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), isFalse);
    expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), isFalse);
  });

  test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    expect(isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), isTrue);
    expect(isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    expect(isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
  });

  test('international phone normalization supports Arabic digits and 00 prefix', () {
    expect(normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    expect(normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    expect(normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    expect(normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    expect(normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    expect(normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    expect(normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    expect(normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  test('registration country codes cover 206 geographic calling codes without duplicates', () {
    expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      expect(codes, contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    expect(codes, isNot(contains('+1684')));
    expect(codes, isNot(contains('+1340')));
    expect(codes, isNot(contains('+1787')));
  });

  test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    expect(
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    expect(
      normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    expect(normalizeBarqContactPhoneDigits('---'), isEmpty);
  });

  test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    expect(searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    expect(searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    expect(searchConversationMessages(messages, 'not found'), isEmpty);
    expect(searchConversationMessages(messages, '   '), isEmpty);
  });

  test('offline sync pauses only for network failures, not one rejected message', () {
    expect(barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), isTrue);
    expect(barqOfflineSyncShouldPause(Exception('Reply target not found')), isFalse);
    expect(barqOfflineSyncShouldPause(Exception('Message is too long')), isFalse);
  });

  test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), isTrue);
    expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), isFalse);
    expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), isFalse);
    expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), isFalse);
  });

  test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    expect(barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    expect(
      barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    expect(
      barqOfflineQueueWithoutExactMessage([accepted], accepted),
      isEmpty,
    );
  });

  test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    expect(barqOfflineItemsNotOnServerPage(queued, server), queued);
    expect(barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  test('offline queue capacity rejects the first item beyond the limit', () {
    expect(barqOfflineQueueIsFull(0), isFalse);
    expect(barqOfflineQueueIsFull(199), isFalse);
    expect(barqOfflineQueueIsFull(200), isTrue);
    expect(barqOfflineQueueIsFull(201), isTrue);
    expect(barqOfflineQueueIsFull(3, limit: 3), isTrue);
  });

  test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    expect(decodeBarqOfflineQueue(null), isEmpty);
    expect(decodeBarqOfflineQueue(''), isEmpty);
    expect(decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    expect(() => decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    expect(() => decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), isTrue);
    expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), isFalse);
    expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), isFalse);
    expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), isFalse);
  });

  test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    expect(barqOfflineItemsNotOnServerPage(queued, []), same(queued));
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


  test('group roles limit promotion to owners and preserve the owner account', () {
    expect(barqCanManageGroupRoles('owner', targetIsOwner: false), isTrue);
    expect(barqCanManageGroupRoles('owner', targetIsOwner: true), isFalse);
    expect(barqCanManageGroupRoles('admin', targetIsOwner: false), isFalse);
    expect(barqCanManageGroupRoles('member', targetIsOwner: false), isFalse);
  });

  test('group removal permissions prevent admins removing peers or owners', () {
    expect(
      barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    expect(
      barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    expect(
      barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    expect(
      barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      isFalse,
    );
    expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      isFalse,
    );
  });

  test('only an owner can transfer group ownership to another non-owner member', () {
    expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    expect(
      barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    expect(
      barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      isFalse,
    );
    expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      isFalse,
    );
  });

  test('group members can leave themselves but the owner cannot leave without transfer', () {
    expect(barqCanLeaveGroup(isSelf: true, isOwner: false), isTrue);
    expect(barqCanLeaveGroup(isSelf: true, isOwner: true), isFalse);
    expect(barqCanLeaveGroup(isSelf: false, isOwner: false), isFalse);
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
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    expect(sendButton.onPressed, isNotNull);
  });


  testWidgets('public profile disables messaging for the current user', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PublicProfilePage(
        person: {
          'id': 'current-user',
          'display_name': 'حسابي',
          'username': 'my_account',
        },
        currentUserId: 'current-user',
        canMessage: true,
      ),
    ));

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    expect(sendButton.onPressed, isNull);
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
  testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
    var deleted = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showMessageActions(
            context,
            message: {'id': 'message-1', 'body': 'رسالة تجريبية'},
            canDelete: true,
            onDelete: () async { deleted = true; },
          ),
          child: const Text('فتح الإجراءات'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح الإجراءات'));
    await tester.pumpAndSettle();
    expect(find.text('نسخ الرسالة'), findsOneWidget);
    expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('other users message actions do not expose delete', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showMessageActions(
            context,
            message: {'id': 'message-2', 'body': 'رسالة صديق'},
            canDelete: false,
            onDelete: () async {},
          ),
          child: const Text('فتح الإجراءات'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح الإجراءات'));
    await tester.pumpAndSettle();
    expect(find.text('نسخ الرسالة'), findsOneWidget);
    expect(find.text('حذف الرسالة'), findsNothing);
  });

  test('quoted reply preview is bounded and handles attachment references', () {
    expect(messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    expect(messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    expect(messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    expect(messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    expect(messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    expect(messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    expect(messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            saved = await showEditMessageDialog(context, 'النص القديم');
          },
          child: const Text('فتح التعديل'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح التعديل'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(saved, 'النص الجديد');
  });

  testWidgets('message action menu invokes the reply callback', (tester) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showMessageActions(
            context,
            message: {'id': 'reply-1', 'body': 'رسالة للرد'},
            canDelete: false,
            onDelete: () async {},
            onReply: (message) async { selected = message; },
          ),
          child: const Text('فتح الإجراءات'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح الإجراءات'));
    await tester.pumpAndSettle();
    expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    expect(selected?['id'], 'reply-1');
  });


  test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    expect(normalized, hasLength(2));
    expect(normalized.first['emoji'], '❤️');
    expect(normalized.last['user_id'], 'u2');
    expect(normalizeMessageReactions(null), isEmpty);
  });

  testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
    String? selectedEmoji;
    bool? removing;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: messageReactionBar(
          context: context,
          currentUserId: 'u1',
          message: {
            'reactions': [
              {'emoji': '❤️', 'user_id': 'u1'},
              {'emoji': '❤️', 'user_id': 'u2'},
            ],
          },
          onReaction: (emoji, remove) async {
            selectedEmoji = emoji;
            removing = remove;
          },
        ),
      )),
    ));

    expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    expect(selectedEmoji, '❤️');
    expect(removing, isTrue);
  });

  testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showMessageActions(
            context,
            message: {'id': 'm1', 'body': 'رسالة'},
            canDelete: false,
            onDelete: () async {},
            onReact: (emoji) async {},
            onPin: () async {},
            onSaveMemory: () async {},
          ),
          child: const Text('فتح الإجراءات'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح الإجراءات'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة تفاعل'), findsOneWidget);
    expect(find.text('تثبيت الرسالة'), findsOneWidget);
    expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  test('media duration formatter supports minute and hour lengths', () {
    expect(formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    expect(formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    expect(formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  test('message links extract only unique safe web URLs and normalize www links', () {
    final links = extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  test('message link extraction ignores non-web schemes', () {
    expect(extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => BarqConversationSummaryDialog(
              loadSummary: () async {
                requests += 1;
                return {'summary': 'ملخص اختباري', 'messageCount': 3};
              },
            ),
          ),
          child: const Text('فتح الملخص'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح الملخص'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(requests, 1);
    expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
    var selectedTool = '';
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showBarqConversationTools(context, [
            BarqConversationTool(
              icon: Icons.search,
              title: 'البحث في المحادثة',
              subtitle: 'ابحث داخل الرسائل',
              onTap: () => selectedTool = 'search',
            ),
            BarqConversationTool(
              icon: Icons.push_pin_outlined,
              title: 'الرسائل المثبتة',
              subtitle: 'عرض الرسائل المثبتة',
              onTap: () => selectedTool = 'pinned',
            ),
          ]),
          child: const Text('فتح أدوات المحادثة'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح أدوات المحادثة'));
    await tester.pumpAndSettle();
    expect(find.text('أدوات المحادثة'), findsOneWidget);
    expect(find.text('البحث في المحادثة'), findsOneWidget);
    expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    expect(selectedTool, 'pinned');
  });

  test('private and group message text share the server 5000-character limit', () {
    expect(isBarqMessageTextAllowed('رسالة قصيرة'), isTrue);
    expect(isBarqMessageTextAllowed('  رسالة قصيرة  '), isTrue);
    expect(isBarqMessageTextAllowed(''), isFalse);
    expect(isBarqMessageTextAllowed('   '), isFalse);
    expect(isBarqMessageTextAllowed(List.filled(5000, 'س').join()), isTrue);
    expect(isBarqMessageTextAllowed(List.filled(5001, 'س').join()), isFalse);
  });

  test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    expect(barqTranslationRetryAllowed('message-1', retryAfter, now: now), isFalse);
    expect(barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), isTrue);
    expect(barqTranslationRetryAllowed('message-2', retryAfter, now: now), isTrue);
    expect(barqTranslationRetryAllowed('', retryAfter, now: now), isFalse);
  });

  test('audio transcription enforces the worker two-megabyte limit', () {
    expect(isBarqTranscriptionSizeAllowed(0), isFalse);
    expect(isBarqTranscriptionSizeAllowed(1), isTrue);
    expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), isTrue);
    expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), isFalse);
  });


  test('SPARK media extensions map to exact supported MIME types', () {
    expect(barqSparkMediaContentType('jpg'), 'image/jpeg');
    expect(barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    expect(barqSparkMediaContentType('png'), 'image/png');
    expect(barqSparkMediaContentType('webp'), 'image/webp');
    expect(barqSparkMediaContentType('gif'), 'image/gif');
    expect(barqSparkMediaContentType('mp4'), 'video/mp4');
    expect(barqSparkMediaContentType('webm'), 'video/webm');
    expect(barqSparkMediaContentType('MOV'), 'video/quicktime');
    expect(barqSparkMediaContentType('exe'), isNull);
    expect(barqSparkMediaContentType(''), isNull);
  });

  test('SPARK media client size limit rejects empty and oversized files', () {
    expect(isBarqSparkMediaSizeAllowed(0), isFalse);
    expect(isBarqSparkMediaSizeAllowed(1), isTrue);
    expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), isTrue);
    expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), isFalse);
  });


  test('private memory photo uploads continue after an individual failure', () async {
    final attempted = <String>[];
    final photos = [
      {'name': 'one.jpg', 'bytes': <int>[1], 'contentType': 'image/jpeg'},
      {'name': 'two.png', 'bytes': <int>[2], 'contentType': 'image/png'},
      {'name': 'three.webp', 'bytes': <int>[3], 'contentType': 'image/webp'},
    ];

    final failures = await uploadPrivateMemoryPhotosSequentially(
      memoryId: 'memory-1',
      photos: photos,
      upload: ({
        required String memoryId,
        required List<int> bytes,
        required String fileName,
        required String contentType,
      }) async {
        attempted.add(fileName);
        if (fileName == 'two.png') throw Exception('simulated upload failure');
      },
    );

    expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    expect(failures, ['two.png']);
  });

  testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    expect(retried, isTrue);
  });

  testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: PrivateMemoryPhotoGallery(media: []),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.textContaining('/'), findsNothing);
  });

  testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
    final photos = [
      {'attachmentId': 'owner-1/private-memories/photo-1'},
      {'attachmentId': 'owner-1/private-memories/photo-2'},
      {'attachmentId': 'owner-1/private-memories/photo-3'},
    ];
    var visiblePage = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: PrivateMemoryPhotoGallery(
              media: photos,
              onPageChanged: (page) => visiblePage = page,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
    expect(visiblePage, 0);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(visiblePage, 1);
    expect(find.text('2 / 3'), findsOneWidget);
  });


  test('BARQ has exactly the four approved visual identities', () {
    expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  test('BARQ identity palettes keep four distinct readable theme foundations', () {
    double contrastRatio(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      final lighter = a > b ? a : b;
      final darker = a > b ? b : a;
      return (lighter + 0.05) / (darker + 0.05);
    }

    final palettes = BarqIdentity.values
        .map(BarqIdentityPalette.forIdentity)
        .toList();
    expect(BarqIdentity.values, hasLength(4));
    expect(palettes.map((p) => p.background).toSet().length, 4);
    expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      expect(palette.text, isNot(palette.background));
      expect(palette.primary, isNot(palette.background));
      expect(palette.secondary, isNot(palette.surface));
      expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    expect(blue.primary, const Color(0xFFD6AD55));
    expect(blue.secondary, const Color(0xFF168BFF));
    expect(blue.background, const Color(0xFF090909));
    expect(blue.surface, const Color(0xFF171717));
  });

  test('FCM token normalization trims valid tokens and rejects invalid values', () {
    expect(normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    expect(normalizeBarqFcmToken(null), isNull);
    expect(normalizeBarqFcmToken(''), isNull);
    expect(normalizeBarqFcmToken('   '), isNull);
    expect(normalizeBarqFcmToken('token with spaces'), isNull);
    expect(normalizeBarqFcmToken(List.filled(4097, 'x').join()), isNull);
    expect(normalizeBarqFcmToken(List.filled(4096, 'x').join()), hasLength(4096));
  });

  test('FCM registration requires authorized or provisional notification permission', () {
    expect(barqCanRegisterFcmToken(AuthorizationStatus.authorized), isTrue);
    expect(barqCanRegisterFcmToken(AuthorizationStatus.provisional), isTrue);
    expect(barqCanRegisterFcmToken(AuthorizationStatus.denied), isFalse);
    expect(barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), isFalse);
  });

}
