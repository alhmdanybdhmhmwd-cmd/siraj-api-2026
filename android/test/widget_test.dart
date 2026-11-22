import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart' as barqApp;

void main() {
  ft.test('optional realtime connects only with a session, endpoint and resumed app', () {
    ft.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), ft.isTrue);
    ft.expect(barqApp.barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), ft.isFalse);
    ft.expect(barqApp.barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), ft.isFalse);
    ft.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), ft.isFalse);
    ft.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), ft.isFalse);
  });

  ft.test('realtime events refresh only the matching direct conversation', () {
    ft.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      ft.isFalse,
    );
  });

  ft.test('notification tap routing validates private chat, group and SPARK destinations', () {
    ft.expect(
      barqApp.barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    ft.expect(
      barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    ft.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    ft.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    ft.expect(barqApp.barqNotificationRouteFromData({'type': 'direct_message'}), ft.isNull);
    ft.expect(barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), ft.isNull);
    ft.expect(barqApp.barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), ft.isNull);
  });

  ft.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), ft.isNull);
    ft.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), ft.isNull);
  });

  ft.test('Nearby requests only permissions supported by the Android API level', () {
    ft.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    ft.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    ft.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    ft.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    ft.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    ft.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    ft.expect(barqApp.barqNearbyRequiresLocationService(30), ft.isTrue);
    ft.expect(barqApp.barqNearbyRequiresLocationService(32), ft.isTrue);
    ft.expect(barqApp.barqNearbyRequiresLocationService(33), ft.isFalse);
    ft.expect(barqApp.barqNearbyRequiresLocationService(37), ft.isFalse);
  });

  ft.test('Nearby payload transfer treats failure and cancellation as failed', () {
    ft.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), ft.isTrue);
    ft.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), ft.isTrue);
    ft.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), ft.isFalse);
    ft.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), ft.isFalse);
    ft.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.NONE), ft.isFalse);
  });

  ft.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    ft.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), ft.isTrue);
    ft.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), ft.isFalse);
  });

  ft.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    ft.expect(barqApp.isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), ft.isTrue);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
    ft.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), ft.isFalse);
  });

  ft.test('registration sends a stable private username without exposing the phone', () {
    final first = barqApp.barqPrivateRegistrationUsername('+967770000000');
    final second = barqApp.barqPrivateRegistrationUsername('+967770000000');
    ft.expect(first, second);
    ft.expect(first, ft.matches(RegExp(r'^barq[a-f0-9]{16}$')));
    ft.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    ft.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    ft.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    ft.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  ft.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    ft.expect(barqApp.barqCountryCodes.length, 206);
    final codes = barqApp.barqCountryCodes.map((country) => country.$2).toSet();
    ft.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      ft.expect(codes, ft.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    ft.expect(codes, ft.isNot(ft.contains('+1684')));
    ft.expect(codes, ft.isNot(ft.contains('+1340')));
    ft.expect(codes, ft.isNot(ft.contains('+1787')));
  });

  ft.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    ft.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    ft.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    ft.expect(barqApp.normalizeBarqContactPhoneDigits('---'), ft.isEmpty);
  });

  ft.test('conversation search ft.matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    ft.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    ft.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    ft.expect(barqApp.searchConversationMessages(messages, 'not found'), ft.isEmpty);
    ft.expect(barqApp.searchConversationMessages(messages, '   '), ft.isEmpty);
  });

  ft.test('offline sync pauses only for network failures, not one rejected message', () {
    ft.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), ft.isTrue);
    ft.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), ft.isFalse);
    ft.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), ft.isFalse);
  });

  ft.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), ft.isTrue);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), ft.isFalse);
  });

  ft.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  ft.test('accepted outbox removal preserves a ft.same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    ft.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    ft.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      ft.isEmpty,
    );
  });

  ft.test('offline reconciliation keeps a ft.same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  ft.test('offline queue capacity rejects the first item beyond the limit', () {
    ft.expect(barqApp.barqOfflineQueueIsFull(0), ft.isFalse);
    ft.expect(barqApp.barqOfflineQueueIsFull(199), ft.isFalse);
    ft.expect(barqApp.barqOfflineQueueIsFull(200), ft.isTrue);
    ft.expect(barqApp.barqOfflineQueueIsFull(201), ft.isTrue);
    ft.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), ft.isTrue);
  });

  ft.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    ft.expect(barqApp.decodeBarqOfflineQueue(null), ft.isEmpty);
    ft.expect(barqApp.decodeBarqOfflineQueue(''), ft.isEmpty);
    ft.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  ft.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), ft.isTrue);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), ft.isFalse);
  });

  ft.test('offline queue reconciliation removes exact ft.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    ft.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), ft.same(queued));
  });

  ft.test('message merge deduplicates by id and keeps chronological order', () {
    final merged = barqApp.mergeMessages(
      [
        {'id': 'm2', 'created_at': '2026-11-19 10:02:00', 'body': 'second'},
        {'id': 'm1', 'created_at': '2026-11-19 10:01:00', 'body': 'first'},
      ],
      [
        {'id': 'm2', 'created_at': '2026-11-19 10:02:00', 'body': 'second updated'},
        {'id': 'm3', 'created_at': '2026-11-19 10:03:00', 'body': 'third'},
      ],
    );

    ft.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    ft.expect(merged[1]['body'], 'second updated');
  });

  ft.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    ft.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    ft.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  ft.test('profile photo path is resolved for group payloads with snake_case fields', () {
    ft.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    ft.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), ft.isEmpty);
    ft.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  ft.test('group roles limit promotion to owners and preserve the owner account', () {
    ft.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), ft.isTrue);
    ft.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), ft.isFalse);
    ft.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), ft.isFalse);
    ft.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), ft.isFalse);
  });

  ft.test('group removal permissions prevent admins removing peers or owners', () {
    ft.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      ft.isFalse,
    );
  });

  ft.test('only an owner can transfer group ownership to another non-owner member', () {
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      ft.isFalse,
    );
  });

  ft.test('group members can leave themselves but the owner cannot leave without transfer', () {
    ft.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), ft.isTrue);
    ft.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), ft.isFalse);
    ft.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), ft.isFalse);
  });

  ft.testWidgets('public profile page shows the selected contact details', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: barqApp.PublicProfilePage(
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

    ft.expect(find.text('الملف الشخصي'), findsOneWidget);
    ft.expect(find.text('صديق برق'), findsOneWidget);
    ft.expect(find.text('@barq_friend'), findsNWidgets(2));
    ft.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    ft.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    ft.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    ft.expect(sendButton.onPressed, ft.isNotNull);
  });


  ft.testWidgets('public profile disables messaging for the current user', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: barqApp.PublicProfilePage(
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
    ft.expect(sendButton.onPressed, ft.isNull);
  });

  ft.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: barqApp.PublicProfilePage(
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

    ft.expect(find.text('عضو المجموعة'), findsOneWidget);
    ft.expect(find.text('@group_member'), findsNWidgets(2));
    ft.expect(find.text('إرسال رسالة'), findsNothing);
  });

  ft.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    ft.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  ft.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
    var deleted = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('نسخ الرسالة'), findsOneWidget);
    ft.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    ft.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    ft.expect(deleted, ft.isTrue);
  });

  ft.testWidgets('other users message actions do not expose delete', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('نسخ الرسالة'), findsOneWidget);
    ft.expect(find.text('حذف الرسالة'), findsNothing);
  });

  ft.test('quoted reply preview is bounded and handles attachment references', () {
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  ft.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            saved = await barqApp.showEditMessageDialog(context, 'النص القديم');
          },
          child: const Text('فتح التعديل'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح التعديل'));
    await tester.pumpAndSettle();
    ft.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    ft.expect(saved, 'النص الجديد');
  });

  ft.testWidgets('message action menu invokes the reply callback', (tester) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    ft.expect(selected?['id'], 'reply-1');
  });


  ft.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    ft.expect(normalized, ft.hasLength(2));
    ft.expect(normalized.first['emoji'], '❤️');
    ft.expect(normalized.last['user_id'], 'u2');
    ft.expect(barqApp.normalizeMessageReactions(null), ft.isEmpty);
  });

  ft.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
    String? selectedEmoji;
    bool? removing;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: barqApp.messageReactionBar(
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

    ft.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    ft.expect(selectedEmoji, '❤️');
    ft.expect(removing, ft.isTrue);
  });

  ft.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('إضافة تفاعل'), findsOneWidget);
    ft.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    ft.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  ft.test('media duration formatter supports minute and hour lengths', () {
    ft.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    ft.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    ft.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  ft.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    ft.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  ft.test('message link extraction ignores non-web schemes', () {
    ft.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  ft.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => barqApp.BarqConversationSummaryDialog(
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
    ft.expect(requests, 0);
    ft.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    ft.expect(requests, 1);
    ft.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  ft.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
    var selectedTool = '';
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showBarqConversationTools(context, [
            barqApp.BarqConversationTool(
              icon: Icons.search,
              title: 'البحث في المحادثة',
              subtitle: 'ابحث داخل الرسائل',
              onTap: () => selectedTool = 'search',
            ),
            barqApp.BarqConversationTool(
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
    ft.expect(find.text('أدوات المحادثة'), findsOneWidget);
    ft.expect(find.text('البحث في المحادثة'), findsOneWidget);
    ft.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    ft.expect(selectedTool, 'pinned');
  });

  ft.test('private and group message text share the server 5000-character limit', () {
    ft.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), ft.isTrue);
    ft.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), ft.isTrue);
    ft.expect(barqApp.isBarqMessageTextAllowed(''), ft.isFalse);
    ft.expect(barqApp.isBarqMessageTextAllowed('   '), ft.isFalse);
    ft.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), ft.isTrue);
    ft.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), ft.isFalse);
  });

  ft.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    ft.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), ft.isFalse);
    ft.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), ft.isTrue);
    ft.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), ft.isTrue);
    ft.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), ft.isFalse);
  });

  ft.test('audio transcription enforces the worker two-megabyte limit', () {
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(0), ft.isFalse);
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(1), ft.isTrue);
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), ft.isTrue);
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), ft.isFalse);
  });


  ft.test('SPARK media extensions map to exact supported MIME types', () {
    ft.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    ft.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    ft.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    ft.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    ft.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    ft.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    ft.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    ft.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    ft.expect(barqApp.barqSparkMediaContentType('exe'), ft.isNull);
    ft.expect(barqApp.barqSparkMediaContentType(''), ft.isNull);
  });

  ft.test('SPARK media client size limit rejects empty and oversized files', () {
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(0), ft.isFalse);
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(1), ft.isTrue);
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), ft.isTrue);
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), ft.isFalse);
  });


  ft.test('private memory photo uploads continue after an individual failure', () async {
    final attempted = <String>[];
    final photos = [
      {'name': 'one.jpg', 'bytes': <int>[1], 'contentType': 'image/jpeg'},
      {'name': 'two.png', 'bytes': <int>[2], 'contentType': 'image/png'},
      {'name': 'three.webp', 'bytes': <int>[3], 'contentType': 'image/webp'},
    ];

    final failures = await barqApp.uploadPrivateMemoryPhotosSequentially(
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

    ft.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    ft.expect(failures, ['two.png']);
  });

  ft.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    ft.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    ft.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    ft.expect(retried, ft.isTrue);
  });

  ft.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: barqApp.PrivateMemoryPhotoGallery(media: []),
          ),
        ),
      ),
    );

    ft.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    ft.expect(find.byType(PageView), findsNothing);
    ft.expect(find.textContaining('/'), findsNothing);
  });

  ft.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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
            child: barqApp.PrivateMemoryPhotoGallery(
              media: photos,
              onPageChanged: (page) => visiblePage = page,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    ft.expect(find.byType(PageView), findsOneWidget);
    ft.expect(find.byType(InteractiveViewer), findsWidgets);
    ft.expect(visiblePage, 0);
    ft.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    ft.expect(visiblePage, 1);
    ft.expect(find.text('2 / 3'), findsOneWidget);
  });


  ft.test('BARQ has exactly the four approved visual identities', () {
    ft.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    ft.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    ft.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    ft.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    ft.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  ft.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    ft.expect(BarqIdentity.values, ft.hasLength(4));
    ft.expect(palettes.map((p) => p.background).toSet().length, 4);
    ft.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      ft.expect(palette.text, ft.isNot(palette.background));
      ft.expect(palette.primary, ft.isNot(palette.background));
      ft.expect(palette.secondary, ft.isNot(palette.surface));
      ft.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      ft.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      ft.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      ft.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    ft.expect(blue.primary, const Color(0xFFD6AD55));
    ft.expect(blue.secondary, const Color(0xFF168BFF));
    ft.expect(blue.background, const Color(0xFF090909));
    ft.expect(blue.surface, const Color(0xFF171717));
  });

  ft.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    ft.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    ft.expect(barqApp.normalizeBarqFcmToken(null), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken(''), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken('   '), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken('token with spaces'), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), ft.hasLength(4096));
  });

  ft.test('foreground push uses generic labels and respects category preferences', () {
    ft.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    ft.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    ft.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), ft.isNull);
  });

  ft.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    ft.expect(success, ft.isTrue);
    ft.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    ft.expect(noSession, ft.isFalse);
    ft.expect(revoked, ft.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    ft.expect(invalidToken, ft.isFalse);
    ft.expect(revoked, ft.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    ft.expect(networkFailure, ft.isFalse);
  });

  ft.test('FCM registration requires authorized or provisional notification permission', () {
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), ft.isTrue);
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), ft.isTrue);
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), ft.isFalse);
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), ft.isFalse);
  });

}
)));
    ft.expect(first, ft.isNot(ft.contains('967770000000')));
    ft.expect(barqApp.barqPrivateRegistrationUsername('+447911123456'), ft.isNot(first));
  });

  ft.test('international phone normalization supports Arabic digits and 00 prefix', () {
    ft.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    ft.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    ft.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    ft.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    ft.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  ft.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    ft.expect(barqApp.barqCountryCodes.length, 206);
    final codes = barqApp.barqCountryCodes.map((country) => country.$2).toSet();
    ft.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      ft.expect(codes, ft.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    ft.expect(codes, ft.isNot(ft.contains('+1684')));
    ft.expect(codes, ft.isNot(ft.contains('+1340')));
    ft.expect(codes, ft.isNot(ft.contains('+1787')));
  });

  ft.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    ft.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    ft.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    ft.expect(barqApp.normalizeBarqContactPhoneDigits('---'), ft.isEmpty);
  });

  ft.test('conversation search ft.matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    ft.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    ft.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    ft.expect(barqApp.searchConversationMessages(messages, 'not found'), ft.isEmpty);
    ft.expect(barqApp.searchConversationMessages(messages, '   '), ft.isEmpty);
  });

  ft.test('offline sync pauses only for network failures, not one rejected message', () {
    ft.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), ft.isTrue);
    ft.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), ft.isFalse);
    ft.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), ft.isFalse);
  });

  ft.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), ft.isTrue);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), ft.isFalse);
  });

  ft.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  ft.test('accepted outbox removal preserves a ft.same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    ft.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    ft.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      ft.isEmpty,
    );
  });

  ft.test('offline reconciliation keeps a ft.same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  ft.test('offline queue capacity rejects the first item beyond the limit', () {
    ft.expect(barqApp.barqOfflineQueueIsFull(0), ft.isFalse);
    ft.expect(barqApp.barqOfflineQueueIsFull(199), ft.isFalse);
    ft.expect(barqApp.barqOfflineQueueIsFull(200), ft.isTrue);
    ft.expect(barqApp.barqOfflineQueueIsFull(201), ft.isTrue);
    ft.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), ft.isTrue);
  });

  ft.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    ft.expect(barqApp.decodeBarqOfflineQueue(null), ft.isEmpty);
    ft.expect(barqApp.decodeBarqOfflineQueue(''), ft.isEmpty);
    ft.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    ft.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  ft.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), ft.isTrue);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), ft.isFalse);
    ft.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), ft.isFalse);
  });

  ft.test('offline queue reconciliation removes exact ft.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    ft.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    ft.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), ft.same(queued));
  });

  ft.test('message merge deduplicates by id and keeps chronological order', () {
    final merged = barqApp.mergeMessages(
      [
        {'id': 'm2', 'created_at': '2026-11-19 10:02:00', 'body': 'second'},
        {'id': 'm1', 'created_at': '2026-11-19 10:01:00', 'body': 'first'},
      ],
      [
        {'id': 'm2', 'created_at': '2026-11-19 10:02:00', 'body': 'second updated'},
        {'id': 'm3', 'created_at': '2026-11-19 10:03:00', 'body': 'third'},
      ],
    );

    ft.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    ft.expect(merged[1]['body'], 'second updated');
  });

  ft.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    ft.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    ft.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  ft.test('profile photo path is resolved for group payloads with snake_case fields', () {
    ft.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    ft.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), ft.isEmpty);
    ft.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  ft.test('group roles limit promotion to owners and preserve the owner account', () {
    ft.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), ft.isTrue);
    ft.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), ft.isFalse);
    ft.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), ft.isFalse);
    ft.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), ft.isFalse);
  });

  ft.test('group removal permissions prevent admins removing peers or owners', () {
    ft.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      ft.isFalse,
    );
  });

  ft.test('only an owner can transfer group ownership to another non-owner member', () {
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      ft.isTrue,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      ft.isFalse,
    );
    ft.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      ft.isFalse,
    );
  });

  ft.test('group members can leave themselves but the owner cannot leave without transfer', () {
    ft.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), ft.isTrue);
    ft.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), ft.isFalse);
    ft.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), ft.isFalse);
  });

  ft.testWidgets('public profile page shows the selected contact details', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: barqApp.PublicProfilePage(
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

    ft.expect(find.text('الملف الشخصي'), findsOneWidget);
    ft.expect(find.text('صديق برق'), findsOneWidget);
    ft.expect(find.text('@barq_friend'), findsNWidgets(2));
    ft.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    ft.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    ft.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    ft.expect(sendButton.onPressed, ft.isNotNull);
  });


  ft.testWidgets('public profile disables messaging for the current user', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: barqApp.PublicProfilePage(
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
    ft.expect(sendButton.onPressed, ft.isNull);
  });

  ft.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: barqApp.PublicProfilePage(
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

    ft.expect(find.text('عضو المجموعة'), findsOneWidget);
    ft.expect(find.text('@group_member'), findsNWidgets(2));
    ft.expect(find.text('إرسال رسالة'), findsNothing);
  });

  ft.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    ft.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  ft.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
    var deleted = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('نسخ الرسالة'), findsOneWidget);
    ft.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    ft.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    ft.expect(deleted, ft.isTrue);
  });

  ft.testWidgets('other users message actions do not expose delete', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('نسخ الرسالة'), findsOneWidget);
    ft.expect(find.text('حذف الرسالة'), findsNothing);
  });

  ft.test('quoted reply preview is bounded and handles attachment references', () {
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    ft.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  ft.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            saved = await barqApp.showEditMessageDialog(context, 'النص القديم');
          },
          child: const Text('فتح التعديل'),
        ),
      )),
    ));

    await tester.tap(find.text('فتح التعديل'));
    await tester.pumpAndSettle();
    ft.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    ft.expect(saved, 'النص الجديد');
  });

  ft.testWidgets('message action menu invokes the reply callback', (tester) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    ft.expect(selected?['id'], 'reply-1');
  });


  ft.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    ft.expect(normalized, ft.hasLength(2));
    ft.expect(normalized.first['emoji'], '❤️');
    ft.expect(normalized.last['user_id'], 'u2');
    ft.expect(barqApp.normalizeMessageReactions(null), ft.isEmpty);
  });

  ft.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
    String? selectedEmoji;
    bool? removing;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: barqApp.messageReactionBar(
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

    ft.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    ft.expect(selectedEmoji, '❤️');
    ft.expect(removing, ft.isTrue);
  });

  ft.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showMessageActions(
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
    ft.expect(find.text('إضافة تفاعل'), findsOneWidget);
    ft.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    ft.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  ft.test('media duration formatter supports minute and hour lengths', () {
    ft.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    ft.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    ft.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  ft.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    ft.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  ft.test('message link extraction ignores non-web schemes', () {
    ft.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  ft.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => barqApp.BarqConversationSummaryDialog(
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
    ft.expect(requests, 0);
    ft.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    ft.expect(requests, 1);
    ft.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  ft.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
    var selectedTool = '';
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => barqApp.showBarqConversationTools(context, [
            barqApp.BarqConversationTool(
              icon: Icons.search,
              title: 'البحث في المحادثة',
              subtitle: 'ابحث داخل الرسائل',
              onTap: () => selectedTool = 'search',
            ),
            barqApp.BarqConversationTool(
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
    ft.expect(find.text('أدوات المحادثة'), findsOneWidget);
    ft.expect(find.text('البحث في المحادثة'), findsOneWidget);
    ft.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    ft.expect(selectedTool, 'pinned');
  });

  ft.test('private and group message text share the server 5000-character limit', () {
    ft.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), ft.isTrue);
    ft.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), ft.isTrue);
    ft.expect(barqApp.isBarqMessageTextAllowed(''), ft.isFalse);
    ft.expect(barqApp.isBarqMessageTextAllowed('   '), ft.isFalse);
    ft.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), ft.isTrue);
    ft.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), ft.isFalse);
  });

  ft.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    ft.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), ft.isFalse);
    ft.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), ft.isTrue);
    ft.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), ft.isTrue);
    ft.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), ft.isFalse);
  });

  ft.test('audio transcription enforces the worker two-megabyte limit', () {
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(0), ft.isFalse);
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(1), ft.isTrue);
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), ft.isTrue);
    ft.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), ft.isFalse);
  });


  ft.test('SPARK media extensions map to exact supported MIME types', () {
    ft.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    ft.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    ft.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    ft.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    ft.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    ft.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    ft.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    ft.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    ft.expect(barqApp.barqSparkMediaContentType('exe'), ft.isNull);
    ft.expect(barqApp.barqSparkMediaContentType(''), ft.isNull);
  });

  ft.test('SPARK media client size limit rejects empty and oversized files', () {
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(0), ft.isFalse);
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(1), ft.isTrue);
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), ft.isTrue);
    ft.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), ft.isFalse);
  });


  ft.test('private memory photo uploads continue after an individual failure', () async {
    final attempted = <String>[];
    final photos = [
      {'name': 'one.jpg', 'bytes': <int>[1], 'contentType': 'image/jpeg'},
      {'name': 'two.png', 'bytes': <int>[2], 'contentType': 'image/png'},
      {'name': 'three.webp', 'bytes': <int>[3], 'contentType': 'image/webp'},
    ];

    final failures = await barqApp.uploadPrivateMemoryPhotosSequentially(
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

    ft.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    ft.expect(failures, ['two.png']);
  });

  ft.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    ft.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    ft.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    ft.expect(retried, ft.isTrue);
  });

  ft.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: barqApp.PrivateMemoryPhotoGallery(media: []),
          ),
        ),
      ),
    );

    ft.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    ft.expect(find.byType(PageView), findsNothing);
    ft.expect(find.textContaining('/'), findsNothing);
  });

  ft.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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
            child: barqApp.PrivateMemoryPhotoGallery(
              media: photos,
              onPageChanged: (page) => visiblePage = page,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    ft.expect(find.byType(PageView), findsOneWidget);
    ft.expect(find.byType(InteractiveViewer), findsWidgets);
    ft.expect(visiblePage, 0);
    ft.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    ft.expect(visiblePage, 1);
    ft.expect(find.text('2 / 3'), findsOneWidget);
  });


  ft.test('BARQ has exactly the four approved visual identities', () {
    ft.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    ft.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    ft.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    ft.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    ft.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  ft.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    ft.expect(BarqIdentity.values, ft.hasLength(4));
    ft.expect(palettes.map((p) => p.background).toSet().length, 4);
    ft.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      ft.expect(palette.text, ft.isNot(palette.background));
      ft.expect(palette.primary, ft.isNot(palette.background));
      ft.expect(palette.secondary, ft.isNot(palette.surface));
      ft.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      ft.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      ft.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      ft.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    ft.expect(blue.primary, const Color(0xFFD6AD55));
    ft.expect(blue.secondary, const Color(0xFF168BFF));
    ft.expect(blue.background, const Color(0xFF090909));
    ft.expect(blue.surface, const Color(0xFF171717));
  });

  ft.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    ft.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    ft.expect(barqApp.normalizeBarqFcmToken(null), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken(''), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken('   '), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken('token with spaces'), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), ft.isNull);
    ft.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), ft.hasLength(4096));
  });

  ft.test('foreground push uses generic labels and respects category preferences', () {
    ft.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    ft.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    ft.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), ft.isNull);
    ft.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), ft.isNull);
  });

  ft.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    ft.expect(success, ft.isTrue);
    ft.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    ft.expect(noSession, ft.isFalse);
    ft.expect(revoked, ft.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    ft.expect(invalidToken, ft.isFalse);
    ft.expect(revoked, ft.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    ft.expect(networkFailure, ft.isFalse);
  });

  ft.test('FCM registration requires authorized or provisional notification permission', () {
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), ft.isTrue);
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), ft.isTrue);
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), ft.isFalse);
    ft.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), ft.isFalse);
  });

}
