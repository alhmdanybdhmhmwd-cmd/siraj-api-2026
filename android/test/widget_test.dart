import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as __barqFlutterTesting2026;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart' as barqApp;
import 'package:barq/barq_identity.dart';

void main() {
  __barqFlutterTesting2026.test('optional realtime connects only with a session, endpoint and resumed app', () {
    __barqFlutterTesting2026.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('realtime events refresh only the matching direct conversation', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      __barqFlutterTesting2026.isFalse,
    );
  });

  __barqFlutterTesting2026.test('notification tap routing validates private chat, group and SPARK destinations', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    __barqFlutterTesting2026.expect(barqApp.barqNotificationRouteFromData({'type': 'direct_message'}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.test('Nearby requests only permissions supported by the Android API level', () {
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyRequiresLocationService(30), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyRequiresLocationService(32), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyRequiresLocationService(33), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyRequiresLocationService(37), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('Nearby payload transfer treats failure and cancellation as failed', () {
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.NONE), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('registration sends a stable private username without exposing the phone', () {
    final first = barqApp.barqPrivateRegistrationUsername('+967770000000');
    final second = barqApp.barqPrivateRegistrationUsername('+967770000000');
    __barqFlutterTesting2026.expect(first, second);
    __barqFlutterTesting2026.expect(first, matches(RegExp(r'^barq[a-f0-9]{16}$')));
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  __barqFlutterTesting2026.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    __barqFlutterTesting2026.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    __barqFlutterTesting2026.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('+1684')));
    __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('+1340')));
    __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('+1787')));
  });

  __barqFlutterTesting2026.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    __barqFlutterTesting2026.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    __barqFlutterTesting2026.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqContactPhoneDigits('---'), __barqFlutterTesting2026.isEmpty);
  });

  __barqFlutterTesting2026.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, 'not found'), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, '   '), __barqFlutterTesting2026.isEmpty);
  });

  __barqFlutterTesting2026.test('offline sync pauses only for network failures, not one rejected message', () {
    __barqFlutterTesting2026.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  __barqFlutterTesting2026.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    __barqFlutterTesting2026.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      __barqFlutterTesting2026.isEmpty,
    );
  });

  __barqFlutterTesting2026.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  __barqFlutterTesting2026.test('offline queue capacity rejects the first item beyond the limit', () {
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(0), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(199), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(200), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(201), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    __barqFlutterTesting2026.expect(barqApp.decodeBarqOfflineQueue(null), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(barqApp.decodeBarqOfflineQueue(''), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), __barqFlutterTesting2026.throwsFormatException);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), __barqFlutterTesting2026.throwsFormatException);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), __barqFlutterTesting2026.throwsFormatException);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), __barqFlutterTesting2026.throwsFormatException);
  });

  __barqFlutterTesting2026.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    __barqFlutterTesting2026.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  __barqFlutterTesting2026.test('message merge deduplicates by id and keeps chronological order', () {
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

    __barqFlutterTesting2026.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    __barqFlutterTesting2026.expect(merged[1]['body'], 'second updated');
  });

  __barqFlutterTesting2026.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    __barqFlutterTesting2026.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    __barqFlutterTesting2026.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  __barqFlutterTesting2026.test('profile photo path is resolved for group payloads with snake_case fields', () {
    __barqFlutterTesting2026.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    __barqFlutterTesting2026.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  __barqFlutterTesting2026.test('group roles limit promotion to owners and preserve the owner account', () {
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('group removal permissions prevent admins removing peers or owners', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      __barqFlutterTesting2026.isFalse,
    );
  });

  __barqFlutterTesting2026.test('only an owner can transfer group ownership to another non-owner member', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      __barqFlutterTesting2026.isFalse,
    );
  });

  __barqFlutterTesting2026.test('group members can leave themselves but the owner cannot leave without transfer', () {
    __barqFlutterTesting2026.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    __barqFlutterTesting2026.expect(find.text('الملف الشخصي'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('صديق برق'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('@barq_friend'), __barqFlutterTesting2026.findsNWidgets(2));
    __barqFlutterTesting2026.expect(find.text('+967700000001'), __barqFlutterTesting2026.findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(find.text('حفظ الرقم في جهات الاتصال'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('إرسال رسالة'), __barqFlutterTesting2026.findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    __barqFlutterTesting2026.expect(sendButton.onPressed, __barqFlutterTesting2026.isNotNull);
  });


  __barqFlutterTesting2026.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    __barqFlutterTesting2026.expect(sendButton.onPressed, __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    __barqFlutterTesting2026.expect(find.text('عضو المجموعة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('@group_member'), __barqFlutterTesting2026.findsNWidgets(2));
    __barqFlutterTesting2026.expect(find.text('إرسال رسالة'), __barqFlutterTesting2026.findsNothing);
  });

  __barqFlutterTesting2026.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    __barqFlutterTesting2026.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  __barqFlutterTesting2026.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('نسخ الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('حذف الرسالة'), __barqFlutterTesting2026.findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(find.text('حذف الرسالة؟'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(deleted, __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.testWidgets('other users message actions do not expose delete', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('نسخ الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('حذف الرسالة'), __barqFlutterTesting2026.findsNothing);
  });

  __barqFlutterTesting2026.test('quoted reply preview is bounded and handles attachment references', () {
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  __barqFlutterTesting2026.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('تعديل الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(saved, 'النص الجديد');
  });

  __barqFlutterTesting2026.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('الرد على الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(selected?['id'], 'reply-1');
  });


  __barqFlutterTesting2026.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    __barqFlutterTesting2026.expect(normalized, __barqFlutterTesting2026.hasLength(2));
    __barqFlutterTesting2026.expect(normalized.first['emoji'], '❤️');
    __barqFlutterTesting2026.expect(normalized.last['user_id'], 'u2');
    __barqFlutterTesting2026.expect(barqApp.normalizeMessageReactions(null), __barqFlutterTesting2026.isEmpty);
  });

  __barqFlutterTesting2026.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    __barqFlutterTesting2026.expect(find.text('❤️ 2'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(selectedEmoji, '❤️');
    __barqFlutterTesting2026.expect(removing, __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('إضافة تفاعل'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('تثبيت الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('حفظ في الذكريات الخاصة'), __barqFlutterTesting2026.findsOneWidget);
  });

  __barqFlutterTesting2026.test('media duration formatter supports minute and hour lengths', () {
    __barqFlutterTesting2026.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    __barqFlutterTesting2026.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    __barqFlutterTesting2026.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  __barqFlutterTesting2026.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    __barqFlutterTesting2026.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  __barqFlutterTesting2026.test('message link extraction ignores non-web schemes', () {
    __barqFlutterTesting2026.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  __barqFlutterTesting2026.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    __barqFlutterTesting2026.expect(requests, 0);
    __barqFlutterTesting2026.expect(find.text('إنشاء الملخص'), __barqFlutterTesting2026.findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    __barqFlutterTesting2026.expect(requests, 1);
    __barqFlutterTesting2026.expect(find.text('ملخص اختباري'), __barqFlutterTesting2026.findsOneWidget);
  });

  __barqFlutterTesting2026.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('أدوات المحادثة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('البحث في المحادثة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('الرسائل المثبتة'), __barqFlutterTesting2026.findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(selectedTool, 'pinned');
  });

  __barqFlutterTesting2026.test('private and group message text share the server 5000-character limit', () {
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed(''), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed('   '), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('audio transcription enforces the worker two-megabyte limit', () {
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(0), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(1), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), __barqFlutterTesting2026.isFalse);
  });


  __barqFlutterTesting2026.test('SPARK media extensions map to exact supported MIME types', () {
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('exe'), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType(''), __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.test('SPARK media client size limit rejects empty and oversized files', () {
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(0), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(1), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), __barqFlutterTesting2026.isFalse);
  });


  __barqFlutterTesting2026.test('private memory photo uploads continue after an individual failure', () async {
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

    __barqFlutterTesting2026.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    __barqFlutterTesting2026.expect(failures, ['two.png']);
  });

  __barqFlutterTesting2026.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    __barqFlutterTesting2026.expect(find.text('تعذر تحميل ذكرياتك'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    __barqFlutterTesting2026.expect(retried, __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    __barqFlutterTesting2026.expect(find.byIcon(Icons.photo_library_outlined), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.byType(PageView), __barqFlutterTesting2026.findsNothing);
    __barqFlutterTesting2026.expect(find.textContaining('/'), __barqFlutterTesting2026.findsNothing);
  });

  __barqFlutterTesting2026.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    __barqFlutterTesting2026.expect(find.byType(PageView), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.byType(InteractiveViewer), __barqFlutterTesting2026.findsWidgets);
    __barqFlutterTesting2026.expect(visiblePage, 0);
    __barqFlutterTesting2026.expect(find.text('1 / 3'), __barqFlutterTesting2026.findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(visiblePage, 1);
    __barqFlutterTesting2026.expect(find.text('2 / 3'), __barqFlutterTesting2026.findsOneWidget);
  });


  __barqFlutterTesting2026.test('BARQ has exactly the four approved visual identities', () {
    __barqFlutterTesting2026.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  __barqFlutterTesting2026.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    __barqFlutterTesting2026.expect(BarqIdentity.values, __barqFlutterTesting2026.hasLength(4));
    __barqFlutterTesting2026.expect(palettes.map((p) => p.background).toSet().length, 4);
    __barqFlutterTesting2026.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      __barqFlutterTesting2026.expect(palette.text, __barqFlutterTesting2026.isNot(palette.background));
      __barqFlutterTesting2026.expect(palette.primary, __barqFlutterTesting2026.isNot(palette.background));
      __barqFlutterTesting2026.expect(palette.secondary, __barqFlutterTesting2026.isNot(palette.surface));
      __barqFlutterTesting2026.expect(contrastRatio(palette.text, palette.background), __barqFlutterTesting2026.greaterThanOrEqualTo(7));
      __barqFlutterTesting2026.expect(contrastRatio(palette.text, palette.surface), __barqFlutterTesting2026.greaterThanOrEqualTo(7));
      __barqFlutterTesting2026.expect(contrastRatio(palette.mutedText, palette.surface), __barqFlutterTesting2026.greaterThanOrEqualTo(4.5));
      __barqFlutterTesting2026.expect(contrastRatio(palette.primary, palette.surface), __barqFlutterTesting2026.greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    __barqFlutterTesting2026.expect(blue.primary, const Color(0xFFD6AD55));
    __barqFlutterTesting2026.expect(blue.secondary, const Color(0xFF168BFF));
    __barqFlutterTesting2026.expect(blue.background, const Color(0xFF090909));
    __barqFlutterTesting2026.expect(blue.surface, const Color(0xFF171717));
  });

  __barqFlutterTesting2026.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(null), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(''), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken('   '), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken('token with spaces'), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), __barqFlutterTesting2026.hasLength(4096));
  });

  __barqFlutterTesting2026.test('foreground push uses generic labels and respects category preferences', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    __barqFlutterTesting2026.expect(success, __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    __barqFlutterTesting2026.expect(noSession, __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(revoked, __barqFlutterTesting2026.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    __barqFlutterTesting2026.expect(invalidToken, __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(revoked, __barqFlutterTesting2026.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    __barqFlutterTesting2026.expect(networkFailure, __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('FCM registration requires authorized or provisional notification permission', () {
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), __barqFlutterTesting2026.isFalse);
  });

}
)));
    __barqFlutterTesting2026.expect(first, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('967770000000')));
    __barqFlutterTesting2026.expect(barqApp.barqPrivateRegistrationUsername('+447911123456'), __barqFlutterTesting2026.isNot(first));
  });

  __barqFlutterTesting2026.test('international phone normalization supports Arabic digits and 00 prefix', () {
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  __barqFlutterTesting2026.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    __barqFlutterTesting2026.expect(barqCountryCodes.length, 206);
    final codes = barqCountryCodes.map((country) => country.$2).toSet();
    __barqFlutterTesting2026.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('+1684')));
    __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('+1340')));
    __barqFlutterTesting2026.expect(codes, __barqFlutterTesting2026.isNot(__barqFlutterTesting2026.contains('+1787')));
  });

  __barqFlutterTesting2026.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    __barqFlutterTesting2026.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    __barqFlutterTesting2026.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqContactPhoneDigits('---'), __barqFlutterTesting2026.isEmpty);
  });

  __barqFlutterTesting2026.test('conversation search matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, 'not found'), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(barqApp.searchConversationMessages(messages, '   '), __barqFlutterTesting2026.isEmpty);
  });

  __barqFlutterTesting2026.test('offline sync pauses only for network failures, not one rejected message', () {
    __barqFlutterTesting2026.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  __barqFlutterTesting2026.test('accepted outbox removal preserves a same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    __barqFlutterTesting2026.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      __barqFlutterTesting2026.isEmpty,
    );
  });

  __barqFlutterTesting2026.test('offline reconciliation keeps a same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  __barqFlutterTesting2026.test('offline queue capacity rejects the first item beyond the limit', () {
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(0), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(199), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(200), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(201), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    __barqFlutterTesting2026.expect(barqApp.decodeBarqOfflineQueue(null), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(barqApp.decodeBarqOfflineQueue(''), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), __barqFlutterTesting2026.throwsFormatException);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), __barqFlutterTesting2026.throwsFormatException);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), __barqFlutterTesting2026.throwsFormatException);
    __barqFlutterTesting2026.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), __barqFlutterTesting2026.throwsFormatException);
  });

  __barqFlutterTesting2026.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('offline queue reconciliation removes exact matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    __barqFlutterTesting2026.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    __barqFlutterTesting2026.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), same(queued));
  });

  __barqFlutterTesting2026.test('message merge deduplicates by id and keeps chronological order', () {
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

    __barqFlutterTesting2026.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    __barqFlutterTesting2026.expect(merged[1]['body'], 'second updated');
  });

  __barqFlutterTesting2026.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    __barqFlutterTesting2026.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    __barqFlutterTesting2026.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  __barqFlutterTesting2026.test('profile photo path is resolved for group payloads with snake_case fields', () {
    __barqFlutterTesting2026.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    __barqFlutterTesting2026.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), __barqFlutterTesting2026.isEmpty);
    __barqFlutterTesting2026.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  __barqFlutterTesting2026.test('group roles limit promotion to owners and preserve the owner account', () {
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('group removal permissions prevent admins removing peers or owners', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      __barqFlutterTesting2026.isFalse,
    );
  });

  __barqFlutterTesting2026.test('only an owner can transfer group ownership to another non-owner member', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isTrue,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      __barqFlutterTesting2026.isFalse,
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      __barqFlutterTesting2026.isFalse,
    );
  });

  __barqFlutterTesting2026.test('group members can leave themselves but the owner cannot leave without transfer', () {
    __barqFlutterTesting2026.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    __barqFlutterTesting2026.expect(find.text('الملف الشخصي'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('صديق برق'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('@barq_friend'), __barqFlutterTesting2026.findsNWidgets(2));
    __barqFlutterTesting2026.expect(find.text('+967700000001'), __barqFlutterTesting2026.findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(find.text('حفظ الرقم في جهات الاتصال'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('إرسال رسالة'), __barqFlutterTesting2026.findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    __barqFlutterTesting2026.expect(sendButton.onPressed, __barqFlutterTesting2026.isNotNull);
  });


  __barqFlutterTesting2026.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    __barqFlutterTesting2026.expect(sendButton.onPressed, __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    __barqFlutterTesting2026.expect(find.text('عضو المجموعة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('@group_member'), __barqFlutterTesting2026.findsNWidgets(2));
    __barqFlutterTesting2026.expect(find.text('إرسال رسالة'), __barqFlutterTesting2026.findsNothing);
  });

  __barqFlutterTesting2026.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    __barqFlutterTesting2026.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  __barqFlutterTesting2026.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('نسخ الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('حذف الرسالة'), __barqFlutterTesting2026.findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(find.text('حذف الرسالة؟'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(deleted, __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.testWidgets('other users message actions do not expose delete', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('نسخ الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('حذف الرسالة'), __barqFlutterTesting2026.findsNothing);
  });

  __barqFlutterTesting2026.test('quoted reply preview is bounded and handles attachment references', () {
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    __barqFlutterTesting2026.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  __barqFlutterTesting2026.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('تعديل الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(saved, 'النص الجديد');
  });

  __barqFlutterTesting2026.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('الرد على الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(selected?['id'], 'reply-1');
  });


  __barqFlutterTesting2026.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    __barqFlutterTesting2026.expect(normalized, __barqFlutterTesting2026.hasLength(2));
    __barqFlutterTesting2026.expect(normalized.first['emoji'], '❤️');
    __barqFlutterTesting2026.expect(normalized.last['user_id'], 'u2');
    __barqFlutterTesting2026.expect(barqApp.normalizeMessageReactions(null), __barqFlutterTesting2026.isEmpty);
  });

  __barqFlutterTesting2026.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    __barqFlutterTesting2026.expect(find.text('❤️ 2'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(selectedEmoji, '❤️');
    __barqFlutterTesting2026.expect(removing, __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('إضافة تفاعل'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('تثبيت الرسالة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('حفظ في الذكريات الخاصة'), __barqFlutterTesting2026.findsOneWidget);
  });

  __barqFlutterTesting2026.test('media duration formatter supports minute and hour lengths', () {
    __barqFlutterTesting2026.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    __barqFlutterTesting2026.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    __barqFlutterTesting2026.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  __barqFlutterTesting2026.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    __barqFlutterTesting2026.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  __barqFlutterTesting2026.test('message link extraction ignores non-web schemes', () {
    __barqFlutterTesting2026.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  __barqFlutterTesting2026.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    __barqFlutterTesting2026.expect(requests, 0);
    __barqFlutterTesting2026.expect(find.text('إنشاء الملخص'), __barqFlutterTesting2026.findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    __barqFlutterTesting2026.expect(requests, 1);
    __barqFlutterTesting2026.expect(find.text('ملخص اختباري'), __barqFlutterTesting2026.findsOneWidget);
  });

  __barqFlutterTesting2026.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    __barqFlutterTesting2026.expect(find.text('أدوات المحادثة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('البحث في المحادثة'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.text('الرسائل المثبتة'), __barqFlutterTesting2026.findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(selectedTool, 'pinned');
  });

  __barqFlutterTesting2026.test('private and group message text share the server 5000-character limit', () {
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed(''), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed('   '), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('audio transcription enforces the worker two-megabyte limit', () {
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(0), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(1), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), __barqFlutterTesting2026.isFalse);
  });


  __barqFlutterTesting2026.test('SPARK media extensions map to exact supported MIME types', () {
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType('exe'), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqSparkMediaContentType(''), __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.test('SPARK media client size limit rejects empty and oversized files', () {
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(0), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(1), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), __barqFlutterTesting2026.isFalse);
  });


  __barqFlutterTesting2026.test('private memory photo uploads continue after an individual failure', () async {
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

    __barqFlutterTesting2026.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    __barqFlutterTesting2026.expect(failures, ['two.png']);
  });

  __barqFlutterTesting2026.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    __barqFlutterTesting2026.expect(find.text('تعذر تحميل ذكرياتك'), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), __barqFlutterTesting2026.findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    __barqFlutterTesting2026.expect(retried, __barqFlutterTesting2026.isTrue);
  });

  __barqFlutterTesting2026.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    __barqFlutterTesting2026.expect(find.byIcon(Icons.photo_library_outlined), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.byType(PageView), __barqFlutterTesting2026.findsNothing);
    __barqFlutterTesting2026.expect(find.textContaining('/'), __barqFlutterTesting2026.findsNothing);
  });

  __barqFlutterTesting2026.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    __barqFlutterTesting2026.expect(find.byType(PageView), __barqFlutterTesting2026.findsOneWidget);
    __barqFlutterTesting2026.expect(find.byType(InteractiveViewer), __barqFlutterTesting2026.findsWidgets);
    __barqFlutterTesting2026.expect(visiblePage, 0);
    __barqFlutterTesting2026.expect(find.text('1 / 3'), __barqFlutterTesting2026.findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    __barqFlutterTesting2026.expect(visiblePage, 1);
    __barqFlutterTesting2026.expect(find.text('2 / 3'), __barqFlutterTesting2026.findsOneWidget);
  });


  __barqFlutterTesting2026.test('BARQ has exactly the four approved visual identities', () {
    __barqFlutterTesting2026.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    __barqFlutterTesting2026.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  __barqFlutterTesting2026.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    __barqFlutterTesting2026.expect(BarqIdentity.values, __barqFlutterTesting2026.hasLength(4));
    __barqFlutterTesting2026.expect(palettes.map((p) => p.background).toSet().length, 4);
    __barqFlutterTesting2026.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      __barqFlutterTesting2026.expect(palette.text, __barqFlutterTesting2026.isNot(palette.background));
      __barqFlutterTesting2026.expect(palette.primary, __barqFlutterTesting2026.isNot(palette.background));
      __barqFlutterTesting2026.expect(palette.secondary, __barqFlutterTesting2026.isNot(palette.surface));
      __barqFlutterTesting2026.expect(contrastRatio(palette.text, palette.background), __barqFlutterTesting2026.greaterThanOrEqualTo(7));
      __barqFlutterTesting2026.expect(contrastRatio(palette.text, palette.surface), __barqFlutterTesting2026.greaterThanOrEqualTo(7));
      __barqFlutterTesting2026.expect(contrastRatio(palette.mutedText, palette.surface), __barqFlutterTesting2026.greaterThanOrEqualTo(4.5));
      __barqFlutterTesting2026.expect(contrastRatio(palette.primary, palette.surface), __barqFlutterTesting2026.greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    __barqFlutterTesting2026.expect(blue.primary, const Color(0xFFD6AD55));
    __barqFlutterTesting2026.expect(blue.secondary, const Color(0xFF168BFF));
    __barqFlutterTesting2026.expect(blue.background, const Color(0xFF090909));
    __barqFlutterTesting2026.expect(blue.surface, const Color(0xFF171717));
  });

  __barqFlutterTesting2026.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(null), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(''), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken('   '), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken('token with spaces'), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), __barqFlutterTesting2026.hasLength(4096));
  });

  __barqFlutterTesting2026.test('foreground push uses generic labels and respects category preferences', () {
    __barqFlutterTesting2026.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    __barqFlutterTesting2026.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), __barqFlutterTesting2026.isNull);
    __barqFlutterTesting2026.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), __barqFlutterTesting2026.isNull);
  });

  __barqFlutterTesting2026.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    __barqFlutterTesting2026.expect(success, __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    __barqFlutterTesting2026.expect(noSession, __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(revoked, __barqFlutterTesting2026.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    __barqFlutterTesting2026.expect(invalidToken, __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(revoked, __barqFlutterTesting2026.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    __barqFlutterTesting2026.expect(networkFailure, __barqFlutterTesting2026.isFalse);
  });

  __barqFlutterTesting2026.test('FCM registration requires authorized or provisional notification permission', () {
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), __barqFlutterTesting2026.isTrue);
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), __barqFlutterTesting2026.isFalse);
    __barqFlutterTesting2026.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), __barqFlutterTesting2026.isFalse);
  });

}
