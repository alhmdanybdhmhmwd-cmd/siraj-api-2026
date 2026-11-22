import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as flutterTest;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart' as barqApp;
import 'package:barq/barq_identity.dart';

void main() {
  flutterTest.test('optional realtime connects only with a session, endpoint and resumed app', () {
    flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), flutterTest.isFalse);
  });

  flutterTest.test('realtime events refresh only the matching direct conversation', () {
    flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      flutterTest.isFalse,
    );
  });

  flutterTest.test('notification tap routing validates private chat, group and SPARK destinations', () {
    flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    flutterTest.expect(barqApp.barqNotificationRouteFromData({'type': 'direct_message'}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), flutterTest.isNull);
  });

  flutterTest.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), flutterTest.isNull);
    flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), flutterTest.isNull);
  });

  flutterTest.test('Nearby requests only permissions supported by the Android API level', () {
    flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    flutterTest.expect(barqApp.barqNearbyRequiresLocationService(30), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqNearbyRequiresLocationService(32), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqNearbyRequiresLocationService(33), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqNearbyRequiresLocationService(37), flutterTest.isFalse);
  });

  flutterTest.test('Nearby payload transfer treats failure and cancellation as failed', () {
    flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.NONE), flutterTest.isFalse);
  });

  flutterTest.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), flutterTest.isTrue);
    flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), flutterTest.isFalse);
  });

  flutterTest.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isTrue);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
    flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), flutterTest.isFalse);
  });

  flutterTest.test('registration sends a stable private username without exposing the phone', () {
    final first = barqApp.barqPrivateRegistrationUsername('+967770000000');
    final second = barqApp.barqPrivateRegistrationUsername('+967770000000');
    flutterTest.expect(first, second);
    flutterTest.expect(first, matches(RegExp(r'^barq[a-f0-9]{16}$')));
    flutterTest.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    flutterTest.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  flutterTest.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    flutterTest.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    flutterTest.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      flutterTest.expect(codes, flutterTest.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    flutterTest.expect(codes, flutterTest.isNot(flutterTest.contains('+1684')));
    flutterTest.expect(codes, flutterTest.isNot(flutterTest.contains('+1340')));
    flutterTest.expect(codes, flutterTest.isNot(flutterTest.contains('+1787')));
  });

  flutterTest.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    flutterTest.expect(barqApp.normalizeBarqContactPhoneDigits('---'), flutterTest.isEmpty);
  });

  flutterTest.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    flutterTest.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    flutterTest.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    flutterTest.expect(barqApp.searchConversationMessages(messages, 'not found'), flutterTest.isEmpty);
    flutterTest.expect(barqApp.searchConversationMessages(messages, '   '), flutterTest.isEmpty);
  });

  flutterTest.test('offline sync pauses only for network failures, not one rejected message', () {
    flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), flutterTest.isFalse);
  });

  flutterTest.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTest.isFalse);
  });

  flutterTest.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  flutterTest.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      flutterTest.isEmpty,
    );
  });

  flutterTest.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  flutterTest.test('offline queue capacity rejects the first item beyond the limit', () {
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(0), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(199), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(200), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(201), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), flutterTest.isTrue);
  });

  flutterTest.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    flutterTest.expect(barqApp.decodeBarqOfflineQueue(null), flutterTest.isEmpty);
    flutterTest.expect(barqApp.decodeBarqOfflineQueue(''), flutterTest.isEmpty);
    flutterTest.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), flutterTest.throwsFormatException);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), flutterTest.throwsFormatException);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), flutterTest.throwsFormatException);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), flutterTest.throwsFormatException);
  });

  flutterTest.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTest.isFalse);
  });

  flutterTest.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    flutterTest.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  flutterTest.test('message merge deduplicates by id and keeps chronological order', () {
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

    flutterTest.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    flutterTest.expect(merged[1]['body'], 'second updated');
  });

  flutterTest.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    flutterTest.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    flutterTest.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  flutterTest.test('profile photo path is resolved for group payloads with snake_case fields', () {
    flutterTest.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    flutterTest.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), flutterTest.isEmpty);
    flutterTest.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  flutterTest.test('group roles limit promotion to owners and preserve the owner account', () {
    flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), flutterTest.isFalse);
  });

  flutterTest.test('group removal permissions prevent admins removing peers or owners', () {
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      flutterTest.isFalse,
    );
  });

  flutterTest.test('only an owner can transfer group ownership to another non-owner member', () {
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      flutterTest.isFalse,
    );
  });

  flutterTest.test('group members can leave themselves but the owner cannot leave without transfer', () {
    flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), flutterTest.isFalse);
  });

  flutterTest.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    flutterTest.expect(find.text('الملف الشخصي'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('صديق برق'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('@barq_friend'), flutterTest.findsNWidgets(2));
    flutterTest.expect(find.text('+967700000001'), flutterTest.findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    flutterTest.expect(find.text('حفظ الرقم في جهات الاتصال'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('إرسال رسالة'), flutterTest.findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    flutterTest.expect(sendButton.onPressed, flutterTest.isNotNull);
  });


  flutterTest.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    flutterTest.expect(sendButton.onPressed, flutterTest.isNull);
  });

  flutterTest.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    flutterTest.expect(find.text('عضو المجموعة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('@group_member'), flutterTest.findsNWidgets(2));
    flutterTest.expect(find.text('إرسال رسالة'), flutterTest.findsNothing);
  });

  flutterTest.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    flutterTest.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  flutterTest.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    flutterTest.expect(find.text('نسخ الرسالة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('حذف الرسالة'), flutterTest.findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    flutterTest.expect(find.text('حذف الرسالة؟'), flutterTest.findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    flutterTest.expect(deleted, flutterTest.isTrue);
  });

  flutterTest.testWidgets('other users message actions do not expose delete', (tester) async {
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
    flutterTest.expect(find.text('نسخ الرسالة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('حذف الرسالة'), flutterTest.findsNothing);
  });

  flutterTest.test('quoted reply preview is bounded and handles attachment references', () {
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  flutterTest.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    flutterTest.expect(find.text('تعديل الرسالة'), flutterTest.findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    flutterTest.expect(saved, 'النص الجديد');
  });

  flutterTest.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    flutterTest.expect(find.text('الرد على الرسالة'), flutterTest.findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    flutterTest.expect(selected?['id'], 'reply-1');
  });


  flutterTest.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    flutterTest.expect(normalized, flutterTest.hasLength(2));
    flutterTest.expect(normalized.first['emoji'], '❤️');
    flutterTest.expect(normalized.last['user_id'], 'u2');
    flutterTest.expect(barqApp.normalizeMessageReactions(null), flutterTest.isEmpty);
  });

  flutterTest.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    flutterTest.expect(find.text('❤️ 2'), flutterTest.findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    flutterTest.expect(selectedEmoji, '❤️');
    flutterTest.expect(removing, flutterTest.isTrue);
  });

  flutterTest.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    flutterTest.expect(find.text('إضافة تفاعل'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('تثبيت الرسالة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('حفظ في الذكريات الخاصة'), flutterTest.findsOneWidget);
  });

  flutterTest.test('media duration formatter supports minute and hour lengths', () {
    flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  flutterTest.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    flutterTest.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  flutterTest.test('message link extraction ignores non-web schemes', () {
    flutterTest.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  flutterTest.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    flutterTest.expect(requests, 0);
    flutterTest.expect(find.text('إنشاء الملخص'), flutterTest.findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    flutterTest.expect(requests, 1);
    flutterTest.expect(find.text('ملخص اختباري'), flutterTest.findsOneWidget);
  });

  flutterTest.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    flutterTest.expect(find.text('أدوات المحادثة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('البحث في المحادثة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('الرسائل المثبتة'), flutterTest.findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    flutterTest.expect(selectedTool, 'pinned');
  });

  flutterTest.test('private and group message text share the server 5000-character limit', () {
    flutterTest.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed(''), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed('   '), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), flutterTest.isFalse);
  });

  flutterTest.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), flutterTest.isFalse);
  });

  flutterTest.test('audio transcription enforces the worker two-megabyte limit', () {
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(0), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(1), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), flutterTest.isFalse);
  });


  flutterTest.test('SPARK media extensions map to exact supported MIME types', () {
    flutterTest.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    flutterTest.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    flutterTest.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    flutterTest.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    flutterTest.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    flutterTest.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    flutterTest.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    flutterTest.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    flutterTest.expect(barqApp.barqSparkMediaContentType('exe'), flutterTest.isNull);
    flutterTest.expect(barqApp.barqSparkMediaContentType(''), flutterTest.isNull);
  });

  flutterTest.test('SPARK media client size limit rejects empty and oversized files', () {
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(0), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(1), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), flutterTest.isFalse);
  });


  flutterTest.test('private memory photo uploads continue after an individual failure', () async {
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

    flutterTest.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    flutterTest.expect(failures, ['two.png']);
  });

  flutterTest.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    flutterTest.expect(find.text('تعذر تحميل ذكرياتك'), flutterTest.findsOneWidget);
    flutterTest.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), flutterTest.findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    flutterTest.expect(retried, flutterTest.isTrue);
  });

  flutterTest.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    flutterTest.expect(find.byIcon(Icons.photo_library_outlined), flutterTest.findsOneWidget);
    flutterTest.expect(find.byType(PageView), flutterTest.findsNothing);
    flutterTest.expect(find.textContaining('/'), flutterTest.findsNothing);
  });

  flutterTest.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    flutterTest.expect(find.byType(PageView), flutterTest.findsOneWidget);
    flutterTest.expect(find.byType(InteractiveViewer), flutterTest.findsWidgets);
    flutterTest.expect(visiblePage, 0);
    flutterTest.expect(find.text('1 / 3'), flutterTest.findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    flutterTest.expect(visiblePage, 1);
    flutterTest.expect(find.text('2 / 3'), flutterTest.findsOneWidget);
  });


  flutterTest.test('BARQ has exactly the four approved visual identities', () {
    flutterTest.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    flutterTest.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    flutterTest.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    flutterTest.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    flutterTest.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  flutterTest.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    flutterTest.expect(BarqIdentity.values, flutterTest.hasLength(4));
    flutterTest.expect(palettes.map((p) => p.background).toSet().length, 4);
    flutterTest.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      flutterTest.expect(palette.text, flutterTest.isNot(palette.background));
      flutterTest.expect(palette.primary, flutterTest.isNot(palette.background));
      flutterTest.expect(palette.secondary, flutterTest.isNot(palette.surface));
      flutterTest.expect(contrastRatio(palette.text, palette.background), flutterTest.greaterThanOrEqualTo(7));
      flutterTest.expect(contrastRatio(palette.text, palette.surface), flutterTest.greaterThanOrEqualTo(7));
      flutterTest.expect(contrastRatio(palette.mutedText, palette.surface), flutterTest.greaterThanOrEqualTo(4.5));
      flutterTest.expect(contrastRatio(palette.primary, palette.surface), flutterTest.greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    flutterTest.expect(blue.primary, const Color(0xFFD6AD55));
    flutterTest.expect(blue.secondary, const Color(0xFF168BFF));
    flutterTest.expect(blue.background, const Color(0xFF090909));
    flutterTest.expect(blue.surface, const Color(0xFF171717));
  });

  flutterTest.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    flutterTest.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    flutterTest.expect(barqApp.normalizeBarqFcmToken(null), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken(''), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken('   '), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken('token with spaces'), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), flutterTest.hasLength(4096));
  });

  flutterTest.test('foreground push uses generic labels and respects category preferences', () {
    flutterTest.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), flutterTest.isNull);
  });

  flutterTest.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    flutterTest.expect(success, flutterTest.isTrue);
    flutterTest.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    flutterTest.expect(noSession, flutterTest.isFalse);
    flutterTest.expect(revoked, flutterTest.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    flutterTest.expect(invalidToken, flutterTest.isFalse);
    flutterTest.expect(revoked, flutterTest.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    flutterTest.expect(networkFailure, flutterTest.isFalse);
  });

  flutterTest.test('FCM registration requires authorized or provisional notification permission', () {
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), flutterTest.isFalse);
  });

}
)));
    flutterTest.expect(first, flutterTest.isNot(flutterTest.contains('967770000000')));
    flutterTest.expect(barqApp.barqPrivateRegistrationUsername('+447911123456'), flutterTest.isNot(first));
  });

  flutterTest.test('international phone normalization supports Arabic digits and 00 prefix', () {
    flutterTest.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    flutterTest.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  flutterTest.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    flutterTest.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    flutterTest.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      flutterTest.expect(codes, flutterTest.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    flutterTest.expect(codes, flutterTest.isNot(flutterTest.contains('+1684')));
    flutterTest.expect(codes, flutterTest.isNot(flutterTest.contains('+1340')));
    flutterTest.expect(codes, flutterTest.isNot(flutterTest.contains('+1787')));
  });

  flutterTest.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    flutterTest.expect(barqApp.normalizeBarqContactPhoneDigits('---'), flutterTest.isEmpty);
  });

  flutterTest.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    flutterTest.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    flutterTest.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    flutterTest.expect(barqApp.searchConversationMessages(messages, 'not found'), flutterTest.isEmpty);
    flutterTest.expect(barqApp.searchConversationMessages(messages, '   '), flutterTest.isEmpty);
  });

  flutterTest.test('offline sync pauses only for network failures, not one rejected message', () {
    flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), flutterTest.isFalse);
  });

  flutterTest.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTest.isFalse);
  });

  flutterTest.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  flutterTest.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      flutterTest.isEmpty,
    );
  });

  flutterTest.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  flutterTest.test('offline queue capacity rejects the first item beyond the limit', () {
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(0), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(199), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(200), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(201), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), flutterTest.isTrue);
  });

  flutterTest.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    flutterTest.expect(barqApp.decodeBarqOfflineQueue(null), flutterTest.isEmpty);
    flutterTest.expect(barqApp.decodeBarqOfflineQueue(''), flutterTest.isEmpty);
    flutterTest.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), flutterTest.throwsFormatException);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), flutterTest.throwsFormatException);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), flutterTest.throwsFormatException);
    flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), flutterTest.throwsFormatException);
  });

  flutterTest.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTest.isFalse);
  });

  flutterTest.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    flutterTest.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  flutterTest.test('message merge deduplicates by id and keeps chronological order', () {
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

    flutterTest.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    flutterTest.expect(merged[1]['body'], 'second updated');
  });

  flutterTest.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    flutterTest.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    flutterTest.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  flutterTest.test('profile photo path is resolved for group payloads with snake_case fields', () {
    flutterTest.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    flutterTest.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), flutterTest.isEmpty);
    flutterTest.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  flutterTest.test('group roles limit promotion to owners and preserve the owner account', () {
    flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), flutterTest.isFalse);
  });

  flutterTest.test('group removal permissions prevent admins removing peers or owners', () {
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      flutterTest.isFalse,
    );
  });

  flutterTest.test('only an owner can transfer group ownership to another non-owner member', () {
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isTrue,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      flutterTest.isFalse,
    );
    flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      flutterTest.isFalse,
    );
  });

  flutterTest.test('group members can leave themselves but the owner cannot leave without transfer', () {
    flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), flutterTest.isFalse);
  });

  flutterTest.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    flutterTest.expect(find.text('الملف الشخصي'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('صديق برق'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('@barq_friend'), flutterTest.findsNWidgets(2));
    flutterTest.expect(find.text('+967700000001'), flutterTest.findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    flutterTest.expect(find.text('حفظ الرقم في جهات الاتصال'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('إرسال رسالة'), flutterTest.findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    flutterTest.expect(sendButton.onPressed, flutterTest.isNotNull);
  });


  flutterTest.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    flutterTest.expect(sendButton.onPressed, flutterTest.isNull);
  });

  flutterTest.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    flutterTest.expect(find.text('عضو المجموعة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('@group_member'), flutterTest.findsNWidgets(2));
    flutterTest.expect(find.text('إرسال رسالة'), flutterTest.findsNothing);
  });

  flutterTest.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    flutterTest.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  flutterTest.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    flutterTest.expect(find.text('نسخ الرسالة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('حذف الرسالة'), flutterTest.findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    flutterTest.expect(find.text('حذف الرسالة؟'), flutterTest.findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    flutterTest.expect(deleted, flutterTest.isTrue);
  });

  flutterTest.testWidgets('other users message actions do not expose delete', (tester) async {
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
    flutterTest.expect(find.text('نسخ الرسالة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('حذف الرسالة'), flutterTest.findsNothing);
  });

  flutterTest.test('quoted reply preview is bounded and handles attachment references', () {
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  flutterTest.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    flutterTest.expect(find.text('تعديل الرسالة'), flutterTest.findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    flutterTest.expect(saved, 'النص الجديد');
  });

  flutterTest.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    flutterTest.expect(find.text('الرد على الرسالة'), flutterTest.findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    flutterTest.expect(selected?['id'], 'reply-1');
  });


  flutterTest.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    flutterTest.expect(normalized, flutterTest.hasLength(2));
    flutterTest.expect(normalized.first['emoji'], '❤️');
    flutterTest.expect(normalized.last['user_id'], 'u2');
    flutterTest.expect(barqApp.normalizeMessageReactions(null), flutterTest.isEmpty);
  });

  flutterTest.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    flutterTest.expect(find.text('❤️ 2'), flutterTest.findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    flutterTest.expect(selectedEmoji, '❤️');
    flutterTest.expect(removing, flutterTest.isTrue);
  });

  flutterTest.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    flutterTest.expect(find.text('إضافة تفاعل'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('تثبيت الرسالة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('حفظ في الذكريات الخاصة'), flutterTest.findsOneWidget);
  });

  flutterTest.test('media duration formatter supports minute and hour lengths', () {
    flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  flutterTest.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    flutterTest.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  flutterTest.test('message link extraction ignores non-web schemes', () {
    flutterTest.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  flutterTest.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    flutterTest.expect(requests, 0);
    flutterTest.expect(find.text('إنشاء الملخص'), flutterTest.findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    flutterTest.expect(requests, 1);
    flutterTest.expect(find.text('ملخص اختباري'), flutterTest.findsOneWidget);
  });

  flutterTest.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    flutterTest.expect(find.text('أدوات المحادثة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('البحث في المحادثة'), flutterTest.findsOneWidget);
    flutterTest.expect(find.text('الرسائل المثبتة'), flutterTest.findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    flutterTest.expect(selectedTool, 'pinned');
  });

  flutterTest.test('private and group message text share the server 5000-character limit', () {
    flutterTest.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed(''), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed('   '), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), flutterTest.isFalse);
  });

  flutterTest.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), flutterTest.isFalse);
  });

  flutterTest.test('audio transcription enforces the worker two-megabyte limit', () {
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(0), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(1), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), flutterTest.isFalse);
  });


  flutterTest.test('SPARK media extensions map to exact supported MIME types', () {
    flutterTest.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    flutterTest.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    flutterTest.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    flutterTest.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    flutterTest.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    flutterTest.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    flutterTest.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    flutterTest.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    flutterTest.expect(barqApp.barqSparkMediaContentType('exe'), flutterTest.isNull);
    flutterTest.expect(barqApp.barqSparkMediaContentType(''), flutterTest.isNull);
  });

  flutterTest.test('SPARK media client size limit rejects empty and oversized files', () {
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(0), flutterTest.isFalse);
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(1), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), flutterTest.isTrue);
    flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), flutterTest.isFalse);
  });


  flutterTest.test('private memory photo uploads continue after an individual failure', () async {
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

    flutterTest.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    flutterTest.expect(failures, ['two.png']);
  });

  flutterTest.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    flutterTest.expect(find.text('تعذر تحميل ذكرياتك'), flutterTest.findsOneWidget);
    flutterTest.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), flutterTest.findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    flutterTest.expect(retried, flutterTest.isTrue);
  });

  flutterTest.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    flutterTest.expect(find.byIcon(Icons.photo_library_outlined), flutterTest.findsOneWidget);
    flutterTest.expect(find.byType(PageView), flutterTest.findsNothing);
    flutterTest.expect(find.textContaining('/'), flutterTest.findsNothing);
  });

  flutterTest.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    flutterTest.expect(find.byType(PageView), flutterTest.findsOneWidget);
    flutterTest.expect(find.byType(InteractiveViewer), flutterTest.findsWidgets);
    flutterTest.expect(visiblePage, 0);
    flutterTest.expect(find.text('1 / 3'), flutterTest.findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    flutterTest.expect(visiblePage, 1);
    flutterTest.expect(find.text('2 / 3'), flutterTest.findsOneWidget);
  });


  flutterTest.test('BARQ has exactly the four approved visual identities', () {
    flutterTest.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    flutterTest.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    flutterTest.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    flutterTest.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    flutterTest.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  flutterTest.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    flutterTest.expect(BarqIdentity.values, flutterTest.hasLength(4));
    flutterTest.expect(palettes.map((p) => p.background).toSet().length, 4);
    flutterTest.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      flutterTest.expect(palette.text, flutterTest.isNot(palette.background));
      flutterTest.expect(palette.primary, flutterTest.isNot(palette.background));
      flutterTest.expect(palette.secondary, flutterTest.isNot(palette.surface));
      flutterTest.expect(contrastRatio(palette.text, palette.background), flutterTest.greaterThanOrEqualTo(7));
      flutterTest.expect(contrastRatio(palette.text, palette.surface), flutterTest.greaterThanOrEqualTo(7));
      flutterTest.expect(contrastRatio(palette.mutedText, palette.surface), flutterTest.greaterThanOrEqualTo(4.5));
      flutterTest.expect(contrastRatio(palette.primary, palette.surface), flutterTest.greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    flutterTest.expect(blue.primary, const Color(0xFFD6AD55));
    flutterTest.expect(blue.secondary, const Color(0xFF168BFF));
    flutterTest.expect(blue.background, const Color(0xFF090909));
    flutterTest.expect(blue.surface, const Color(0xFF171717));
  });

  flutterTest.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    flutterTest.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    flutterTest.expect(barqApp.normalizeBarqFcmToken(null), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken(''), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken('   '), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken('token with spaces'), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), flutterTest.isNull);
    flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), flutterTest.hasLength(4096));
  });

  flutterTest.test('foreground push uses generic labels and respects category preferences', () {
    flutterTest.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), flutterTest.isNull);
    flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), flutterTest.isNull);
  });

  flutterTest.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    flutterTest.expect(success, flutterTest.isTrue);
    flutterTest.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    flutterTest.expect(noSession, flutterTest.isFalse);
    flutterTest.expect(revoked, flutterTest.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    flutterTest.expect(invalidToken, flutterTest.isFalse);
    flutterTest.expect(revoked, flutterTest.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    flutterTest.expect(networkFailure, flutterTest.isFalse);
  });

  flutterTest.test('FCM registration requires authorized or provisional notification permission', () {
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), flutterTest.isTrue);
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), flutterTest.isFalse);
    flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), flutterTest.isFalse);
  });

}
