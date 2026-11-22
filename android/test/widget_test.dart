import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as barqTestApi;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart';
import 'package:barq/barq_identity.dart';

void main() {
  barqTestApi.test('optional realtime connects only with a session, endpoint and resumed app', () {
    barqTestApi.expect(barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), barqTestApi.isTrue);
    barqTestApi.expect(barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), barqTestApi.isFalse);
    barqTestApi.expect(barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), barqTestApi.isFalse);
    barqTestApi.expect(barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), barqTestApi.isFalse);
    barqTestApi.expect(barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), barqTestApi.isFalse);
  });

  barqTestApi.test('realtime events refresh only the matching direct conversation', () {
    barqTestApi.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      barqTestApi.isFalse,
    );
  });

  barqTestApi.test('notification tap routing validates private chat, group and SPARK destinations', () {
    barqTestApi.expect(
      barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    barqTestApi.expect(
      barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    barqTestApi.expect(
      barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    barqTestApi.expect(
      barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    barqTestApi.expect(barqNotificationRouteFromData({'type': 'direct_message'}), barqTestApi.isNull);
    barqTestApi.expect(barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), barqTestApi.isNull);
    barqTestApi.expect(barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), barqTestApi.isNull);
  });

  barqTestApi.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), barqTestApi.isNull);
    barqTestApi.expect(barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), barqTestApi.isNull);
  });

  barqTestApi.test('Nearby requests only permissions supported by the Android API level', () {
    barqTestApi.expect(barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    barqTestApi.expect(barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    barqTestApi.expect(barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    barqTestApi.expect(barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    barqTestApi.expect(barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    barqTestApi.expect(barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    barqTestApi.expect(barqNearbyRequiresLocationService(30), barqTestApi.isTrue);
    barqTestApi.expect(barqNearbyRequiresLocationService(32), barqTestApi.isTrue);
    barqTestApi.expect(barqNearbyRequiresLocationService(33), barqTestApi.isFalse);
    barqTestApi.expect(barqNearbyRequiresLocationService(37), barqTestApi.isFalse);
  });

  barqTestApi.test('Nearby payload transfer treats failure and cancellation as failed', () {
    barqTestApi.expect(barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), barqTestApi.isTrue);
    barqTestApi.expect(barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), barqTestApi.isTrue);
    barqTestApi.expect(barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), barqTestApi.isFalse);
    barqTestApi.expect(barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), barqTestApi.isFalse);
    barqTestApi.expect(barqNearbyPayloadTransferFailed(PayloadStatus.NONE), barqTestApi.isFalse);
  });

  barqTestApi.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    barqTestApi.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), barqTestApi.isTrue);
    barqTestApi.expect(isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), barqTestApi.isFalse);
  });

  barqTestApi.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    barqTestApi.expect(isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isTrue);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
    barqTestApi.expect(isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), barqTestApi.isFalse);
  });

  barqTestApi.test('registration sends a stable private username without exposing the phone', () {
    final first = barqPrivateRegistrationUsername('+967770000000');
    final second = barqPrivateRegistrationUsername('+967770000000');
    barqTestApi.expect(first, second);
    barqTestApi.expect(first, matches(RegExp(r'^barq[a-f0-9]{16}$')));
    barqTestApi.expect(normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    barqTestApi.expect(normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    barqTestApi.expect(normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    barqTestApi.expect(normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  barqTestApi.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    barqTestApi.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    barqTestApi.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      barqTestApi.expect(codes, barqTestApi.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    barqTestApi.expect(codes, barqTestApi.isNot(barqTestApi.contains('+1684')));
    barqTestApi.expect(codes, barqTestApi.isNot(barqTestApi.contains('+1340')));
    barqTestApi.expect(codes, barqTestApi.isNot(barqTestApi.contains('+1787')));
  });

  barqTestApi.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    barqTestApi.expect(
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    barqTestApi.expect(
      normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    barqTestApi.expect(normalizeBarqContactPhoneDigits('---'), barqTestApi.isEmpty);
  });

  barqTestApi.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    barqTestApi.expect(searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    barqTestApi.expect(searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    barqTestApi.expect(searchConversationMessages(messages, 'not found'), barqTestApi.isEmpty);
    barqTestApi.expect(searchConversationMessages(messages, '   '), barqTestApi.isEmpty);
  });

  barqTestApi.test('offline sync pauses only for network failures, not one rejected message', () {
    barqTestApi.expect(barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineSyncShouldPause(Exception('Reply target not found')), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineSyncShouldPause(Exception('Message is too long')), barqTestApi.isFalse);
  });

  barqTestApi.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqTestApi.isFalse);
  });

  barqTestApi.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  barqTestApi.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    barqTestApi.expect(
      barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    barqTestApi.expect(
      barqOfflineQueueWithoutExactMessage([accepted], accepted),
      barqTestApi.isEmpty,
    );
  });

  barqTestApi.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, server), queued);
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  barqTestApi.test('offline queue capacity rejects the first item beyond the limit', () {
    barqTestApi.expect(barqOfflineQueueIsFull(0), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineQueueIsFull(199), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineQueueIsFull(200), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineQueueIsFull(201), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineQueueIsFull(3, limit: 3), barqTestApi.isTrue);
  });

  barqTestApi.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    barqTestApi.expect(decodeBarqOfflineQueue(null), barqTestApi.isEmpty);
    barqTestApi.expect(decodeBarqOfflineQueue(''), barqTestApi.isEmpty);
    barqTestApi.expect(decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    barqTestApi.expect(() => decodeBarqOfflineQueue('{bad json'), barqTestApi.throwsFormatException);
    barqTestApi.expect(() => decodeBarqOfflineQueue('{"id":"m1"}'), barqTestApi.throwsFormatException);
    barqTestApi.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, null]'), barqTestApi.throwsFormatException);
    barqTestApi.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), barqTestApi.throwsFormatException);
  });

  barqTestApi.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqTestApi.isFalse);
  });

  barqTestApi.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    barqTestApi.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  barqTestApi.test('message merge deduplicates by id and keeps chronological order', () {
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

    barqTestApi.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    barqTestApi.expect(merged[1]['body'], 'second updated');
  });

  barqTestApi.test('field helper supports API snake_case and camelCase fields', () {
    barqTestApi.expect(field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    barqTestApi.expect(field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  barqTestApi.test('profile photo path is resolved for group payloads with snake_case fields', () {
    barqTestApi.expect(
      profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    barqTestApi.expect(profilePhotoPath({'id': 'without-photo'}), barqTestApi.isEmpty);
    barqTestApi.expect(
      profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  barqTestApi.test('group roles limit promotion to owners and preserve the owner account', () {
    barqTestApi.expect(barqCanManageGroupRoles('owner', targetIsOwner: false), barqTestApi.isTrue);
    barqTestApi.expect(barqCanManageGroupRoles('owner', targetIsOwner: true), barqTestApi.isFalse);
    barqTestApi.expect(barqCanManageGroupRoles('admin', targetIsOwner: false), barqTestApi.isFalse);
    barqTestApi.expect(barqCanManageGroupRoles('member', targetIsOwner: false), barqTestApi.isFalse);
  });

  barqTestApi.test('group removal permissions prevent admins removing peers or owners', () {
    barqTestApi.expect(
      barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      barqTestApi.isFalse,
    );
  });

  barqTestApi.test('only an owner can transfer group ownership to another non-owner member', () {
    barqTestApi.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      barqTestApi.isFalse,
    );
  });

  barqTestApi.test('group members can leave themselves but the owner cannot leave without transfer', () {
    barqTestApi.expect(barqCanLeaveGroup(isSelf: true, isOwner: false), barqTestApi.isTrue);
    barqTestApi.expect(barqCanLeaveGroup(isSelf: true, isOwner: true), barqTestApi.isFalse);
    barqTestApi.expect(barqCanLeaveGroup(isSelf: false, isOwner: false), barqTestApi.isFalse);
  });

  barqTestApi.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    barqTestApi.expect(find.text('الملف الشخصي'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('صديق برق'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('@barq_friend'), barqTestApi.findsNWidgets(2));
    barqTestApi.expect(find.text('+967700000001'), barqTestApi.findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    barqTestApi.expect(find.text('حفظ الرقم في جهات الاتصال'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('إرسال رسالة'), barqTestApi.findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    barqTestApi.expect(sendButton.onPressed, barqTestApi.isNotNull);
  });


  barqTestApi.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    barqTestApi.expect(sendButton.onPressed, barqTestApi.isNull);
  });

  barqTestApi.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    barqTestApi.expect(find.text('عضو المجموعة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('@group_member'), barqTestApi.findsNWidgets(2));
    barqTestApi.expect(find.text('إرسال رسالة'), barqTestApi.findsNothing);
  });

  barqTestApi.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    barqTestApi.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  barqTestApi.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    barqTestApi.expect(find.text('نسخ الرسالة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('حذف الرسالة'), barqTestApi.findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    barqTestApi.expect(find.text('حذف الرسالة؟'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    barqTestApi.expect(deleted, barqTestApi.isTrue);
  });

  barqTestApi.testWidgets('other users message actions do not expose delete', (tester) async {
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
    barqTestApi.expect(find.text('نسخ الرسالة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('حذف الرسالة'), barqTestApi.findsNothing);
  });

  barqTestApi.test('quoted reply preview is bounded and handles attachment references', () {
    barqTestApi.expect(messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    barqTestApi.expect(messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  barqTestApi.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    barqTestApi.expect(find.text('تعديل الرسالة'), barqTestApi.findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    barqTestApi.expect(saved, 'النص الجديد');
  });

  barqTestApi.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    barqTestApi.expect(find.text('الرد على الرسالة'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    barqTestApi.expect(selected?['id'], 'reply-1');
  });


  barqTestApi.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    barqTestApi.expect(normalized, barqTestApi.hasLength(2));
    barqTestApi.expect(normalized.first['emoji'], '❤️');
    barqTestApi.expect(normalized.last['user_id'], 'u2');
    barqTestApi.expect(normalizeMessageReactions(null), barqTestApi.isEmpty);
  });

  barqTestApi.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    barqTestApi.expect(find.text('❤️ 2'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    barqTestApi.expect(selectedEmoji, '❤️');
    barqTestApi.expect(removing, barqTestApi.isTrue);
  });

  barqTestApi.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    barqTestApi.expect(find.text('إضافة تفاعل'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('تثبيت الرسالة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('حفظ في الذكريات الخاصة'), barqTestApi.findsOneWidget);
  });

  barqTestApi.test('media duration formatter supports minute and hour lengths', () {
    barqTestApi.expect(formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    barqTestApi.expect(formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    barqTestApi.expect(formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  barqTestApi.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    barqTestApi.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  barqTestApi.test('message link extraction ignores non-web schemes', () {
    barqTestApi.expect(extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  barqTestApi.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    barqTestApi.expect(requests, 0);
    barqTestApi.expect(find.text('إنشاء الملخص'), barqTestApi.findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    barqTestApi.expect(requests, 1);
    barqTestApi.expect(find.text('ملخص اختباري'), barqTestApi.findsOneWidget);
  });

  barqTestApi.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    barqTestApi.expect(find.text('أدوات المحادثة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('البحث في المحادثة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('الرسائل المثبتة'), barqTestApi.findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    barqTestApi.expect(selectedTool, 'pinned');
  });

  barqTestApi.test('private and group message text share the server 5000-character limit', () {
    barqTestApi.expect(isBarqMessageTextAllowed('رسالة قصيرة'), barqTestApi.isTrue);
    barqTestApi.expect(isBarqMessageTextAllowed('  رسالة قصيرة  '), barqTestApi.isTrue);
    barqTestApi.expect(isBarqMessageTextAllowed(''), barqTestApi.isFalse);
    barqTestApi.expect(isBarqMessageTextAllowed('   '), barqTestApi.isFalse);
    barqTestApi.expect(isBarqMessageTextAllowed(List.filled(5000, 'س').join()), barqTestApi.isTrue);
    barqTestApi.expect(isBarqMessageTextAllowed(List.filled(5001, 'س').join()), barqTestApi.isFalse);
  });

  barqTestApi.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    barqTestApi.expect(barqTranslationRetryAllowed('message-1', retryAfter, now: now), barqTestApi.isFalse);
    barqTestApi.expect(barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), barqTestApi.isTrue);
    barqTestApi.expect(barqTranslationRetryAllowed('message-2', retryAfter, now: now), barqTestApi.isTrue);
    barqTestApi.expect(barqTranslationRetryAllowed('', retryAfter, now: now), barqTestApi.isFalse);
  });

  barqTestApi.test('audio transcription enforces the worker two-megabyte limit', () {
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(0), barqTestApi.isFalse);
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(1), barqTestApi.isTrue);
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), barqTestApi.isTrue);
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), barqTestApi.isFalse);
  });


  barqTestApi.test('SPARK media extensions map to exact supported MIME types', () {
    barqTestApi.expect(barqSparkMediaContentType('jpg'), 'image/jpeg');
    barqTestApi.expect(barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    barqTestApi.expect(barqSparkMediaContentType('png'), 'image/png');
    barqTestApi.expect(barqSparkMediaContentType('webp'), 'image/webp');
    barqTestApi.expect(barqSparkMediaContentType('gif'), 'image/gif');
    barqTestApi.expect(barqSparkMediaContentType('mp4'), 'video/mp4');
    barqTestApi.expect(barqSparkMediaContentType('webm'), 'video/webm');
    barqTestApi.expect(barqSparkMediaContentType('MOV'), 'video/quicktime');
    barqTestApi.expect(barqSparkMediaContentType('exe'), barqTestApi.isNull);
    barqTestApi.expect(barqSparkMediaContentType(''), barqTestApi.isNull);
  });

  barqTestApi.test('SPARK media client size limit rejects empty and oversized files', () {
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(0), barqTestApi.isFalse);
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(1), barqTestApi.isTrue);
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), barqTestApi.isTrue);
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), barqTestApi.isFalse);
  });


  barqTestApi.test('private memory photo uploads continue after an individual failure', () async {
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

    barqTestApi.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    barqTestApi.expect(failures, ['two.png']);
  });

  barqTestApi.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    barqTestApi.expect(find.text('تعذر تحميل ذكرياتك'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    barqTestApi.expect(retried, barqTestApi.isTrue);
  });

  barqTestApi.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    barqTestApi.expect(find.byIcon(Icons.photo_library_outlined), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.byType(PageView), barqTestApi.findsNothing);
    barqTestApi.expect(find.textContaining('/'), barqTestApi.findsNothing);
  });

  barqTestApi.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    barqTestApi.expect(find.byType(PageView), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.byType(InteractiveViewer), barqTestApi.findsWidgets);
    barqTestApi.expect(visiblePage, 0);
    barqTestApi.expect(find.text('1 / 3'), barqTestApi.findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    barqTestApi.expect(visiblePage, 1);
    barqTestApi.expect(find.text('2 / 3'), barqTestApi.findsOneWidget);
  });


  barqTestApi.test('BARQ has exactly the four approved visual identities', () {
    barqTestApi.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  barqTestApi.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    barqTestApi.expect(BarqIdentity.values, barqTestApi.hasLength(4));
    barqTestApi.expect(palettes.map((p) => p.background).toSet().length, 4);
    barqTestApi.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      barqTestApi.expect(palette.text, barqTestApi.isNot(palette.background));
      barqTestApi.expect(palette.primary, barqTestApi.isNot(palette.background));
      barqTestApi.expect(palette.secondary, barqTestApi.isNot(palette.surface));
      barqTestApi.expect(contrastRatio(palette.text, palette.background), barqTestApi.greaterThanOrEqualTo(7));
      barqTestApi.expect(contrastRatio(palette.text, palette.surface), barqTestApi.greaterThanOrEqualTo(7));
      barqTestApi.expect(contrastRatio(palette.mutedText, palette.surface), barqTestApi.greaterThanOrEqualTo(4.5));
      barqTestApi.expect(contrastRatio(palette.primary, palette.surface), barqTestApi.greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    barqTestApi.expect(blue.primary, const Color(0xFFD6AD55));
    barqTestApi.expect(blue.secondary, const Color(0xFF168BFF));
    barqTestApi.expect(blue.background, const Color(0xFF090909));
    barqTestApi.expect(blue.surface, const Color(0xFF171717));
  });

  barqTestApi.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    barqTestApi.expect(normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    barqTestApi.expect(normalizeBarqFcmToken(null), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken(''), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken('   '), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken('token with spaces'), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken(List.filled(4097, 'x').join()), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken(List.filled(4096, 'x').join()), barqTestApi.hasLength(4096));
  });

  barqTestApi.test('foreground push uses generic labels and respects category preferences', () {
    barqTestApi.expect(
      barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    barqTestApi.expect(
      barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    barqTestApi.expect(
      barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    barqTestApi.expect(barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'unknown'}, {}), barqTestApi.isNull);
  });

  barqTestApi.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    barqTestApi.expect(success, barqTestApi.isTrue);
    barqTestApi.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    barqTestApi.expect(noSession, barqTestApi.isFalse);
    barqTestApi.expect(revoked, barqTestApi.isNull);

    final invalidToken = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    barqTestApi.expect(invalidToken, barqTestApi.isFalse);
    barqTestApi.expect(revoked, barqTestApi.isNull);

    final networkFailure = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    barqTestApi.expect(networkFailure, barqTestApi.isFalse);
  });

  barqTestApi.test('FCM registration requires authorized or provisional notification permission', () {
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.authorized), barqTestApi.isTrue);
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.provisional), barqTestApi.isTrue);
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.denied), barqTestApi.isFalse);
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), barqTestApi.isFalse);
  });

}
)));
    barqTestApi.expect(first, barqTestApi.isNot(barqTestApi.contains('967770000000')));
    barqTestApi.expect(barqPrivateRegistrationUsername('+447911123456'), barqTestApi.isNot(first));
  });

  barqTestApi.test('international phone normalization supports Arabic digits and 00 prefix', () {
    barqTestApi.expect(normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    barqTestApi.expect(normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    barqTestApi.expect(normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    barqTestApi.expect(normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    barqTestApi.expect(normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  barqTestApi.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    barqTestApi.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    barqTestApi.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      barqTestApi.expect(codes, barqTestApi.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    barqTestApi.expect(codes, barqTestApi.isNot(barqTestApi.contains('+1684')));
    barqTestApi.expect(codes, barqTestApi.isNot(barqTestApi.contains('+1340')));
    barqTestApi.expect(codes, barqTestApi.isNot(barqTestApi.contains('+1787')));
  });

  barqTestApi.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    barqTestApi.expect(
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    barqTestApi.expect(
      normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    barqTestApi.expect(normalizeBarqContactPhoneDigits('---'), barqTestApi.isEmpty);
  });

  barqTestApi.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    barqTestApi.expect(searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    barqTestApi.expect(searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    barqTestApi.expect(searchConversationMessages(messages, 'not found'), barqTestApi.isEmpty);
    barqTestApi.expect(searchConversationMessages(messages, '   '), barqTestApi.isEmpty);
  });

  barqTestApi.test('offline sync pauses only for network failures, not one rejected message', () {
    barqTestApi.expect(barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineSyncShouldPause(Exception('Reply target not found')), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineSyncShouldPause(Exception('Message is too long')), barqTestApi.isFalse);
  });

  barqTestApi.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqTestApi.isFalse);
  });

  barqTestApi.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  barqTestApi.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    barqTestApi.expect(
      barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    barqTestApi.expect(
      barqOfflineQueueWithoutExactMessage([accepted], accepted),
      barqTestApi.isEmpty,
    );
  });

  barqTestApi.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, server), queued);
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  barqTestApi.test('offline queue capacity rejects the first item beyond the limit', () {
    barqTestApi.expect(barqOfflineQueueIsFull(0), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineQueueIsFull(199), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineQueueIsFull(200), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineQueueIsFull(201), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineQueueIsFull(3, limit: 3), barqTestApi.isTrue);
  });

  barqTestApi.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    barqTestApi.expect(decodeBarqOfflineQueue(null), barqTestApi.isEmpty);
    barqTestApi.expect(decodeBarqOfflineQueue(''), barqTestApi.isEmpty);
    barqTestApi.expect(decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    barqTestApi.expect(() => decodeBarqOfflineQueue('{bad json'), barqTestApi.throwsFormatException);
    barqTestApi.expect(() => decodeBarqOfflineQueue('{"id":"m1"}'), barqTestApi.throwsFormatException);
    barqTestApi.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, null]'), barqTestApi.throwsFormatException);
    barqTestApi.expect(() => decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), barqTestApi.throwsFormatException);
  });

  barqTestApi.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqTestApi.isTrue);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqTestApi.isFalse);
    barqTestApi.expect(barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqTestApi.isFalse);
  });

  barqTestApi.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    barqTestApi.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    barqTestApi.expect(barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  barqTestApi.test('message merge deduplicates by id and keeps chronological order', () {
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

    barqTestApi.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    barqTestApi.expect(merged[1]['body'], 'second updated');
  });

  barqTestApi.test('field helper supports API snake_case and camelCase fields', () {
    barqTestApi.expect(field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    barqTestApi.expect(field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  barqTestApi.test('profile photo path is resolved for group payloads with snake_case fields', () {
    barqTestApi.expect(
      profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    barqTestApi.expect(profilePhotoPath({'id': 'without-photo'}), barqTestApi.isEmpty);
    barqTestApi.expect(
      profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  barqTestApi.test('group roles limit promotion to owners and preserve the owner account', () {
    barqTestApi.expect(barqCanManageGroupRoles('owner', targetIsOwner: false), barqTestApi.isTrue);
    barqTestApi.expect(barqCanManageGroupRoles('owner', targetIsOwner: true), barqTestApi.isFalse);
    barqTestApi.expect(barqCanManageGroupRoles('admin', targetIsOwner: false), barqTestApi.isFalse);
    barqTestApi.expect(barqCanManageGroupRoles('member', targetIsOwner: false), barqTestApi.isFalse);
  });

  barqTestApi.test('group removal permissions prevent admins removing peers or owners', () {
    barqTestApi.expect(
      barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      barqTestApi.isFalse,
    );
  });

  barqTestApi.test('only an owner can transfer group ownership to another non-owner member', () {
    barqTestApi.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isTrue,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      barqTestApi.isFalse,
    );
    barqTestApi.expect(
      barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      barqTestApi.isFalse,
    );
  });

  barqTestApi.test('group members can leave themselves but the owner cannot leave without transfer', () {
    barqTestApi.expect(barqCanLeaveGroup(isSelf: true, isOwner: false), barqTestApi.isTrue);
    barqTestApi.expect(barqCanLeaveGroup(isSelf: true, isOwner: true), barqTestApi.isFalse);
    barqTestApi.expect(barqCanLeaveGroup(isSelf: false, isOwner: false), barqTestApi.isFalse);
  });

  barqTestApi.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    barqTestApi.expect(find.text('الملف الشخصي'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('صديق برق'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('@barq_friend'), barqTestApi.findsNWidgets(2));
    barqTestApi.expect(find.text('+967700000001'), barqTestApi.findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    barqTestApi.expect(find.text('حفظ الرقم في جهات الاتصال'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('إرسال رسالة'), barqTestApi.findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    barqTestApi.expect(sendButton.onPressed, barqTestApi.isNotNull);
  });


  barqTestApi.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    barqTestApi.expect(sendButton.onPressed, barqTestApi.isNull);
  });

  barqTestApi.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    barqTestApi.expect(find.text('عضو المجموعة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('@group_member'), barqTestApi.findsNWidgets(2));
    barqTestApi.expect(find.text('إرسال رسالة'), barqTestApi.findsNothing);
  });

  barqTestApi.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    barqTestApi.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  barqTestApi.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    barqTestApi.expect(find.text('نسخ الرسالة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('حذف الرسالة'), barqTestApi.findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    barqTestApi.expect(find.text('حذف الرسالة؟'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    barqTestApi.expect(deleted, barqTestApi.isTrue);
  });

  barqTestApi.testWidgets('other users message actions do not expose delete', (tester) async {
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
    barqTestApi.expect(find.text('نسخ الرسالة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('حذف الرسالة'), barqTestApi.findsNothing);
  });

  barqTestApi.test('quoted reply preview is bounded and handles attachment references', () {
    barqTestApi.expect(messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    barqTestApi.expect(messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    barqTestApi.expect(messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  barqTestApi.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    barqTestApi.expect(find.text('تعديل الرسالة'), barqTestApi.findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    barqTestApi.expect(saved, 'النص الجديد');
  });

  barqTestApi.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    barqTestApi.expect(find.text('الرد على الرسالة'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    barqTestApi.expect(selected?['id'], 'reply-1');
  });


  barqTestApi.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    barqTestApi.expect(normalized, barqTestApi.hasLength(2));
    barqTestApi.expect(normalized.first['emoji'], '❤️');
    barqTestApi.expect(normalized.last['user_id'], 'u2');
    barqTestApi.expect(normalizeMessageReactions(null), barqTestApi.isEmpty);
  });

  barqTestApi.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    barqTestApi.expect(find.text('❤️ 2'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    barqTestApi.expect(selectedEmoji, '❤️');
    barqTestApi.expect(removing, barqTestApi.isTrue);
  });

  barqTestApi.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    barqTestApi.expect(find.text('إضافة تفاعل'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('تثبيت الرسالة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('حفظ في الذكريات الخاصة'), barqTestApi.findsOneWidget);
  });

  barqTestApi.test('media duration formatter supports minute and hour lengths', () {
    barqTestApi.expect(formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    barqTestApi.expect(formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    barqTestApi.expect(formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  barqTestApi.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    barqTestApi.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  barqTestApi.test('message link extraction ignores non-web schemes', () {
    barqTestApi.expect(extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  barqTestApi.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    barqTestApi.expect(requests, 0);
    barqTestApi.expect(find.text('إنشاء الملخص'), barqTestApi.findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    barqTestApi.expect(requests, 1);
    barqTestApi.expect(find.text('ملخص اختباري'), barqTestApi.findsOneWidget);
  });

  barqTestApi.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    barqTestApi.expect(find.text('أدوات المحادثة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('البحث في المحادثة'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.text('الرسائل المثبتة'), barqTestApi.findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    barqTestApi.expect(selectedTool, 'pinned');
  });

  barqTestApi.test('private and group message text share the server 5000-character limit', () {
    barqTestApi.expect(isBarqMessageTextAllowed('رسالة قصيرة'), barqTestApi.isTrue);
    barqTestApi.expect(isBarqMessageTextAllowed('  رسالة قصيرة  '), barqTestApi.isTrue);
    barqTestApi.expect(isBarqMessageTextAllowed(''), barqTestApi.isFalse);
    barqTestApi.expect(isBarqMessageTextAllowed('   '), barqTestApi.isFalse);
    barqTestApi.expect(isBarqMessageTextAllowed(List.filled(5000, 'س').join()), barqTestApi.isTrue);
    barqTestApi.expect(isBarqMessageTextAllowed(List.filled(5001, 'س').join()), barqTestApi.isFalse);
  });

  barqTestApi.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    barqTestApi.expect(barqTranslationRetryAllowed('message-1', retryAfter, now: now), barqTestApi.isFalse);
    barqTestApi.expect(barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), barqTestApi.isTrue);
    barqTestApi.expect(barqTranslationRetryAllowed('message-2', retryAfter, now: now), barqTestApi.isTrue);
    barqTestApi.expect(barqTranslationRetryAllowed('', retryAfter, now: now), barqTestApi.isFalse);
  });

  barqTestApi.test('audio transcription enforces the worker two-megabyte limit', () {
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(0), barqTestApi.isFalse);
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(1), barqTestApi.isTrue);
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), barqTestApi.isTrue);
    barqTestApi.expect(isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), barqTestApi.isFalse);
  });


  barqTestApi.test('SPARK media extensions map to exact supported MIME types', () {
    barqTestApi.expect(barqSparkMediaContentType('jpg'), 'image/jpeg');
    barqTestApi.expect(barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    barqTestApi.expect(barqSparkMediaContentType('png'), 'image/png');
    barqTestApi.expect(barqSparkMediaContentType('webp'), 'image/webp');
    barqTestApi.expect(barqSparkMediaContentType('gif'), 'image/gif');
    barqTestApi.expect(barqSparkMediaContentType('mp4'), 'video/mp4');
    barqTestApi.expect(barqSparkMediaContentType('webm'), 'video/webm');
    barqTestApi.expect(barqSparkMediaContentType('MOV'), 'video/quicktime');
    barqTestApi.expect(barqSparkMediaContentType('exe'), barqTestApi.isNull);
    barqTestApi.expect(barqSparkMediaContentType(''), barqTestApi.isNull);
  });

  barqTestApi.test('SPARK media client size limit rejects empty and oversized files', () {
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(0), barqTestApi.isFalse);
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(1), barqTestApi.isTrue);
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), barqTestApi.isTrue);
    barqTestApi.expect(isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), barqTestApi.isFalse);
  });


  barqTestApi.test('private memory photo uploads continue after an individual failure', () async {
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

    barqTestApi.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    barqTestApi.expect(failures, ['two.png']);
  });

  barqTestApi.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    barqTestApi.expect(find.text('تعذر تحميل ذكرياتك'), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), barqTestApi.findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    barqTestApi.expect(retried, barqTestApi.isTrue);
  });

  barqTestApi.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    barqTestApi.expect(find.byIcon(Icons.photo_library_outlined), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.byType(PageView), barqTestApi.findsNothing);
    barqTestApi.expect(find.textContaining('/'), barqTestApi.findsNothing);
  });

  barqTestApi.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    barqTestApi.expect(find.byType(PageView), barqTestApi.findsOneWidget);
    barqTestApi.expect(find.byType(InteractiveViewer), barqTestApi.findsWidgets);
    barqTestApi.expect(visiblePage, 0);
    barqTestApi.expect(find.text('1 / 3'), barqTestApi.findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    barqTestApi.expect(visiblePage, 1);
    barqTestApi.expect(find.text('2 / 3'), barqTestApi.findsOneWidget);
  });


  barqTestApi.test('BARQ has exactly the four approved visual identities', () {
    barqTestApi.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    barqTestApi.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  barqTestApi.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    barqTestApi.expect(BarqIdentity.values, barqTestApi.hasLength(4));
    barqTestApi.expect(palettes.map((p) => p.background).toSet().length, 4);
    barqTestApi.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      barqTestApi.expect(palette.text, barqTestApi.isNot(palette.background));
      barqTestApi.expect(palette.primary, barqTestApi.isNot(palette.background));
      barqTestApi.expect(palette.secondary, barqTestApi.isNot(palette.surface));
      barqTestApi.expect(contrastRatio(palette.text, palette.background), barqTestApi.greaterThanOrEqualTo(7));
      barqTestApi.expect(contrastRatio(palette.text, palette.surface), barqTestApi.greaterThanOrEqualTo(7));
      barqTestApi.expect(contrastRatio(palette.mutedText, palette.surface), barqTestApi.greaterThanOrEqualTo(4.5));
      barqTestApi.expect(contrastRatio(palette.primary, palette.surface), barqTestApi.greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    barqTestApi.expect(blue.primary, const Color(0xFFD6AD55));
    barqTestApi.expect(blue.secondary, const Color(0xFF168BFF));
    barqTestApi.expect(blue.background, const Color(0xFF090909));
    barqTestApi.expect(blue.surface, const Color(0xFF171717));
  });

  barqTestApi.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    barqTestApi.expect(normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    barqTestApi.expect(normalizeBarqFcmToken(null), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken(''), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken('   '), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken('token with spaces'), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken(List.filled(4097, 'x').join()), barqTestApi.isNull);
    barqTestApi.expect(normalizeBarqFcmToken(List.filled(4096, 'x').join()), barqTestApi.hasLength(4096));
  });

  barqTestApi.test('foreground push uses generic labels and respects category preferences', () {
    barqTestApi.expect(
      barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    barqTestApi.expect(
      barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    barqTestApi.expect(
      barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    barqTestApi.expect(barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), barqTestApi.isNull);
    barqTestApi.expect(barqForegroundPushLabel({'type': 'unknown'}, {}), barqTestApi.isNull);
  });

  barqTestApi.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    barqTestApi.expect(success, barqTestApi.isTrue);
    barqTestApi.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    barqTestApi.expect(noSession, barqTestApi.isFalse);
    barqTestApi.expect(revoked, barqTestApi.isNull);

    final invalidToken = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    barqTestApi.expect(invalidToken, barqTestApi.isFalse);
    barqTestApi.expect(revoked, barqTestApi.isNull);

    final networkFailure = await revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    barqTestApi.expect(networkFailure, barqTestApi.isFalse);
  });

  barqTestApi.test('FCM registration requires authorized or provisional notification permission', () {
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.authorized), barqTestApi.isTrue);
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.provisional), barqTestApi.isTrue);
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.denied), barqTestApi.isFalse);
    barqTestApi.expect(barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), barqTestApi.isFalse);
  });

}
