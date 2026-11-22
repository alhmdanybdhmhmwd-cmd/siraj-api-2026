import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart';
import 'package:barq/barq_identity.dart';

void main() {
  flutter_test.test('optional realtime connects only with a session, endpoint and resumed app', () {
    flutter_test.expect(barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), isTrue);
    flutter_test.expect(barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), isFalse);
    flutter_test.expect(barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), isFalse);
    flutter_test.expect(barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), isFalse);
    flutter_test.expect(barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), isFalse);
  });

  flutter_test.test('realtime events refresh only the matching direct conversation', () {
    flutter_test.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      isTrue,
    );
    flutter_test.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      isTrue,
    );
    flutter_test.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      isFalse,
    );
    flutter_test.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      isFalse,
    );
    flutter_test.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      isFalse,
    );
  });

  flutter_test.test('notification tap routing validates private chat, group and SPARK destinations', () {
    flutter_test.expect(
      barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    flutter_test.expect(
      barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    flutter_test.expect(
      barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    flutter_test.expect(
      barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    flutter_test.expect(barqNotificationRouteFromData({'type': 'direct_message'}), isNull);
    flutter_test.expect(barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), isNull);
    flutter_test.expect(barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), isNull);
  });

  flutter_test.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), isNull);
    flutter_test.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), isNull);
  });

  flutter_test.test('Nearby requests only permissions supported by the Android API level', () {
    flutter_test.expect(barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    flutter_test.expect(barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    flutter_test.expect(barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    flutter_test.expect(barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    flutter_test.expect(barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    flutter_test.expect(barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
  });

  flutter_test.test('Nearby payload transfer treats failure and cancellation as failed', () {
    flutter_test.expect(barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), isTrue);
    flutter_test.expect(barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), isTrue);
    flutter_test.expect(barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), isFalse);
    flutter_test.expect(barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), isFalse);
    flutter_test.expect(barqNearbyPayloadTransferFailed(PayloadStatus.NONE), isFalse);
  });

  flutter_test.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    flutter_test.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), isTrue);
    flutter_test.expect(isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), isFalse);
    flutter_test.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), isFalse);
    flutter_test.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), isFalse);
    flutter_test.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), isFalse);
    flutter_test.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), isFalse);
  });

  flutter_test.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    flutter_test.expect(isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), isTrue);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
    flutter_test.expect(isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), isFalse);
  });

  flutter_test.test('registration sends a stable private username without exposing the phone', () {
    final first = barqPrivateRegistrationUsername('+967770000000');
    final second = barqPrivateRegistrationUsername('+967770000000');
    flutter_test.expect(first, second);
    flutter_test.expect(first, matches(RegExp(r'^barq[a-f0-9]{16}$')));
    flutter_test.expect(normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    flutter_test.expect(normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    flutter_test.expect(normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    flutter_test.expect(normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  flutter_test.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    flutter_test.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    flutter_test.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      flutter_test.expect(codes, contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    flutter_test.expect(codes, isNot(contains('+1684')));
    flutter_test.expect(codes, isNot(contains('+1340')));
    flutter_test.expect(codes, isNot(contains('+1787')));
  });

  flutter_test.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    flutter_test.expect(
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    flutter_test.expect(
      normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    flutter_test.expect(normalizeBarqContactPhoneDigits('---'), isEmpty);
  });

  flutter_test.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    flutter_test.expect(searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    flutter_test.expect(searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    flutter_test.expect(searchConversationMessages(messages, 'not found'), isEmpty);
    flutter_test.expect(searchConversationMessages(messages, '   '), isEmpty);
  });

  flutter_test.test('offline sync pauses only for network failures, not one rejected message', () {
    flutter_test.expect(barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), isTrue);
    flutter_test.expect(barqOfflineSyncShouldPause(Exception('Reply target not found')), isFalse);
    flutter_test.expect(barqOfflineSyncShouldPause(Exception('Message is too long')), isFalse);
  });

  flutter_test.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), isTrue);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), isFalse);
  });

  flutter_test.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  flutter_test.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    flutter_test.expect(
      barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    flutter_test.expect(
      barqOfflineQueueWithoutExactMessage([accepted], accepted),
      isEmpty,
    );
  });

  flutter_test.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, server), queued);
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  flutter_test.test('offline queue capacity rejects the first item beyond the limit', () {
    flutter_test.expect(barqOfflineQueueIsFull(0), isFalse);
    flutter_test.expect(barqOfflineQueueIsFull(199), isFalse);
    flutter_test.expect(barqOfflineQueueIsFull(200), isTrue);
    flutter_test.expect(barqOfflineQueueIsFull(201), isTrue);
    flutter_test.expect(barqOfflineQueueIsFull(3, limit: 3), isTrue);
  });

  flutter_test.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    flutter_test.expect(decodeBarqOfflineQueue(null), isEmpty);
    flutter_test.expect(decodeBarqOfflineQueue(''), isEmpty);
    flutter_test.expect(decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    flutter_test.expect(() => decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    flutter_test.expect(() => decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    flutter_test.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    flutter_test.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  flutter_test.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), isTrue);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), isFalse);
  });

  flutter_test.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    flutter_test.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  flutter_test.test('message merge deduplicates by id and keeps chronological order', () {
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

    flutter_test.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    flutter_test.expect(merged[1]['body'], 'second updated');
  });

  flutter_test.test('field helper supports API snake_case and camelCase fields', () {
    flutter_test.expect(field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    flutter_test.expect(field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  flutter_test.test('profile photo path is resolved for group payloads with snake_case fields', () {
    flutter_test.expect(
      profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    flutter_test.expect(profilePhotoPath({'id': 'without-photo'}), isEmpty);
    flutter_test.expect(
      profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  flutter_test.test('group roles limit promotion to owners and preserve the owner account', () {
    flutter_test.expect(barqCanManageGroupRoles('owner', targetIsOwner: false), isTrue);
    flutter_test.expect(barqCanManageGroupRoles('owner', targetIsOwner: true), isFalse);
    flutter_test.expect(barqCanManageGroupRoles('admin', targetIsOwner: false), isFalse);
    flutter_test.expect(barqCanManageGroupRoles('member', targetIsOwner: false), isFalse);
  });

  flutter_test.test('group removal permissions prevent admins removing peers or owners', () {
    flutter_test.expect(
      barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      isFalse,
    );
  });

  flutter_test.test('only an owner can transfer group ownership to another non-owner member', () {
    flutter_test.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      isFalse,
    );
  });

  flutter_test.test('group members can leave themselves but the owner cannot leave without transfer', () {
    flutter_test.expect(barqCanLeaveGroup(isSelf: true, isOwner: false), isTrue);
    flutter_test.expect(barqCanLeaveGroup(isSelf: true, isOwner: true), isFalse);
    flutter_test.expect(barqCanLeaveGroup(isSelf: false, isOwner: false), isFalse);
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

    flutter_test.expect(find.text('الملف الشخصي'), findsOneWidget);
    flutter_test.expect(find.text('صديق برق'), findsOneWidget);
    flutter_test.expect(find.text('@barq_friend'), findsNWidgets(2));
    flutter_test.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    flutter_test.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    flutter_test.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    flutter_test.expect(sendButton.onPressed, isNotNull);
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
    flutter_test.expect(sendButton.onPressed, isNull);
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

    flutter_test.expect(find.text('عضو المجموعة'), findsOneWidget);
    flutter_test.expect(find.text('@group_member'), findsNWidgets(2));
    flutter_test.expect(find.text('إرسال رسالة'), findsNothing);
  });

  flutter_test.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    flutter_test.expect(visible.map((message) => message['id']).toList(),
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
    flutter_test.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutter_test.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    flutter_test.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    flutter_test.expect(deleted, isTrue);
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
    flutter_test.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutter_test.expect(find.text('حذف الرسالة'), findsNothing);
  });

  flutter_test.test('quoted reply preview is bounded and handles attachment references', () {
    flutter_test.expect(messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    flutter_test.expect(messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    flutter_test.expect(messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': ''}), 'رسالة');
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
    flutter_test.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    flutter_test.expect(saved, 'النص الجديد');
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
    flutter_test.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    flutter_test.expect(selected?['id'], 'reply-1');
  });


  flutter_test.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    flutter_test.expect(normalized, hasLength(2));
    flutter_test.expect(normalized.first['emoji'], '❤️');
    flutter_test.expect(normalized.last['user_id'], 'u2');
    flutter_test.expect(normalizeMessageReactions(null), isEmpty);
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

    flutter_test.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    flutter_test.expect(selectedEmoji, '❤️');
    flutter_test.expect(removing, isTrue);
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
    flutter_test.expect(find.text('إضافة تفاعل'), findsOneWidget);
    flutter_test.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    flutter_test.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  flutter_test.test('media duration formatter supports minute and hour lengths', () {
    flutter_test.expect(formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    flutter_test.expect(formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    flutter_test.expect(formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  flutter_test.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    flutter_test.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  flutter_test.test('message link extraction ignores non-web schemes', () {
    flutter_test.expect(extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
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
    flutter_test.expect(requests, 0);
    flutter_test.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    flutter_test.expect(requests, 1);
    flutter_test.expect(find.text('ملخص اختباري'), findsOneWidget);
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
    flutter_test.expect(find.text('أدوات المحادثة'), findsOneWidget);
    flutter_test.expect(find.text('البحث في المحادثة'), findsOneWidget);
    flutter_test.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    flutter_test.expect(selectedTool, 'pinned');
  });

  flutter_test.test('private and group message text share the server 5000-character limit', () {
    flutter_test.expect(isBarqMessageTextAllowed('رسالة قصيرة'), isTrue);
    flutter_test.expect(isBarqMessageTextAllowed('  رسالة قصيرة  '), isTrue);
    flutter_test.expect(isBarqMessageTextAllowed(''), isFalse);
    flutter_test.expect(isBarqMessageTextAllowed('   '), isFalse);
    flutter_test.expect(isBarqMessageTextAllowed(List.filled(5000, 'س').join()), isTrue);
    flutter_test.expect(isBarqMessageTextAllowed(List.filled(5001, 'س').join()), isFalse);
  });

  flutter_test.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    flutter_test.expect(barqTranslationRetryAllowed('message-1', retryAfter, now: now), isFalse);
    flutter_test.expect(barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), isTrue);
    flutter_test.expect(barqTranslationRetryAllowed('message-2', retryAfter, now: now), isTrue);
    flutter_test.expect(barqTranslationRetryAllowed('', retryAfter, now: now), isFalse);
  });

  flutter_test.test('audio transcription enforces the worker two-megabyte limit', () {
    flutter_test.expect(isBarqTranscriptionSizeAllowed(0), isFalse);
    flutter_test.expect(isBarqTranscriptionSizeAllowed(1), isTrue);
    flutter_test.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), isTrue);
    flutter_test.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), isFalse);
  });


  flutter_test.test('SPARK media extensions map to exact supported MIME types', () {
    flutter_test.expect(barqSparkMediaContentType('jpg'), 'image/jpeg');
    flutter_test.expect(barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    flutter_test.expect(barqSparkMediaContentType('png'), 'image/png');
    flutter_test.expect(barqSparkMediaContentType('webp'), 'image/webp');
    flutter_test.expect(barqSparkMediaContentType('gif'), 'image/gif');
    flutter_test.expect(barqSparkMediaContentType('mp4'), 'video/mp4');
    flutter_test.expect(barqSparkMediaContentType('webm'), 'video/webm');
    flutter_test.expect(barqSparkMediaContentType('MOV'), 'video/quicktime');
    flutter_test.expect(barqSparkMediaContentType('exe'), isNull);
    flutter_test.expect(barqSparkMediaContentType(''), isNull);
  });

  flutter_test.test('SPARK media client size limit rejects empty and oversized files', () {
    flutter_test.expect(isBarqSparkMediaSizeAllowed(0), isFalse);
    flutter_test.expect(isBarqSparkMediaSizeAllowed(1), isTrue);
    flutter_test.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), isTrue);
    flutter_test.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), isFalse);
  });


  flutter_test.test('private memory photo uploads continue after an individual failure', () async {
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

    flutter_test.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    flutter_test.expect(failures, ['two.png']);
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

    flutter_test.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    flutter_test.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    flutter_test.expect(retried, isTrue);
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

    flutter_test.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    flutter_test.expect(find.byType(PageView), findsNothing);
    flutter_test.expect(find.textContaining('/'), findsNothing);
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

    flutter_test.expect(find.byType(PageView), findsOneWidget);
    flutter_test.expect(find.byType(InteractiveViewer), findsWidgets);
    flutter_test.expect(visiblePage, 0);
    flutter_test.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    flutter_test.expect(visiblePage, 1);
    flutter_test.expect(find.text('2 / 3'), findsOneWidget);
  });


  flutter_test.test('BARQ has exactly the four approved visual identities', () {
    flutter_test.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    flutter_test.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    flutter_test.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    flutter_test.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    flutter_test.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  flutter_test.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    flutter_test.expect(BarqIdentity.values, hasLength(4));
    flutter_test.expect(palettes.map((p) => p.background).toSet().length, 4);
    flutter_test.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      flutter_test.expect(palette.text, isNot(palette.background));
      flutter_test.expect(palette.primary, isNot(palette.background));
      flutter_test.expect(palette.secondary, isNot(palette.surface));
      flutter_test.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      flutter_test.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      flutter_test.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      flutter_test.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    flutter_test.expect(blue.primary, const Color(0xFFD6AD55));
    flutter_test.expect(blue.secondary, const Color(0xFF168BFF));
    flutter_test.expect(blue.background, const Color(0xFF090909));
    flutter_test.expect(blue.surface, const Color(0xFF171717));
  });

  flutter_test.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    flutter_test.expect(normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    flutter_test.expect(normalizeBarqFcmToken(null), isNull);
    flutter_test.expect(normalizeBarqFcmToken(''), isNull);
    flutter_test.expect(normalizeBarqFcmToken('   '), isNull);
    flutter_test.expect(normalizeBarqFcmToken('token with spaces'), isNull);
    flutter_test.expect(normalizeBarqFcmToken(List.filled(4097, 'x').join()), isNull);
    flutter_test.expect(normalizeBarqFcmToken(List.filled(4096, 'x').join()), hasLength(4096));
  });

  flutter_test.test('foreground push uses generic labels and respects category preferences', () {
    flutter_test.expect(
      barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    flutter_test.expect(
      barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    flutter_test.expect(
      barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    flutter_test.expect(barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'unknown'}, {}), isNull);
  });

  flutter_test.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    flutter_test.expect(success, isTrue);
    flutter_test.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    flutter_test.expect(noSession, isFalse);
    flutter_test.expect(revoked, isNull);

    final invalidToken = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    flutter_test.expect(invalidToken, isFalse);
    flutter_test.expect(revoked, isNull);

    final networkFailure = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    flutter_test.expect(networkFailure, isFalse);
  });

  flutter_test.test('FCM registration requires authorized or provisional notification permission', () {
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.authorized), isTrue);
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.provisional), isTrue);
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.denied), isFalse);
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), isFalse);
  });

}
)));
    flutter_test.expect(first, isNot(contains('967770000000')));
    flutter_test.expect(barqPrivateRegistrationUsername('+447911123456'), isNot(first));
  });

  flutter_test.test('international phone normalization supports Arabic digits and 00 prefix', () {
    flutter_test.expect(normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    flutter_test.expect(normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    flutter_test.expect(normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    flutter_test.expect(normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    flutter_test.expect(normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  flutter_test.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    flutter_test.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    flutter_test.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      flutter_test.expect(codes, contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    flutter_test.expect(codes, isNot(contains('+1684')));
    flutter_test.expect(codes, isNot(contains('+1340')));
    flutter_test.expect(codes, isNot(contains('+1787')));
  });

  flutter_test.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    flutter_test.expect(
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    flutter_test.expect(
      normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    flutter_test.expect(normalizeBarqContactPhoneDigits('---'), isEmpty);
  });

  flutter_test.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    flutter_test.expect(searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    flutter_test.expect(searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    flutter_test.expect(searchConversationMessages(messages, 'not found'), isEmpty);
    flutter_test.expect(searchConversationMessages(messages, '   '), isEmpty);
  });

  flutter_test.test('offline sync pauses only for network failures, not one rejected message', () {
    flutter_test.expect(barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), isTrue);
    flutter_test.expect(barqOfflineSyncShouldPause(Exception('Reply target not found')), isFalse);
    flutter_test.expect(barqOfflineSyncShouldPause(Exception('Message is too long')), isFalse);
  });

  flutter_test.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), isTrue);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), isFalse);
  });

  flutter_test.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  flutter_test.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    flutter_test.expect(
      barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    flutter_test.expect(
      barqOfflineQueueWithoutExactMessage([accepted], accepted),
      isEmpty,
    );
  });

  flutter_test.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, server), queued);
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  flutter_test.test('offline queue capacity rejects the first item beyond the limit', () {
    flutter_test.expect(barqOfflineQueueIsFull(0), isFalse);
    flutter_test.expect(barqOfflineQueueIsFull(199), isFalse);
    flutter_test.expect(barqOfflineQueueIsFull(200), isTrue);
    flutter_test.expect(barqOfflineQueueIsFull(201), isTrue);
    flutter_test.expect(barqOfflineQueueIsFull(3, limit: 3), isTrue);
  });

  flutter_test.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    flutter_test.expect(decodeBarqOfflineQueue(null), isEmpty);
    flutter_test.expect(decodeBarqOfflineQueue(''), isEmpty);
    flutter_test.expect(decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    flutter_test.expect(() => decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    flutter_test.expect(() => decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    flutter_test.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    flutter_test.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  flutter_test.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), isTrue);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), isFalse);
    flutter_test.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), isFalse);
  });

  flutter_test.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    flutter_test.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    flutter_test.expect(barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  flutter_test.test('message merge deduplicates by id and keeps chronological order', () {
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

    flutter_test.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    flutter_test.expect(merged[1]['body'], 'second updated');
  });

  flutter_test.test('field helper supports API snake_case and camelCase fields', () {
    flutter_test.expect(field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    flutter_test.expect(field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  flutter_test.test('profile photo path is resolved for group payloads with snake_case fields', () {
    flutter_test.expect(
      profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    flutter_test.expect(profilePhotoPath({'id': 'without-photo'}), isEmpty);
    flutter_test.expect(
      profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  flutter_test.test('group roles limit promotion to owners and preserve the owner account', () {
    flutter_test.expect(barqCanManageGroupRoles('owner', targetIsOwner: false), isTrue);
    flutter_test.expect(barqCanManageGroupRoles('owner', targetIsOwner: true), isFalse);
    flutter_test.expect(barqCanManageGroupRoles('admin', targetIsOwner: false), isFalse);
    flutter_test.expect(barqCanManageGroupRoles('member', targetIsOwner: false), isFalse);
  });

  flutter_test.test('group removal permissions prevent admins removing peers or owners', () {
    flutter_test.expect(
      barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      isFalse,
    );
  });

  flutter_test.test('only an owner can transfer group ownership to another non-owner member', () {
    flutter_test.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      isTrue,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      isFalse,
    );
    flutter_test.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      isFalse,
    );
  });

  flutter_test.test('group members can leave themselves but the owner cannot leave without transfer', () {
    flutter_test.expect(barqCanLeaveGroup(isSelf: true, isOwner: false), isTrue);
    flutter_test.expect(barqCanLeaveGroup(isSelf: true, isOwner: true), isFalse);
    flutter_test.expect(barqCanLeaveGroup(isSelf: false, isOwner: false), isFalse);
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

    flutter_test.expect(find.text('الملف الشخصي'), findsOneWidget);
    flutter_test.expect(find.text('صديق برق'), findsOneWidget);
    flutter_test.expect(find.text('@barq_friend'), findsNWidgets(2));
    flutter_test.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    flutter_test.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    flutter_test.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    flutter_test.expect(sendButton.onPressed, isNotNull);
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
    flutter_test.expect(sendButton.onPressed, isNull);
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

    flutter_test.expect(find.text('عضو المجموعة'), findsOneWidget);
    flutter_test.expect(find.text('@group_member'), findsNWidgets(2));
    flutter_test.expect(find.text('إرسال رسالة'), findsNothing);
  });

  flutter_test.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    flutter_test.expect(visible.map((message) => message['id']).toList(),
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
    flutter_test.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutter_test.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    flutter_test.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    flutter_test.expect(deleted, isTrue);
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
    flutter_test.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutter_test.expect(find.text('حذف الرسالة'), findsNothing);
  });

  flutter_test.test('quoted reply preview is bounded and handles attachment references', () {
    flutter_test.expect(messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    flutter_test.expect(messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    flutter_test.expect(messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    flutter_test.expect(messageReplyPreview({'reply_to_body': ''}), 'رسالة');
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
    flutter_test.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    flutter_test.expect(saved, 'النص الجديد');
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
    flutter_test.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    flutter_test.expect(selected?['id'], 'reply-1');
  });


  flutter_test.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    flutter_test.expect(normalized, hasLength(2));
    flutter_test.expect(normalized.first['emoji'], '❤️');
    flutter_test.expect(normalized.last['user_id'], 'u2');
    flutter_test.expect(normalizeMessageReactions(null), isEmpty);
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

    flutter_test.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    flutter_test.expect(selectedEmoji, '❤️');
    flutter_test.expect(removing, isTrue);
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
    flutter_test.expect(find.text('إضافة تفاعل'), findsOneWidget);
    flutter_test.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    flutter_test.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  flutter_test.test('media duration formatter supports minute and hour lengths', () {
    flutter_test.expect(formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    flutter_test.expect(formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    flutter_test.expect(formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  flutter_test.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    flutter_test.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  flutter_test.test('message link extraction ignores non-web schemes', () {
    flutter_test.expect(extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
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
    flutter_test.expect(requests, 0);
    flutter_test.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    flutter_test.expect(requests, 1);
    flutter_test.expect(find.text('ملخص اختباري'), findsOneWidget);
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
    flutter_test.expect(find.text('أدوات المحادثة'), findsOneWidget);
    flutter_test.expect(find.text('البحث في المحادثة'), findsOneWidget);
    flutter_test.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    flutter_test.expect(selectedTool, 'pinned');
  });

  flutter_test.test('private and group message text share the server 5000-character limit', () {
    flutter_test.expect(isBarqMessageTextAllowed('رسالة قصيرة'), isTrue);
    flutter_test.expect(isBarqMessageTextAllowed('  رسالة قصيرة  '), isTrue);
    flutter_test.expect(isBarqMessageTextAllowed(''), isFalse);
    flutter_test.expect(isBarqMessageTextAllowed('   '), isFalse);
    flutter_test.expect(isBarqMessageTextAllowed(List.filled(5000, 'س').join()), isTrue);
    flutter_test.expect(isBarqMessageTextAllowed(List.filled(5001, 'س').join()), isFalse);
  });

  flutter_test.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    flutter_test.expect(barqTranslationRetryAllowed('message-1', retryAfter, now: now), isFalse);
    flutter_test.expect(barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), isTrue);
    flutter_test.expect(barqTranslationRetryAllowed('message-2', retryAfter, now: now), isTrue);
    flutter_test.expect(barqTranslationRetryAllowed('', retryAfter, now: now), isFalse);
  });

  flutter_test.test('audio transcription enforces the worker two-megabyte limit', () {
    flutter_test.expect(isBarqTranscriptionSizeAllowed(0), isFalse);
    flutter_test.expect(isBarqTranscriptionSizeAllowed(1), isTrue);
    flutter_test.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), isTrue);
    flutter_test.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), isFalse);
  });


  flutter_test.test('SPARK media extensions map to exact supported MIME types', () {
    flutter_test.expect(barqSparkMediaContentType('jpg'), 'image/jpeg');
    flutter_test.expect(barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    flutter_test.expect(barqSparkMediaContentType('png'), 'image/png');
    flutter_test.expect(barqSparkMediaContentType('webp'), 'image/webp');
    flutter_test.expect(barqSparkMediaContentType('gif'), 'image/gif');
    flutter_test.expect(barqSparkMediaContentType('mp4'), 'video/mp4');
    flutter_test.expect(barqSparkMediaContentType('webm'), 'video/webm');
    flutter_test.expect(barqSparkMediaContentType('MOV'), 'video/quicktime');
    flutter_test.expect(barqSparkMediaContentType('exe'), isNull);
    flutter_test.expect(barqSparkMediaContentType(''), isNull);
  });

  flutter_test.test('SPARK media client size limit rejects empty and oversized files', () {
    flutter_test.expect(isBarqSparkMediaSizeAllowed(0), isFalse);
    flutter_test.expect(isBarqSparkMediaSizeAllowed(1), isTrue);
    flutter_test.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), isTrue);
    flutter_test.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), isFalse);
  });


  flutter_test.test('private memory photo uploads continue after an individual failure', () async {
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

    flutter_test.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    flutter_test.expect(failures, ['two.png']);
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

    flutter_test.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    flutter_test.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    flutter_test.expect(retried, isTrue);
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

    flutter_test.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    flutter_test.expect(find.byType(PageView), findsNothing);
    flutter_test.expect(find.textContaining('/'), findsNothing);
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

    flutter_test.expect(find.byType(PageView), findsOneWidget);
    flutter_test.expect(find.byType(InteractiveViewer), findsWidgets);
    flutter_test.expect(visiblePage, 0);
    flutter_test.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    flutter_test.expect(visiblePage, 1);
    flutter_test.expect(find.text('2 / 3'), findsOneWidget);
  });


  flutter_test.test('BARQ has exactly the four approved visual identities', () {
    flutter_test.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    flutter_test.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    flutter_test.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    flutter_test.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    flutter_test.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  flutter_test.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    flutter_test.expect(BarqIdentity.values, hasLength(4));
    flutter_test.expect(palettes.map((p) => p.background).toSet().length, 4);
    flutter_test.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      flutter_test.expect(palette.text, isNot(palette.background));
      flutter_test.expect(palette.primary, isNot(palette.background));
      flutter_test.expect(palette.secondary, isNot(palette.surface));
      flutter_test.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      flutter_test.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      flutter_test.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      flutter_test.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    flutter_test.expect(blue.primary, const Color(0xFFD6AD55));
    flutter_test.expect(blue.secondary, const Color(0xFF168BFF));
    flutter_test.expect(blue.background, const Color(0xFF090909));
    flutter_test.expect(blue.surface, const Color(0xFF171717));
  });

  flutter_test.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    flutter_test.expect(normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    flutter_test.expect(normalizeBarqFcmToken(null), isNull);
    flutter_test.expect(normalizeBarqFcmToken(''), isNull);
    flutter_test.expect(normalizeBarqFcmToken('   '), isNull);
    flutter_test.expect(normalizeBarqFcmToken('token with spaces'), isNull);
    flutter_test.expect(normalizeBarqFcmToken(List.filled(4097, 'x').join()), isNull);
    flutter_test.expect(normalizeBarqFcmToken(List.filled(4096, 'x').join()), hasLength(4096));
  });

  flutter_test.test('foreground push uses generic labels and respects category preferences', () {
    flutter_test.expect(
      barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    flutter_test.expect(
      barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    flutter_test.expect(
      barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    flutter_test.expect(barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), isNull);
    flutter_test.expect(barqForegroundPushLabel({'type': 'unknown'}, {}), isNull);
  });

  flutter_test.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    flutter_test.expect(success, isTrue);
    flutter_test.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    flutter_test.expect(noSession, isFalse);
    flutter_test.expect(revoked, isNull);

    final invalidToken = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    flutter_test.expect(invalidToken, isFalse);
    flutter_test.expect(revoked, isNull);

    final networkFailure = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    flutter_test.expect(networkFailure, isFalse);
  });

  flutter_test.test('FCM registration requires authorized or provisional notification permission', () {
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.authorized), isTrue);
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.provisional), isTrue);
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.denied), isFalse);
    flutter_test.expect(barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), isFalse);
  });

}
