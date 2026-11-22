import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as flutterTesting2026x9;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart' as barqApp;
import 'package:barq/barq_identity.dart' as barqIdentity;

void main() {
  flutterTesting2026x9.test('optional realtime connects only with a session, endpoint and resumed app', () {
    flutterTesting2026x9.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('realtime events refresh only the matching direct conversation', () {
    flutterTesting2026x9.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      flutterTesting2026x9.isFalse,
    );
  });

  flutterTesting2026x9.test('notification tap routing validates private chat, group and SPARK destinations', () {
    flutterTesting2026x9.expect(
      barqApp.barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    flutterTesting2026x9.expect(
      barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    flutterTesting2026x9.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    flutterTesting2026x9.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    flutterTesting2026x9.expect(barqApp.barqNotificationRouteFromData({'type': 'direct_message'}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.test('Nearby requests only permissions supported by the Android API level', () {
    flutterTesting2026x9.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    flutterTesting2026x9.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    flutterTesting2026x9.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    flutterTesting2026x9.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    flutterTesting2026x9.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    flutterTesting2026x9.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    flutterTesting2026x9.expect(barqApp.barqNearbyRequiresLocationService(30), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqNearbyRequiresLocationService(32), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqNearbyRequiresLocationService(33), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqNearbyRequiresLocationService(37), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('Nearby payload transfer treats failure and cancellation as failed', () {
    flutterTesting2026x9.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.NONE), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('registration sends a stable private username without exposing the phone', () {
    final first = barqApp.barqPrivateRegistrationUsername('+967770000000');
    final second = barqApp.barqPrivateRegistrationUsername('+967770000000');
    flutterTesting2026x9.expect(first, second);
    flutterTesting2026x9.expect(first, flutterTesting2026x9.matches(RegExp(r'^barq[a-f0-9]{16}$')));
    flutterTesting2026x9.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    flutterTesting2026x9.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  flutterTesting2026x9.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    flutterTesting2026x9.expect(barqIdentity.barqCountryCodes.length, 206);
    final codes = barqIdentity.barqCountryCodes.map((country) => country.$2).toSet();
    flutterTesting2026x9.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      flutterTesting2026x9.expect(codes, flutterTesting2026x9.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    flutterTesting2026x9.expect(codes, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('+1684')));
    flutterTesting2026x9.expect(codes, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('+1340')));
    flutterTesting2026x9.expect(codes, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('+1787')));
  });

  flutterTesting2026x9.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    flutterTesting2026x9.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    flutterTesting2026x9.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    flutterTesting2026x9.expect(barqApp.normalizeBarqContactPhoneDigits('---'), flutterTesting2026x9.isEmpty);
  });

  flutterTesting2026x9.test('conversation search flutterTesting2026x9.matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, 'not found'), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, '   '), flutterTesting2026x9.isEmpty);
  });

  flutterTesting2026x9.test('offline sync pauses only for network failures, not one rejected message', () {
    flutterTesting2026x9.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  flutterTesting2026x9.test('accepted outbox removal preserves a flutterTesting2026x9.same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    flutterTesting2026x9.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    flutterTesting2026x9.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      flutterTesting2026x9.isEmpty,
    );
  });

  flutterTesting2026x9.test('offline reconciliation keeps a flutterTesting2026x9.same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  flutterTesting2026x9.test('offline queue capacity rejects the first item beyond the limit', () {
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(0), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(199), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(200), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(201), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    flutterTesting2026x9.expect(barqApp.decodeBarqOfflineQueue(null), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(barqApp.decodeBarqOfflineQueue(''), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  flutterTesting2026x9.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('offline queue reconciliation removes exact flutterTesting2026x9.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    flutterTesting2026x9.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), flutterTesting2026x9.same(queued));
  });

  flutterTesting2026x9.test('message merge deduplicates by id and keeps chronological order', () {
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

    flutterTesting2026x9.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    flutterTesting2026x9.expect(merged[1]['body'], 'second updated');
  });

  flutterTesting2026x9.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    flutterTesting2026x9.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    flutterTesting2026x9.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  flutterTesting2026x9.test('profile photo path is resolved for group payloads with snake_case fields', () {
    flutterTesting2026x9.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    flutterTesting2026x9.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  flutterTesting2026x9.test('group roles limit promotion to owners and preserve the owner account', () {
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('group removal permissions prevent admins removing peers or owners', () {
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      flutterTesting2026x9.isFalse,
    );
  });

  flutterTesting2026x9.test('only an owner can transfer group ownership to another non-owner member', () {
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      flutterTesting2026x9.isFalse,
    );
  });

  flutterTesting2026x9.test('group members can leave themselves but the owner cannot leave without transfer', () {
    flutterTesting2026x9.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    flutterTesting2026x9.expect(find.text('الملف الشخصي'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('صديق برق'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('@barq_friend'), findsNWidgets(2));
    flutterTesting2026x9.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    flutterTesting2026x9.expect(sendButton.onPressed, flutterTesting2026x9.isNotNull);
  });


  flutterTesting2026x9.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    flutterTesting2026x9.expect(sendButton.onPressed, flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    flutterTesting2026x9.expect(find.text('عضو المجموعة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('@group_member'), findsNWidgets(2));
    flutterTesting2026x9.expect(find.text('إرسال رسالة'), findsNothing);
  });

  flutterTesting2026x9.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    flutterTesting2026x9.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  flutterTesting2026x9.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    flutterTesting2026x9.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(deleted, flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.testWidgets('other users message actions do not expose delete', (tester) async {
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
    flutterTesting2026x9.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('حذف الرسالة'), findsNothing);
  });

  flutterTesting2026x9.test('quoted reply preview is bounded and handles attachment references', () {
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  flutterTesting2026x9.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    flutterTesting2026x9.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(saved, 'النص الجديد');
  });

  flutterTesting2026x9.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    flutterTesting2026x9.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(selected?['id'], 'reply-1');
  });


  flutterTesting2026x9.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    flutterTesting2026x9.expect(normalized, flutterTesting2026x9.hasLength(2));
    flutterTesting2026x9.expect(normalized.first['emoji'], '❤️');
    flutterTesting2026x9.expect(normalized.last['user_id'], 'u2');
    flutterTesting2026x9.expect(barqApp.normalizeMessageReactions(null), flutterTesting2026x9.isEmpty);
  });

  flutterTesting2026x9.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    flutterTesting2026x9.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(selectedEmoji, '❤️');
    flutterTesting2026x9.expect(removing, flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    flutterTesting2026x9.expect(find.text('إضافة تفاعل'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  flutterTesting2026x9.test('media duration formatter supports minute and hour lengths', () {
    flutterTesting2026x9.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    flutterTesting2026x9.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    flutterTesting2026x9.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  flutterTesting2026x9.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    flutterTesting2026x9.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  flutterTesting2026x9.test('message link extraction ignores non-web schemes', () {
    flutterTesting2026x9.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  flutterTesting2026x9.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    flutterTesting2026x9.expect(requests, 0);
    flutterTesting2026x9.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    flutterTesting2026x9.expect(requests, 1);
    flutterTesting2026x9.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  flutterTesting2026x9.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    flutterTesting2026x9.expect(find.text('أدوات المحادثة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('البحث في المحادثة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(selectedTool, 'pinned');
  });

  flutterTesting2026x9.test('private and group message text share the server 5000-character limit', () {
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed(''), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed('   '), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('audio transcription enforces the worker two-megabyte limit', () {
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(0), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(1), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), flutterTesting2026x9.isFalse);
  });


  flutterTesting2026x9.test('SPARK media extensions map to exact supported MIME types', () {
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('exe'), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType(''), flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.test('SPARK media client size limit rejects empty and oversized files', () {
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(0), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(1), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), flutterTesting2026x9.isFalse);
  });


  flutterTesting2026x9.test('private memory photo uploads continue after an individual failure', () async {
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

    flutterTesting2026x9.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    flutterTesting2026x9.expect(failures, ['two.png']);
  });

  flutterTesting2026x9.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    flutterTesting2026x9.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    flutterTesting2026x9.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    flutterTesting2026x9.expect(retried, flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    flutterTesting2026x9.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    flutterTesting2026x9.expect(find.byType(PageView), findsNothing);
    flutterTesting2026x9.expect(find.textContaining('/'), findsNothing);
  });

  flutterTesting2026x9.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    flutterTesting2026x9.expect(find.byType(PageView), findsOneWidget);
    flutterTesting2026x9.expect(find.byType(InteractiveViewer), findsWidgets);
    flutterTesting2026x9.expect(visiblePage, 0);
    flutterTesting2026x9.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(visiblePage, 1);
    flutterTesting2026x9.expect(find.text('2 / 3'), findsOneWidget);
  });


  flutterTesting2026x9.test('BARQ has exactly the four approved visual identities', () {
    flutterTesting2026x9.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  flutterTesting2026x9.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    flutterTesting2026x9.expect(BarqIdentity.values, flutterTesting2026x9.hasLength(4));
    flutterTesting2026x9.expect(palettes.map((p) => p.background).toSet().length, 4);
    flutterTesting2026x9.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      flutterTesting2026x9.expect(palette.text, flutterTesting2026x9.isNot(palette.background));
      flutterTesting2026x9.expect(palette.primary, flutterTesting2026x9.isNot(palette.background));
      flutterTesting2026x9.expect(palette.secondary, flutterTesting2026x9.isNot(palette.surface));
      flutterTesting2026x9.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      flutterTesting2026x9.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      flutterTesting2026x9.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      flutterTesting2026x9.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    flutterTesting2026x9.expect(blue.primary, const Color(0xFFD6AD55));
    flutterTesting2026x9.expect(blue.secondary, const Color(0xFF168BFF));
    flutterTesting2026x9.expect(blue.background, const Color(0xFF090909));
    flutterTesting2026x9.expect(blue.surface, const Color(0xFF171717));
  });

  flutterTesting2026x9.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(null), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(''), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken('   '), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken('token with spaces'), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), flutterTesting2026x9.hasLength(4096));
  });

  flutterTesting2026x9.test('foreground push uses generic labels and respects category preferences', () {
    flutterTesting2026x9.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    flutterTesting2026x9.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    flutterTesting2026x9.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    flutterTesting2026x9.expect(success, flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    flutterTesting2026x9.expect(noSession, flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(revoked, flutterTesting2026x9.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    flutterTesting2026x9.expect(invalidToken, flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(revoked, flutterTesting2026x9.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    flutterTesting2026x9.expect(networkFailure, flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('FCM registration requires authorized or provisional notification permission', () {
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), flutterTesting2026x9.isFalse);
  });

}
)));
    flutterTesting2026x9.expect(first, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('967770000000')));
    flutterTesting2026x9.expect(barqApp.barqPrivateRegistrationUsername('+447911123456'), flutterTesting2026x9.isNot(first));
  });

  flutterTesting2026x9.test('international phone normalization supports Arabic digits and 00 prefix', () {
    flutterTesting2026x9.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    flutterTesting2026x9.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    flutterTesting2026x9.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  flutterTesting2026x9.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    flutterTesting2026x9.expect(barqIdentity.barqCountryCodes.length, 206);
    final codes = barqIdentity.barqCountryCodes.map((country) => country.$2).toSet();
    flutterTesting2026x9.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      flutterTesting2026x9.expect(codes, flutterTesting2026x9.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    flutterTesting2026x9.expect(codes, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('+1684')));
    flutterTesting2026x9.expect(codes, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('+1340')));
    flutterTesting2026x9.expect(codes, flutterTesting2026x9.isNot(flutterTesting2026x9.contains('+1787')));
  });

  flutterTesting2026x9.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    flutterTesting2026x9.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    flutterTesting2026x9.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    flutterTesting2026x9.expect(barqApp.normalizeBarqContactPhoneDigits('---'), flutterTesting2026x9.isEmpty);
  });

  flutterTesting2026x9.test('conversation search flutterTesting2026x9.matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, 'not found'), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(barqApp.searchConversationMessages(messages, '   '), flutterTesting2026x9.isEmpty);
  });

  flutterTesting2026x9.test('offline sync pauses only for network failures, not one rejected message', () {
    flutterTesting2026x9.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  flutterTesting2026x9.test('accepted outbox removal preserves a flutterTesting2026x9.same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    flutterTesting2026x9.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    flutterTesting2026x9.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      flutterTesting2026x9.isEmpty,
    );
  });

  flutterTesting2026x9.test('offline reconciliation keeps a flutterTesting2026x9.same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  flutterTesting2026x9.test('offline queue capacity rejects the first item beyond the limit', () {
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(0), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(199), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(200), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(201), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    flutterTesting2026x9.expect(barqApp.decodeBarqOfflineQueue(null), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(barqApp.decodeBarqOfflineQueue(''), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    flutterTesting2026x9.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  flutterTesting2026x9.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('offline queue reconciliation removes exact flutterTesting2026x9.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    flutterTesting2026x9.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    flutterTesting2026x9.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), flutterTesting2026x9.same(queued));
  });

  flutterTesting2026x9.test('message merge deduplicates by id and keeps chronological order', () {
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

    flutterTesting2026x9.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    flutterTesting2026x9.expect(merged[1]['body'], 'second updated');
  });

  flutterTesting2026x9.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    flutterTesting2026x9.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    flutterTesting2026x9.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  flutterTesting2026x9.test('profile photo path is resolved for group payloads with snake_case fields', () {
    flutterTesting2026x9.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    flutterTesting2026x9.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), flutterTesting2026x9.isEmpty);
    flutterTesting2026x9.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  flutterTesting2026x9.test('group roles limit promotion to owners and preserve the owner account', () {
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('group removal permissions prevent admins removing peers or owners', () {
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      flutterTesting2026x9.isFalse,
    );
  });

  flutterTesting2026x9.test('only an owner can transfer group ownership to another non-owner member', () {
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isTrue,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      flutterTesting2026x9.isFalse,
    );
    flutterTesting2026x9.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      flutterTesting2026x9.isFalse,
    );
  });

  flutterTesting2026x9.test('group members can leave themselves but the owner cannot leave without transfer', () {
    flutterTesting2026x9.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    flutterTesting2026x9.expect(find.text('الملف الشخصي'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('صديق برق'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('@barq_friend'), findsNWidgets(2));
    flutterTesting2026x9.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    flutterTesting2026x9.expect(sendButton.onPressed, flutterTesting2026x9.isNotNull);
  });


  flutterTesting2026x9.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    flutterTesting2026x9.expect(sendButton.onPressed, flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    flutterTesting2026x9.expect(find.text('عضو المجموعة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('@group_member'), findsNWidgets(2));
    flutterTesting2026x9.expect(find.text('إرسال رسالة'), findsNothing);
  });

  flutterTesting2026x9.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    flutterTesting2026x9.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  flutterTesting2026x9.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    flutterTesting2026x9.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(deleted, flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.testWidgets('other users message actions do not expose delete', (tester) async {
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
    flutterTesting2026x9.expect(find.text('نسخ الرسالة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('حذف الرسالة'), findsNothing);
  });

  flutterTesting2026x9.test('quoted reply preview is bounded and handles attachment references', () {
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    flutterTesting2026x9.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  flutterTesting2026x9.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    flutterTesting2026x9.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(saved, 'النص الجديد');
  });

  flutterTesting2026x9.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    flutterTesting2026x9.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(selected?['id'], 'reply-1');
  });


  flutterTesting2026x9.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    flutterTesting2026x9.expect(normalized, flutterTesting2026x9.hasLength(2));
    flutterTesting2026x9.expect(normalized.first['emoji'], '❤️');
    flutterTesting2026x9.expect(normalized.last['user_id'], 'u2');
    flutterTesting2026x9.expect(barqApp.normalizeMessageReactions(null), flutterTesting2026x9.isEmpty);
  });

  flutterTesting2026x9.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    flutterTesting2026x9.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(selectedEmoji, '❤️');
    flutterTesting2026x9.expect(removing, flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    flutterTesting2026x9.expect(find.text('إضافة تفاعل'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  flutterTesting2026x9.test('media duration formatter supports minute and hour lengths', () {
    flutterTesting2026x9.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    flutterTesting2026x9.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    flutterTesting2026x9.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  flutterTesting2026x9.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    flutterTesting2026x9.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  flutterTesting2026x9.test('message link extraction ignores non-web schemes', () {
    flutterTesting2026x9.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  flutterTesting2026x9.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    flutterTesting2026x9.expect(requests, 0);
    flutterTesting2026x9.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    flutterTesting2026x9.expect(requests, 1);
    flutterTesting2026x9.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  flutterTesting2026x9.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    flutterTesting2026x9.expect(find.text('أدوات المحادثة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('البحث في المحادثة'), findsOneWidget);
    flutterTesting2026x9.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(selectedTool, 'pinned');
  });

  flutterTesting2026x9.test('private and group message text share the server 5000-character limit', () {
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed(''), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed('   '), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('audio transcription enforces the worker two-megabyte limit', () {
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(0), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(1), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), flutterTesting2026x9.isFalse);
  });


  flutterTesting2026x9.test('SPARK media extensions map to exact supported MIME types', () {
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType('exe'), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqSparkMediaContentType(''), flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.test('SPARK media client size limit rejects empty and oversized files', () {
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(0), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(1), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), flutterTesting2026x9.isFalse);
  });


  flutterTesting2026x9.test('private memory photo uploads continue after an individual failure', () async {
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

    flutterTesting2026x9.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    flutterTesting2026x9.expect(failures, ['two.png']);
  });

  flutterTesting2026x9.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    flutterTesting2026x9.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    flutterTesting2026x9.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    flutterTesting2026x9.expect(retried, flutterTesting2026x9.isTrue);
  });

  flutterTesting2026x9.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    flutterTesting2026x9.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    flutterTesting2026x9.expect(find.byType(PageView), findsNothing);
    flutterTesting2026x9.expect(find.textContaining('/'), findsNothing);
  });

  flutterTesting2026x9.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    flutterTesting2026x9.expect(find.byType(PageView), findsOneWidget);
    flutterTesting2026x9.expect(find.byType(InteractiveViewer), findsWidgets);
    flutterTesting2026x9.expect(visiblePage, 0);
    flutterTesting2026x9.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    flutterTesting2026x9.expect(visiblePage, 1);
    flutterTesting2026x9.expect(find.text('2 / 3'), findsOneWidget);
  });


  flutterTesting2026x9.test('BARQ has exactly the four approved visual identities', () {
    flutterTesting2026x9.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    flutterTesting2026x9.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  flutterTesting2026x9.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    flutterTesting2026x9.expect(BarqIdentity.values, flutterTesting2026x9.hasLength(4));
    flutterTesting2026x9.expect(palettes.map((p) => p.background).toSet().length, 4);
    flutterTesting2026x9.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      flutterTesting2026x9.expect(palette.text, flutterTesting2026x9.isNot(palette.background));
      flutterTesting2026x9.expect(palette.primary, flutterTesting2026x9.isNot(palette.background));
      flutterTesting2026x9.expect(palette.secondary, flutterTesting2026x9.isNot(palette.surface));
      flutterTesting2026x9.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      flutterTesting2026x9.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      flutterTesting2026x9.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      flutterTesting2026x9.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    flutterTesting2026x9.expect(blue.primary, const Color(0xFFD6AD55));
    flutterTesting2026x9.expect(blue.secondary, const Color(0xFF168BFF));
    flutterTesting2026x9.expect(blue.background, const Color(0xFF090909));
    flutterTesting2026x9.expect(blue.surface, const Color(0xFF171717));
  });

  flutterTesting2026x9.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(null), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(''), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken('   '), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken('token with spaces'), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), flutterTesting2026x9.hasLength(4096));
  });

  flutterTesting2026x9.test('foreground push uses generic labels and respects category preferences', () {
    flutterTesting2026x9.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    flutterTesting2026x9.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    flutterTesting2026x9.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), flutterTesting2026x9.isNull);
    flutterTesting2026x9.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), flutterTesting2026x9.isNull);
  });

  flutterTesting2026x9.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    flutterTesting2026x9.expect(success, flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    flutterTesting2026x9.expect(noSession, flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(revoked, flutterTesting2026x9.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    flutterTesting2026x9.expect(invalidToken, flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(revoked, flutterTesting2026x9.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    flutterTesting2026x9.expect(networkFailure, flutterTesting2026x9.isFalse);
  });

  flutterTesting2026x9.test('FCM registration requires authorized or provisional notification permission', () {
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), flutterTesting2026x9.isTrue);
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), flutterTesting2026x9.isFalse);
    flutterTesting2026x9.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), flutterTesting2026x9.isFalse);
  });

}
