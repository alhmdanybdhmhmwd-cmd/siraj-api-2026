import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as _flutterTest;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart' as barqApp;

void main() {
  _flutterTest.test('optional realtime connects only with a session, endpoint and resumed app', () {
    _flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), _flutterTest.isFalse);
  });

  _flutterTest.test('realtime events refresh only the matching direct conversation', () {
    _flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      _flutterTest.isFalse,
    );
  });

  _flutterTest.test('notification tap routing validates private chat, group and SPARK destinations', () {
    _flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    _flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    _flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    _flutterTest.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    _flutterTest.expect(barqApp.barqNotificationRouteFromData({'type': 'direct_message'}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), _flutterTest.isNull);
  });

  _flutterTest.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), _flutterTest.isNull);
  });

  _flutterTest.test('Nearby requests only permissions supported by the Android API level', () {
    _flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    _flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    _flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    _flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    _flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    _flutterTest.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    _flutterTest.expect(barqApp.barqNearbyRequiresLocationService(30), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqNearbyRequiresLocationService(32), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqNearbyRequiresLocationService(33), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqNearbyRequiresLocationService(37), _flutterTest.isFalse);
  });

  _flutterTest.test('Nearby payload transfer treats failure and cancellation as failed', () {
    _flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.NONE), _flutterTest.isFalse);
  });

  _flutterTest.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    _flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), _flutterTest.isFalse);
  });

  _flutterTest.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), _flutterTest.isFalse);
  });

  _flutterTest.test('registration sends a stable private username without exposing the phone', () {
    final first = barqApp.barqPrivateRegistrationUsername('+967770000000');
    final second = barqApp.barqPrivateRegistrationUsername('+967770000000');
    _flutterTest.expect(first, second);
    _flutterTest.expect(first, _flutterTest.matches(RegExp(r'^barq[a-f0-9]{16}$')));
    _flutterTest.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    _flutterTest.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  _flutterTest.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    _flutterTest.expect(barqApp.barqCountryCodes.length, 206);
    final codes = barqApp.barqCountryCodes.map((country) => country.$2).toSet();
    _flutterTest.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      _flutterTest.expect(codes, _flutterTest.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    _flutterTest.expect(codes, _flutterTest.isNot(_flutterTest.contains('+1684')));
    _flutterTest.expect(codes, _flutterTest.isNot(_flutterTest.contains('+1340')));
    _flutterTest.expect(codes, _flutterTest.isNot(_flutterTest.contains('+1787')));
  });

  _flutterTest.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    _flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    _flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    _flutterTest.expect(barqApp.normalizeBarqContactPhoneDigits('---'), _flutterTest.isEmpty);
  });

  _flutterTest.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    _flutterTest.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    _flutterTest.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    _flutterTest.expect(barqApp.searchConversationMessages(messages, 'not found'), _flutterTest.isEmpty);
    _flutterTest.expect(barqApp.searchConversationMessages(messages, '   '), _flutterTest.isEmpty);
  });

  _flutterTest.test('offline sync pauses only for network failures, not one rejected message', () {
    _flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), _flutterTest.isFalse);
  });

  _flutterTest.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), _flutterTest.isFalse);
  });

  _flutterTest.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  _flutterTest.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    _flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    _flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      _flutterTest.isEmpty,
    );
  });

  _flutterTest.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  _flutterTest.test('offline queue capacity rejects the first item beyond the limit', () {
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(0), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(199), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(200), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(201), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), _flutterTest.isTrue);
  });

  _flutterTest.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    _flutterTest.expect(barqApp.decodeBarqOfflineQueue(null), _flutterTest.isEmpty);
    _flutterTest.expect(barqApp.decodeBarqOfflineQueue(''), _flutterTest.isEmpty);
    _flutterTest.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  _flutterTest.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), _flutterTest.isFalse);
  });

  _flutterTest.test('offline queue reconciliation removes exact _flutterTest.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    _flutterTest.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), _flutterTest.same(queued));
  });

  _flutterTest.test('message merge deduplicates by id and keeps chronological order', () {
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

    _flutterTest.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    _flutterTest.expect(merged[1]['body'], 'second updated');
  });

  _flutterTest.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    _flutterTest.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    _flutterTest.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  _flutterTest.test('profile photo path is resolved for group payloads with snake_case fields', () {
    _flutterTest.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    _flutterTest.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), _flutterTest.isEmpty);
    _flutterTest.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  _flutterTest.test('group roles limit promotion to owners and preserve the owner account', () {
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), _flutterTest.isFalse);
  });

  _flutterTest.test('group removal permissions prevent admins removing peers or owners', () {
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      _flutterTest.isFalse,
    );
  });

  _flutterTest.test('only an owner can transfer group ownership to another non-owner member', () {
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      _flutterTest.isFalse,
    );
  });

  _flutterTest.test('group members can leave themselves but the owner cannot leave without transfer', () {
    _flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), _flutterTest.isFalse);
  });

  _flutterTest.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    _flutterTest.expect(find.text('الملف الشخصي'), findsOneWidget);
    _flutterTest.expect(find.text('صديق برق'), findsOneWidget);
    _flutterTest.expect(find.text('@barq_friend'), findsNWidgets(2));
    _flutterTest.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    _flutterTest.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    _flutterTest.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    _flutterTest.expect(sendButton.onPressed, _flutterTest.isNotNull);
  });


  _flutterTest.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    _flutterTest.expect(sendButton.onPressed, _flutterTest.isNull);
  });

  _flutterTest.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    _flutterTest.expect(find.text('عضو المجموعة'), findsOneWidget);
    _flutterTest.expect(find.text('@group_member'), findsNWidgets(2));
    _flutterTest.expect(find.text('إرسال رسالة'), findsNothing);
  });

  _flutterTest.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    _flutterTest.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  _flutterTest.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    _flutterTest.expect(find.text('نسخ الرسالة'), findsOneWidget);
    _flutterTest.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    _flutterTest.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    _flutterTest.expect(deleted, _flutterTest.isTrue);
  });

  _flutterTest.testWidgets('other users message actions do not expose delete', (tester) async {
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
    _flutterTest.expect(find.text('نسخ الرسالة'), findsOneWidget);
    _flutterTest.expect(find.text('حذف الرسالة'), findsNothing);
  });

  _flutterTest.test('quoted reply preview is bounded and handles attachment references', () {
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  _flutterTest.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    _flutterTest.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    _flutterTest.expect(saved, 'النص الجديد');
  });

  _flutterTest.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    _flutterTest.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    _flutterTest.expect(selected?['id'], 'reply-1');
  });


  _flutterTest.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    _flutterTest.expect(normalized, _flutterTest.hasLength(2));
    _flutterTest.expect(normalized.first['emoji'], '❤️');
    _flutterTest.expect(normalized.last['user_id'], 'u2');
    _flutterTest.expect(barqApp.normalizeMessageReactions(null), _flutterTest.isEmpty);
  });

  _flutterTest.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    _flutterTest.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    _flutterTest.expect(selectedEmoji, '❤️');
    _flutterTest.expect(removing, _flutterTest.isTrue);
  });

  _flutterTest.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    _flutterTest.expect(find.text('إضافة تفاعل'), findsOneWidget);
    _flutterTest.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    _flutterTest.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  _flutterTest.test('media duration formatter supports minute and hour lengths', () {
    _flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    _flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    _flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  _flutterTest.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    _flutterTest.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  _flutterTest.test('message link extraction ignores non-web schemes', () {
    _flutterTest.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  _flutterTest.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    _flutterTest.expect(requests, 0);
    _flutterTest.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    _flutterTest.expect(requests, 1);
    _flutterTest.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  _flutterTest.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    _flutterTest.expect(find.text('أدوات المحادثة'), findsOneWidget);
    _flutterTest.expect(find.text('البحث في المحادثة'), findsOneWidget);
    _flutterTest.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    _flutterTest.expect(selectedTool, 'pinned');
  });

  _flutterTest.test('private and group message text share the server 5000-character limit', () {
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed(''), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed('   '), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), _flutterTest.isFalse);
  });

  _flutterTest.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), _flutterTest.isFalse);
  });

  _flutterTest.test('audio transcription enforces the worker two-megabyte limit', () {
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(0), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(1), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), _flutterTest.isFalse);
  });


  _flutterTest.test('SPARK media extensions map to exact supported MIME types', () {
    _flutterTest.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('exe'), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqSparkMediaContentType(''), _flutterTest.isNull);
  });

  _flutterTest.test('SPARK media client size limit rejects empty and oversized files', () {
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(0), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(1), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), _flutterTest.isFalse);
  });


  _flutterTest.test('private memory photo uploads continue after an individual failure', () async {
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

    _flutterTest.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    _flutterTest.expect(failures, ['two.png']);
  });

  _flutterTest.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    _flutterTest.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    _flutterTest.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    _flutterTest.expect(retried, _flutterTest.isTrue);
  });

  _flutterTest.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    _flutterTest.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    _flutterTest.expect(find.byType(PageView), findsNothing);
    _flutterTest.expect(find.textContaining('/'), findsNothing);
  });

  _flutterTest.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    _flutterTest.expect(find.byType(PageView), findsOneWidget);
    _flutterTest.expect(find.byType(InteractiveViewer), findsWidgets);
    _flutterTest.expect(visiblePage, 0);
    _flutterTest.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    _flutterTest.expect(visiblePage, 1);
    _flutterTest.expect(find.text('2 / 3'), findsOneWidget);
  });


  _flutterTest.test('BARQ has exactly the four approved visual identities', () {
    _flutterTest.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  _flutterTest.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    _flutterTest.expect(BarqIdentity.values, _flutterTest.hasLength(4));
    _flutterTest.expect(palettes.map((p) => p.background).toSet().length, 4);
    _flutterTest.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      _flutterTest.expect(palette.text, _flutterTest.isNot(palette.background));
      _flutterTest.expect(palette.primary, _flutterTest.isNot(palette.background));
      _flutterTest.expect(palette.secondary, _flutterTest.isNot(palette.surface));
      _flutterTest.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      _flutterTest.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      _flutterTest.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      _flutterTest.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    _flutterTest.expect(blue.primary, const Color(0xFFD6AD55));
    _flutterTest.expect(blue.secondary, const Color(0xFF168BFF));
    _flutterTest.expect(blue.background, const Color(0xFF090909));
    _flutterTest.expect(blue.surface, const Color(0xFF171717));
  });

  _flutterTest.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    _flutterTest.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(null), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(''), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken('   '), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken('token with spaces'), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), _flutterTest.hasLength(4096));
  });

  _flutterTest.test('foreground push uses generic labels and respects category preferences', () {
    _flutterTest.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    _flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    _flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), _flutterTest.isNull);
  });

  _flutterTest.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    _flutterTest.expect(success, _flutterTest.isTrue);
    _flutterTest.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    _flutterTest.expect(noSession, _flutterTest.isFalse);
    _flutterTest.expect(revoked, _flutterTest.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    _flutterTest.expect(invalidToken, _flutterTest.isFalse);
    _flutterTest.expect(revoked, _flutterTest.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    _flutterTest.expect(networkFailure, _flutterTest.isFalse);
  });

  _flutterTest.test('FCM registration requires authorized or provisional notification permission', () {
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), _flutterTest.isFalse);
  });

}
)));
    _flutterTest.expect(first, _flutterTest.isNot(_flutterTest.contains('967770000000')));
    _flutterTest.expect(barqApp.barqPrivateRegistrationUsername('+447911123456'), _flutterTest.isNot(first));
  });

  _flutterTest.test('international phone normalization supports Arabic digits and 00 prefix', () {
    _flutterTest.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    _flutterTest.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    _flutterTest.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  _flutterTest.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    _flutterTest.expect(barqApp.barqCountryCodes.length, 206);
    final codes = barqApp.barqCountryCodes.map((country) => country.$2).toSet();
    _flutterTest.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      _flutterTest.expect(codes, _flutterTest.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    _flutterTest.expect(codes, _flutterTest.isNot(_flutterTest.contains('+1684')));
    _flutterTest.expect(codes, _flutterTest.isNot(_flutterTest.contains('+1340')));
    _flutterTest.expect(codes, _flutterTest.isNot(_flutterTest.contains('+1787')));
  });

  _flutterTest.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    _flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    _flutterTest.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    _flutterTest.expect(barqApp.normalizeBarqContactPhoneDigits('---'), _flutterTest.isEmpty);
  });

  _flutterTest.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    _flutterTest.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    _flutterTest.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    _flutterTest.expect(barqApp.searchConversationMessages(messages, 'not found'), _flutterTest.isEmpty);
    _flutterTest.expect(barqApp.searchConversationMessages(messages, '   '), _flutterTest.isEmpty);
  });

  _flutterTest.test('offline sync pauses only for network failures, not one rejected message', () {
    _flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), _flutterTest.isFalse);
  });

  _flutterTest.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), _flutterTest.isFalse);
  });

  _flutterTest.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  _flutterTest.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    _flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    _flutterTest.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      _flutterTest.isEmpty,
    );
  });

  _flutterTest.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  _flutterTest.test('offline queue capacity rejects the first item beyond the limit', () {
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(0), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(199), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(200), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(201), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), _flutterTest.isTrue);
  });

  _flutterTest.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    _flutterTest.expect(barqApp.decodeBarqOfflineQueue(null), _flutterTest.isEmpty);
    _flutterTest.expect(barqApp.decodeBarqOfflineQueue(''), _flutterTest.isEmpty);
    _flutterTest.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    _flutterTest.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  _flutterTest.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), _flutterTest.isFalse);
  });

  _flutterTest.test('offline queue reconciliation removes exact _flutterTest.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    _flutterTest.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    _flutterTest.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), _flutterTest.same(queued));
  });

  _flutterTest.test('message merge deduplicates by id and keeps chronological order', () {
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

    _flutterTest.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    _flutterTest.expect(merged[1]['body'], 'second updated');
  });

  _flutterTest.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    _flutterTest.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    _flutterTest.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  _flutterTest.test('profile photo path is resolved for group payloads with snake_case fields', () {
    _flutterTest.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    _flutterTest.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), _flutterTest.isEmpty);
    _flutterTest.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  _flutterTest.test('group roles limit promotion to owners and preserve the owner account', () {
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), _flutterTest.isFalse);
  });

  _flutterTest.test('group removal permissions prevent admins removing peers or owners', () {
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      _flutterTest.isFalse,
    );
  });

  _flutterTest.test('only an owner can transfer group ownership to another non-owner member', () {
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isTrue,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      _flutterTest.isFalse,
    );
    _flutterTest.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      _flutterTest.isFalse,
    );
  });

  _flutterTest.test('group members can leave themselves but the owner cannot leave without transfer', () {
    _flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), _flutterTest.isFalse);
  });

  _flutterTest.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    _flutterTest.expect(find.text('الملف الشخصي'), findsOneWidget);
    _flutterTest.expect(find.text('صديق برق'), findsOneWidget);
    _flutterTest.expect(find.text('@barq_friend'), findsNWidgets(2));
    _flutterTest.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    _flutterTest.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    _flutterTest.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    _flutterTest.expect(sendButton.onPressed, _flutterTest.isNotNull);
  });


  _flutterTest.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    _flutterTest.expect(sendButton.onPressed, _flutterTest.isNull);
  });

  _flutterTest.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    _flutterTest.expect(find.text('عضو المجموعة'), findsOneWidget);
    _flutterTest.expect(find.text('@group_member'), findsNWidgets(2));
    _flutterTest.expect(find.text('إرسال رسالة'), findsNothing);
  });

  _flutterTest.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    _flutterTest.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  _flutterTest.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    _flutterTest.expect(find.text('نسخ الرسالة'), findsOneWidget);
    _flutterTest.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    _flutterTest.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    _flutterTest.expect(deleted, _flutterTest.isTrue);
  });

  _flutterTest.testWidgets('other users message actions do not expose delete', (tester) async {
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
    _flutterTest.expect(find.text('نسخ الرسالة'), findsOneWidget);
    _flutterTest.expect(find.text('حذف الرسالة'), findsNothing);
  });

  _flutterTest.test('quoted reply preview is bounded and handles attachment references', () {
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    _flutterTest.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  _flutterTest.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    _flutterTest.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    _flutterTest.expect(saved, 'النص الجديد');
  });

  _flutterTest.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    _flutterTest.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    _flutterTest.expect(selected?['id'], 'reply-1');
  });


  _flutterTest.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    _flutterTest.expect(normalized, _flutterTest.hasLength(2));
    _flutterTest.expect(normalized.first['emoji'], '❤️');
    _flutterTest.expect(normalized.last['user_id'], 'u2');
    _flutterTest.expect(barqApp.normalizeMessageReactions(null), _flutterTest.isEmpty);
  });

  _flutterTest.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    _flutterTest.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    _flutterTest.expect(selectedEmoji, '❤️');
    _flutterTest.expect(removing, _flutterTest.isTrue);
  });

  _flutterTest.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    _flutterTest.expect(find.text('إضافة تفاعل'), findsOneWidget);
    _flutterTest.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    _flutterTest.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  _flutterTest.test('media duration formatter supports minute and hour lengths', () {
    _flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    _flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    _flutterTest.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  _flutterTest.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    _flutterTest.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  _flutterTest.test('message link extraction ignores non-web schemes', () {
    _flutterTest.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  _flutterTest.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    _flutterTest.expect(requests, 0);
    _flutterTest.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    _flutterTest.expect(requests, 1);
    _flutterTest.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  _flutterTest.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    _flutterTest.expect(find.text('أدوات المحادثة'), findsOneWidget);
    _flutterTest.expect(find.text('البحث في المحادثة'), findsOneWidget);
    _flutterTest.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    _flutterTest.expect(selectedTool, 'pinned');
  });

  _flutterTest.test('private and group message text share the server 5000-character limit', () {
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed(''), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed('   '), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), _flutterTest.isFalse);
  });

  _flutterTest.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), _flutterTest.isFalse);
  });

  _flutterTest.test('audio transcription enforces the worker two-megabyte limit', () {
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(0), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(1), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), _flutterTest.isFalse);
  });


  _flutterTest.test('SPARK media extensions map to exact supported MIME types', () {
    _flutterTest.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    _flutterTest.expect(barqApp.barqSparkMediaContentType('exe'), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqSparkMediaContentType(''), _flutterTest.isNull);
  });

  _flutterTest.test('SPARK media client size limit rejects empty and oversized files', () {
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(0), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(1), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), _flutterTest.isFalse);
  });


  _flutterTest.test('private memory photo uploads continue after an individual failure', () async {
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

    _flutterTest.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    _flutterTest.expect(failures, ['two.png']);
  });

  _flutterTest.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    _flutterTest.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    _flutterTest.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    _flutterTest.expect(retried, _flutterTest.isTrue);
  });

  _flutterTest.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    _flutterTest.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    _flutterTest.expect(find.byType(PageView), findsNothing);
    _flutterTest.expect(find.textContaining('/'), findsNothing);
  });

  _flutterTest.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    _flutterTest.expect(find.byType(PageView), findsOneWidget);
    _flutterTest.expect(find.byType(InteractiveViewer), findsWidgets);
    _flutterTest.expect(visiblePage, 0);
    _flutterTest.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    _flutterTest.expect(visiblePage, 1);
    _flutterTest.expect(find.text('2 / 3'), findsOneWidget);
  });


  _flutterTest.test('BARQ has exactly the four approved visual identities', () {
    _flutterTest.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    _flutterTest.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  _flutterTest.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    _flutterTest.expect(BarqIdentity.values, _flutterTest.hasLength(4));
    _flutterTest.expect(palettes.map((p) => p.background).toSet().length, 4);
    _flutterTest.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      _flutterTest.expect(palette.text, _flutterTest.isNot(palette.background));
      _flutterTest.expect(palette.primary, _flutterTest.isNot(palette.background));
      _flutterTest.expect(palette.secondary, _flutterTest.isNot(palette.surface));
      _flutterTest.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      _flutterTest.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      _flutterTest.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      _flutterTest.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    _flutterTest.expect(blue.primary, const Color(0xFFD6AD55));
    _flutterTest.expect(blue.secondary, const Color(0xFF168BFF));
    _flutterTest.expect(blue.background, const Color(0xFF090909));
    _flutterTest.expect(blue.surface, const Color(0xFF171717));
  });

  _flutterTest.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    _flutterTest.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(null), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(''), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken('   '), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken('token with spaces'), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), _flutterTest.isNull);
    _flutterTest.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), _flutterTest.hasLength(4096));
  });

  _flutterTest.test('foreground push uses generic labels and respects category preferences', () {
    _flutterTest.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    _flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    _flutterTest.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), _flutterTest.isNull);
    _flutterTest.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), _flutterTest.isNull);
  });

  _flutterTest.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    _flutterTest.expect(success, _flutterTest.isTrue);
    _flutterTest.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    _flutterTest.expect(noSession, _flutterTest.isFalse);
    _flutterTest.expect(revoked, _flutterTest.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    _flutterTest.expect(invalidToken, _flutterTest.isFalse);
    _flutterTest.expect(revoked, _flutterTest.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    _flutterTest.expect(networkFailure, _flutterTest.isFalse);
  });

  _flutterTest.test('FCM registration requires authorized or provisional notification permission', () {
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), _flutterTest.isTrue);
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), _flutterTest.isFalse);
    _flutterTest.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), _flutterTest.isFalse);
  });

}
