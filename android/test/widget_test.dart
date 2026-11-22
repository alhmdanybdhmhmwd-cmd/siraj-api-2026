import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_test/flutter_test.dart' as barqFlutterTestNamespace20261122;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barq/main.dart' as barqApp;

void main() {
  barqFlutterTestNamespace20261122.test('optional realtime connects only with a session, endpoint and resumed app', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: 'wss://example.test'), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqRealtimeCanConnect(authToken: null, appResumed: true, socketUrl: 'wss://example.test'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqRealtimeCanConnect(authToken: '', appResumed: true, socketUrl: 'wss://example.test'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: false, socketUrl: 'wss://example.test'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqRealtimeCanConnect(authToken: 'session', appResumed: true, socketUrl: ''), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('realtime events refresh only the matching direct conversation', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1', 'receiverId': 'me'},
        'friend-1',
      ),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'me', 'receiverId': 'friend-1'},
        'friend-1',
      ),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'other', 'receiverId': 'me'},
        'friend-1',
      ),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'presence', 'senderId': 'friend-1'},
        'friend-1',
      ),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqRealtimeMessageMatchesConversation(
        {'type': 'message', 'senderId': 'friend-1'},
        '',
      ),
      barqFlutterTestNamespace20261122.isFalse,
    );
  });

  barqFlutterTestNamespace20261122.test('notification tap routing validates private chat, group and SPARK destinations', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqNotificationRouteFromData({'type': 'direct_message', 'senderId': 'user-7'}),
      {'type': 'direct_message', 'senderId': 'user-7'},
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': 'group-4'}),
      {'type': 'group_message', 'groupId': 'group-4'},
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update'}),
      {'type': 'status_update'},
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqNotificationRouteFromData({'type': 'status_update', 'statusId': 'spark-9'}),
      {'type': 'status_update', 'statusId': 'spark-9'},
    );
    barqFlutterTestNamespace20261122.expect(barqApp.barqNotificationRouteFromData({'type': 'direct_message'}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNotificationRouteFromData({'type': 'group_message', 'groupId': ' '}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNotificationRouteFromData({'type': 'unknown', 'senderId': 'user-7'}), barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.test('private invite links accept only the BARQ scheme, host and 12-character code', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456')), 'ABCDEF123456');
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456')), 'ABCDEF123456');
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('https://invite/abcdef123456')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://other/abcdef123456')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abc123')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef12345z')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456/extra')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite?code=abcdef123456&code=111111111111')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456?code=abcdef123456')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite@evil.example/abcdef123456')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite:443/abcdef123456')), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqInviteCodeFromUri(Uri.parse('barq://invite/abcdef123456#other')), barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.test('Nearby requests only permissions supported by the Android API level', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(26), ['location', 'bluetooth']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(30), ['location', 'bluetooth']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(31), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(32), ['location', 'bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(33), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPermissionNamesForAndroidSdk(37), ['bluetoothAdvertise', 'bluetoothConnect', 'bluetoothScan', 'nearbyWifiDevices']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyRequiresLocationService(30), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyRequiresLocationService(32), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyRequiresLocationService(33), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyRequiresLocationService(37), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('Nearby payload transfer treats failure and cancellation as failed', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.FAILURE), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.CANCELED), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.SUCCESS), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.IN_PROGRESS), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqNearbyPayloadTransferFailed(PayloadStatus.NONE), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('Nearby outgoing text validates sender, contact, stable ID and body', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    const contacts = {'friend-1'};
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'spoofed', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'stranger',
      knownContacts: contacts, messageId: id, body: 'hello',
    ), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: 'bad-id', body: 'hello',
    ), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: '   ',
    ), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyOutgoingText(
      senderId: 'me', currentUserId: 'me', receiverId: 'friend-1',
      knownContacts: contacts, messageId: id, body: List.filled(5001, 'x').join(),
    ), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('Nearby accepts only bounded text messages from the verified peer', () {
    final valid = <String, dynamic>{
      'kind': 'barq_text_message',
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'senderId': 'friend-1',
      'receiverId': 'me',
      'body': 'رسالة قريبة',
    };
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload(valid, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'senderId': 'stranger'}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'receiverId': 'other'}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'x'.padRight(129, 'x')}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'bad id'}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'a1b2c3d4e5f60708'}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'id': 'A1B2C3D4E5F60708A1B2C3D4E5F60708'}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': '   '}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'body': List<String>.filled(5001, 'x').join()}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isValidBarqNearbyTextPayload({...valid, 'kind': 'media'}, peerId: 'friend-1', currentUserId: 'me'), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('registration sends a stable private username without exposing the phone', () {
    final first = barqApp.barqPrivateRegistrationUsername('+967770000000');
    final second = barqApp.barqPrivateRegistrationUsername('+967770000000');
    barqFlutterTestNamespace20261122.expect(first, second);
    barqFlutterTestNamespace20261122.expect(first, barqFlutterTestNamespace20261122.matches(RegExp(r'^barq[a-f0-9]{16}$')));
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  barqFlutterTestNamespace20261122.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCountryCodes.length, 206);
    final codes = barqApp.barqCountryCodes.map((country) => country.$2).toSet();
    barqFlutterTestNamespace20261122.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('+1684')));
    barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('+1340')));
    barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('+1787')));
  });

  barqFlutterTestNamespace20261122.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqContactPhoneDigits('---'), barqFlutterTestNamespace20261122.isEmpty);
  });

  barqFlutterTestNamespace20261122.test('conversation search barqFlutterTestNamespace20261122.matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, 'not found'), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, '   '), barqFlutterTestNamespace20261122.isEmpty);
  });

  barqFlutterTestNamespace20261122.test('offline sync pauses only for network failures, not one rejected message', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  barqFlutterTestNamespace20261122.test('accepted outbox removal preserves a barqFlutterTestNamespace20261122.same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      barqFlutterTestNamespace20261122.isEmpty,
    );
  });

  barqFlutterTestNamespace20261122.test('offline reconciliation keeps a barqFlutterTestNamespace20261122.same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  barqFlutterTestNamespace20261122.test('offline queue capacity rejects the first item beyond the limit', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(0), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(199), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(200), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(201), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    barqFlutterTestNamespace20261122.expect(barqApp.decodeBarqOfflineQueue(null), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(barqApp.decodeBarqOfflineQueue(''), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  barqFlutterTestNamespace20261122.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('offline queue reconciliation removes exact barqFlutterTestNamespace20261122.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    barqFlutterTestNamespace20261122.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), barqFlutterTestNamespace20261122.same(queued));
  });

  barqFlutterTestNamespace20261122.test('message merge deduplicates by id and keeps chronological order', () {
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

    barqFlutterTestNamespace20261122.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    barqFlutterTestNamespace20261122.expect(merged[1]['body'], 'second updated');
  });

  barqFlutterTestNamespace20261122.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    barqFlutterTestNamespace20261122.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    barqFlutterTestNamespace20261122.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  barqFlutterTestNamespace20261122.test('profile photo path is resolved for group payloads with snake_case fields', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    barqFlutterTestNamespace20261122.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  barqFlutterTestNamespace20261122.test('group roles limit promotion to owners and preserve the owner account', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('group removal permissions prevent admins removing peers or owners', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      barqFlutterTestNamespace20261122.isFalse,
    );
  });

  barqFlutterTestNamespace20261122.test('only an owner can transfer group ownership to another non-owner member', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      barqFlutterTestNamespace20261122.isFalse,
    );
  });

  barqFlutterTestNamespace20261122.test('group members can leave themselves but the owner cannot leave without transfer', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.text('الملف الشخصي'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('صديق برق'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('@barq_friend'), findsNWidgets(2));
    barqFlutterTestNamespace20261122.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    barqFlutterTestNamespace20261122.expect(sendButton.onPressed, barqFlutterTestNamespace20261122.isNotNull);
  });


  barqFlutterTestNamespace20261122.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(sendButton.onPressed, barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.text('عضو المجموعة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('@group_member'), findsNWidgets(2));
    barqFlutterTestNamespace20261122.expect(find.text('إرسال رسالة'), findsNothing);
  });

  barqFlutterTestNamespace20261122.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    barqFlutterTestNamespace20261122.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  barqFlutterTestNamespace20261122.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('نسخ الرسالة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(deleted, barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.testWidgets('other users message actions do not expose delete', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('نسخ الرسالة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('حذف الرسالة'), findsNothing);
  });

  barqFlutterTestNamespace20261122.test('quoted reply preview is bounded and handles attachment references', () {
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  barqFlutterTestNamespace20261122.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(saved, 'النص الجديد');
  });

  barqFlutterTestNamespace20261122.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(selected?['id'], 'reply-1');
  });


  barqFlutterTestNamespace20261122.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    barqFlutterTestNamespace20261122.expect(normalized, barqFlutterTestNamespace20261122.hasLength(2));
    barqFlutterTestNamespace20261122.expect(normalized.first['emoji'], '❤️');
    barqFlutterTestNamespace20261122.expect(normalized.last['user_id'], 'u2');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeMessageReactions(null), barqFlutterTestNamespace20261122.isEmpty);
  });

  barqFlutterTestNamespace20261122.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(selectedEmoji, '❤️');
    barqFlutterTestNamespace20261122.expect(removing, barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('إضافة تفاعل'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  barqFlutterTestNamespace20261122.test('media duration formatter supports minute and hour lengths', () {
    barqFlutterTestNamespace20261122.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    barqFlutterTestNamespace20261122.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    barqFlutterTestNamespace20261122.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  barqFlutterTestNamespace20261122.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    barqFlutterTestNamespace20261122.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  barqFlutterTestNamespace20261122.test('message link extraction ignores non-web schemes', () {
    barqFlutterTestNamespace20261122.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  barqFlutterTestNamespace20261122.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(requests, 0);
    barqFlutterTestNamespace20261122.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    barqFlutterTestNamespace20261122.expect(requests, 1);
    barqFlutterTestNamespace20261122.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  barqFlutterTestNamespace20261122.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('أدوات المحادثة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('البحث في المحادثة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(selectedTool, 'pinned');
  });

  barqFlutterTestNamespace20261122.test('private and group message text share the server 5000-character limit', () {
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed(''), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed('   '), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('audio transcription enforces the worker two-megabyte limit', () {
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(0), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(1), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), barqFlutterTestNamespace20261122.isFalse);
  });


  barqFlutterTestNamespace20261122.test('SPARK media extensions map to exact supported MIME types', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('exe'), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType(''), barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.test('SPARK media client size limit rejects empty and oversized files', () {
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(0), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(1), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), barqFlutterTestNamespace20261122.isFalse);
  });


  barqFlutterTestNamespace20261122.test('private memory photo uploads continue after an individual failure', () async {
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

    barqFlutterTestNamespace20261122.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    barqFlutterTestNamespace20261122.expect(failures, ['two.png']);
  });

  barqFlutterTestNamespace20261122.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    barqFlutterTestNamespace20261122.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    barqFlutterTestNamespace20261122.expect(retried, barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.byType(PageView), findsNothing);
    barqFlutterTestNamespace20261122.expect(find.textContaining('/'), findsNothing);
  });

  barqFlutterTestNamespace20261122.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.byType(PageView), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.byType(InteractiveViewer), findsWidgets);
    barqFlutterTestNamespace20261122.expect(visiblePage, 0);
    barqFlutterTestNamespace20261122.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(visiblePage, 1);
    barqFlutterTestNamespace20261122.expect(find.text('2 / 3'), findsOneWidget);
  });


  barqFlutterTestNamespace20261122.test('BARQ has exactly the four approved visual identities', () {
    barqFlutterTestNamespace20261122.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  barqFlutterTestNamespace20261122.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    barqFlutterTestNamespace20261122.expect(BarqIdentity.values, barqFlutterTestNamespace20261122.hasLength(4));
    barqFlutterTestNamespace20261122.expect(palettes.map((p) => p.background).toSet().length, 4);
    barqFlutterTestNamespace20261122.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      barqFlutterTestNamespace20261122.expect(palette.text, barqFlutterTestNamespace20261122.isNot(palette.background));
      barqFlutterTestNamespace20261122.expect(palette.primary, barqFlutterTestNamespace20261122.isNot(palette.background));
      barqFlutterTestNamespace20261122.expect(palette.secondary, barqFlutterTestNamespace20261122.isNot(palette.surface));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    barqFlutterTestNamespace20261122.expect(blue.primary, const Color(0xFFD6AD55));
    barqFlutterTestNamespace20261122.expect(blue.secondary, const Color(0xFF168BFF));
    barqFlutterTestNamespace20261122.expect(blue.background, const Color(0xFF090909));
    barqFlutterTestNamespace20261122.expect(blue.surface, const Color(0xFF171717));
  });

  barqFlutterTestNamespace20261122.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(null), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(''), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken('   '), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken('token with spaces'), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), barqFlutterTestNamespace20261122.hasLength(4096));
  });

  barqFlutterTestNamespace20261122.test('foreground push uses generic labels and respects category preferences', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    barqFlutterTestNamespace20261122.expect(success, barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    barqFlutterTestNamespace20261122.expect(noSession, barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(revoked, barqFlutterTestNamespace20261122.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    barqFlutterTestNamespace20261122.expect(invalidToken, barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(revoked, barqFlutterTestNamespace20261122.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    barqFlutterTestNamespace20261122.expect(networkFailure, barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('FCM registration requires authorized or provisional notification permission', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), barqFlutterTestNamespace20261122.isFalse);
  });

}
)));
    barqFlutterTestNamespace20261122.expect(first, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('967770000000')));
    barqFlutterTestNamespace20261122.expect(barqApp.barqPrivateRegistrationUsername('+447911123456'), barqFlutterTestNamespace20261122.isNot(first));
  });

  barqFlutterTestNamespace20261122.test('international phone normalization supports Arabic digits and 00 prefix', () {
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqInternationalPhone(' +٩٦٧ ٧٧٠٠٠٠٠٠٠ '), '+967770000000');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqInternationalPhone('00447911123456'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone('٠٧٧٠٠٠٠٠٠٠', '+967'), '+967770000000');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone('0770000000', '+967'), '+967770000000');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone('+447911123456', '+967'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone(' +44 7911 123456 ', '+967'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone(' 00 44 7911 123456 ', '+967'), '+447911123456');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqRegistrationPhone(' ٠٧٧٠٠٠٠٠٠٠ ', '+967'), '+967770000000');
  });

  barqFlutterTestNamespace20261122.test('registration country codes cover 206 geographic calling codes without duplicates', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCountryCodes.length, 206);
    final codes = barqApp.barqCountryCodes.map((country) => country.$2).toSet();
    barqFlutterTestNamespace20261122.expect(codes.length, 206);
    for (final code in [
      '+222', '+223', '+228', '+246', '+247', '+269', '+297', '+298', '+299',
      '+350', '+378', '+383', '+389', '+423', '+501', '+590', '+594', '+596',
      '+672', '+681', '+850', '+972', '+995',
    ]) {
      barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.contains(code));
    }
    // These are regional prefixes within the shared +1 plan, not country codes.
    barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('+1684')));
    barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('+1340')));
    barqFlutterTestNamespace20261122.expect(codes, barqFlutterTestNamespace20261122.isNot(barqFlutterTestNamespace20261122.contains('+1787')));
  });

  barqFlutterTestNamespace20261122.test('saved contact comparison normalizes Arabic digits and phone punctuation', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
      '967770000001',
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.normalizeBarqContactPhoneDigits('+967 77 000 0001'),
      barqApp.normalizeBarqContactPhoneDigits('+٩٦٧ (٧٧) ٠٠٠-٠٠٠١'),
    );
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqContactPhoneDigits('---'), barqFlutterTestNamespace20261122.isEmpty);
  });

  barqFlutterTestNamespace20261122.test('conversation search barqFlutterTestNamespace20261122.matches message text and sender case-insensitively', () {
    final messages = [
      {'id': '1', 'body': 'مرحبا يا صديقي', 'display_name': 'Ali'},
      {'id': '2', 'body': 'Good morning', 'display_name': 'Sara'},
      {'id': '3', 'body': 'رسالة أخرى', 'display_name': 'Ali'},
    ];

    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, 'صديقي').map((m) => m['id']), ['1']);
    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, 'ALI').map((m) => m['id']), ['1', '3']);
    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, 'not found'), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(barqApp.searchConversationMessages(messages, '   '), barqFlutterTestNamespace20261122.isEmpty);
  });

  barqFlutterTestNamespace20261122.test('offline sync pauses only for network failures, not one rejected message', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineSyncShouldPause(Exception('NETWORK_DIAGNOSTIC: SocketException')), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineSyncShouldPause(Exception('Reply target not found')), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineSyncShouldPause(Exception('Message is too long')), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('Nearby inbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'friend-1',
      'receiver_id': 'me',
      'body': 'hello',
    };
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('offline reconciliation removes only an exact server copy', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
      {'id': 'b1b2c3d4e5f60708a1b2c3d4e5f60708', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'keep me'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'hello'},
    ];
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), [queued.last]);
  });

  barqFlutterTestNamespace20261122.test('accepted outbox removal preserves a barqFlutterTestNamespace20261122.same-ID entry with changed content or reply target', () {
    final accepted = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
      'reply_to_id': 'reply-a',
    };
    final changed = {...accepted, 'reply_to_id': 'reply-b'};
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted, changed], accepted),
      [changed],
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqOfflineQueueWithoutExactMessage([accepted], accepted),
      barqFlutterTestNamespace20261122.isEmpty,
    );
  });

  barqFlutterTestNamespace20261122.test('offline reconciliation keeps a barqFlutterTestNamespace20261122.same-ID message when its content or parties differ', () {
    const id = 'a1b2c3d4e5f60708a1b2c3d4e5f60708';
    final queued = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'original'},
    ];
    final server = <Map<String, dynamic>>[
      {'id': id, 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'tampered'},
    ];
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, server), queued);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {...server.single, 'sender_id': 'other', 'body': 'original'},
    ]), queued);
  });

  barqFlutterTestNamespace20261122.test('offline queue capacity rejects the first item beyond the limit', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(0), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(199), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(200), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(201), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineQueueIsFull(3, limit: 3), barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.test('offline queue decoding preserves empty queues and rejects corrupted data', () {
    barqFlutterTestNamespace20261122.expect(barqApp.decodeBarqOfflineQueue(null), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(barqApp.decodeBarqOfflineQueue(''), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(barqApp.decodeBarqOfflineQueue('[{"id":"m1","body":"hello"}]'), [
      {'id': 'm1', 'body': 'hello'},
    ]);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('{bad json'), throwsFormatException);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('{"id":"m1"}'), throwsFormatException);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, null]'), throwsFormatException);
    barqFlutterTestNamespace20261122.expect(() => barqApp.decodeBarqOfflineQueue('[{"id":"m1"}, "bad-entry"]'), throwsFormatException);
  });

  barqFlutterTestNamespace20261122.test('Nearby outbox duplicate IDs must match sender, receiver, and body', () {
    final original = <String, dynamic>{
      'id': 'a1b2c3d4e5f60708a1b2c3d4e5f60708',
      'sender_id': 'me',
      'receiver_id': 'friend-1',
      'body': 'hello',
    };
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, Map<String, dynamic>.from(original)), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'body': 'tampered'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'sender_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineIncomingMessageMatches(original, {...original, 'receiver_id': 'other'}), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('offline queue reconciliation removes exact barqFlutterTestNamespace20261122.matches found on any server page', () {
    final queued = [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
      {'id': 'offline-new', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'بانتظار المزامنة'},
    ];
    final remaining = barqApp.barqOfflineItemsNotOnServerPage(queued, [
      {'id': 'offline-old', 'sender_id': 'me', 'receiver_id': 'friend-1', 'body': 'وصلت دون إنترنت'},
    ]);

    barqFlutterTestNamespace20261122.expect(remaining.map((item) => item['id']).toList(), ['offline-new']);
    barqFlutterTestNamespace20261122.expect(barqApp.barqOfflineItemsNotOnServerPage(queued, []), barqFlutterTestNamespace20261122.same(queued));
  });

  barqFlutterTestNamespace20261122.test('message merge deduplicates by id and keeps chronological order', () {
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

    barqFlutterTestNamespace20261122.expect(merged.map((message) => message['id']).toList(), ['m1', 'm2', 'm3']);
    barqFlutterTestNamespace20261122.expect(merged[1]['body'], 'second updated');
  });

  barqFlutterTestNamespace20261122.test('barqApp.field helper supports API snake_case and camelCase fields', () {
    barqFlutterTestNamespace20261122.expect(barqApp.field({'display_name': 'برق'}, ['displayName', 'display_name']), 'برق');
    barqFlutterTestNamespace20261122.expect(barqApp.field({}, ['username'], 'مستخدم'), 'مستخدم');
  });

  barqFlutterTestNamespace20261122.test('profile photo path is resolved for group payloads with snake_case fields', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.profilePhotoPath({
        'sender_id': 'user/with space',
        'photo_updated_at': '2026-11-20 12:00:00',
      }),
      '/api/profile/photo/user%2Fwith%20space',
    );
    barqFlutterTestNamespace20261122.expect(barqApp.profilePhotoPath({'id': 'without-photo'}), barqFlutterTestNamespace20261122.isEmpty);
    barqFlutterTestNamespace20261122.expect(
      barqApp.profilePhotoPath({'id': 'friend-1', 'photo_url': '/api/profile/photo/friend-1'}),
      '/api/profile/photo/friend-1',
    );
  });


  barqFlutterTestNamespace20261122.test('group roles limit promotion to owners and preserve the owner account', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: false), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('owner', targetIsOwner: true), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('admin', targetIsOwner: false), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanManageGroupRoles('member', targetIsOwner: false), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('group removal permissions prevent admins removing peers or owners', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'member', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('admin', 'admin', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('member', 'member', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: true, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanRemoveGroupMember('owner', 'member', targetIsOwner: false, targetIsSelf: true),
      barqFlutterTestNamespace20261122.isFalse,
    );
  });

  barqFlutterTestNamespace20261122.test('only an owner can transfer group ownership to another non-owner member', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isTrue,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('admin', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('member', targetIsOwner: false, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: true, targetIsSelf: false),
      barqFlutterTestNamespace20261122.isFalse,
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqCanTransferGroupOwnership('owner', targetIsOwner: false, targetIsSelf: true),
      barqFlutterTestNamespace20261122.isFalse,
    );
  });

  barqFlutterTestNamespace20261122.test('group members can leave themselves but the owner cannot leave without transfer', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: false), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanLeaveGroup(isSelf: true, isOwner: true), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanLeaveGroup(isSelf: false, isOwner: false), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.testWidgets('public profile page shows the selected contact details', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.text('الملف الشخصي'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('صديق برق'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('@barq_friend'), findsNWidgets(2));
    barqFlutterTestNamespace20261122.expect(find.text('+967700000001'), findsOneWidget);
    // ListView builds off-screen children lazily; scroll to materialize the actions.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(find.text('حفظ الرقم في جهات الاتصال'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('إرسال رسالة'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إرسال رسالة'),
    );
    barqFlutterTestNamespace20261122.expect(sendButton.onPressed, barqFlutterTestNamespace20261122.isNotNull);
  });


  barqFlutterTestNamespace20261122.testWidgets('public profile disables messaging for the current user', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(sendButton.onPressed, barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.testWidgets('public profile accepts nested API user and hides message action by default', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.text('عضو المجموعة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('@group_member'), findsNWidgets(2));
    barqFlutterTestNamespace20261122.expect(find.text('إرسال رسالة'), findsNothing);
  });

  barqFlutterTestNamespace20261122.test('ephemeral messages disappear at their first-read expiry deadline', () {
    final now = DateTime.utc(2026, 11, 20, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final visible = barqApp.filterExpiredEphemeralMessages([
      {'id': 'regular', 'body': 'يبقى', 'is_ephemeral': false},
      {'id': 'unread', 'body': 'بانتظار القراءة', 'is_ephemeral': true},
      {'id': 'active', 'body': 'ينتهي لاحقًا', 'is_ephemeral': true, 'delete_at': nowSeconds + 10},
      {'id': 'expired', 'body': 'انتهى', 'is_ephemeral': true, 'delete_at': nowSeconds},
      {'id': 'expired-string', 'body': 'انتهى أيضًا', 'is_ephemeral': true, 'delete_at': (nowSeconds - 1).toString()},
    ], now: now);

    barqFlutterTestNamespace20261122.expect(visible.map((message) => message['id']).toList(),
        ['regular', 'unread', 'active']);
  });
  barqFlutterTestNamespace20261122.testWidgets('own message actions allow copying and confirmed deletion', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('نسخ الرسالة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('حذف الرسالة'), findsOneWidget);

    await tester.tap(find.text('حذف الرسالة'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(find.text('حذف الرسالة؟'), findsOneWidget);
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(deleted, barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.testWidgets('other users message actions do not expose delete', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('نسخ الرسالة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('حذف الرسالة'), findsNothing);
  });

  barqFlutterTestNamespace20261122.test('quoted reply preview is bounded and handles attachment references', () {
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': 'رسالة مقتبسة'}), 'رسالة مقتبسة');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': List.filled(130, 'x').join()}).length, 121);
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachmentId":"a1"}'}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': '{"attachment_id":"a2"}'}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': '{"fileName":"photo.jpg"}'}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': {'attachmentId': 'a3'}}), 'مرفق');
    barqFlutterTestNamespace20261122.expect(barqApp.messageReplyPreview({'reply_to_body': ''}), 'رسالة');
  });

  barqFlutterTestNamespace20261122.testWidgets('message edit dialog returns trimmed replacement text', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('تعديل الرسالة'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  النص الجديد  ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(saved, 'النص الجديد');
  });

  barqFlutterTestNamespace20261122.testWidgets('message action menu invokes the reply callback', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('الرد على الرسالة'), findsOneWidget);
    await tester.tap(find.text('الرد على الرسالة'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(selected?['id'], 'reply-1');
  });


  barqFlutterTestNamespace20261122.test('message reaction normalization preserves emoji and reacting user IDs', () {
    final normalized = barqApp.normalizeMessageReactions([
      {'emoji': '❤️', 'user_id': 'u1'},
      {'emoji': '🔥', 'user_id': 'u2'},
    ]);
    barqFlutterTestNamespace20261122.expect(normalized, barqFlutterTestNamespace20261122.hasLength(2));
    barqFlutterTestNamespace20261122.expect(normalized.first['emoji'], '❤️');
    barqFlutterTestNamespace20261122.expect(normalized.last['user_id'], 'u2');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeMessageReactions(null), barqFlutterTestNamespace20261122.isEmpty);
  });

  barqFlutterTestNamespace20261122.testWidgets('reaction chips show counts and allow removing the current user reaction', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.text('❤️ 2'), findsOneWidget);
    await tester.tap(find.text('❤️ 2'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(selectedEmoji, '❤️');
    barqFlutterTestNamespace20261122.expect(removing, barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.testWidgets('message action sheet exposes reaction and pin actions', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('إضافة تفاعل'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('تثبيت الرسالة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('حفظ في الذكريات الخاصة'), findsOneWidget);
  });

  barqFlutterTestNamespace20261122.test('media duration formatter supports minute and hour lengths', () {
    barqFlutterTestNamespace20261122.expect(barqApp.formatBarqMediaDuration(const Duration(seconds: 0)), '00:00');
    barqFlutterTestNamespace20261122.expect(barqApp.formatBarqMediaDuration(const Duration(minutes: 2, seconds: 9)), '02:09');
    barqFlutterTestNamespace20261122.expect(barqApp.formatBarqMediaDuration(const Duration(hours: 1, minutes: 3, seconds: 5)), '1:03:05');
  });

  barqFlutterTestNamespace20261122.test('message links extract only unique safe web URLs and normalize www links', () {
    final links = barqApp.extractBarqLinks(
      'زور https://example.com/path، ثم www.openai.com وبعدها https://example.com/path',
    );
    barqFlutterTestNamespace20261122.expect(links, [
      Uri.parse('https://example.com/path'),
      Uri.parse('https://www.openai.com'),
    ]);
  });

  barqFlutterTestNamespace20261122.test('message link extraction ignores non-web schemes', () {
    barqFlutterTestNamespace20261122.expect(barqApp.extractBarqLinks('javascript:alert(1) file:///tmp/a https://safe.example'), [
      Uri.parse('https://safe.example'),
    ]);
  });

  barqFlutterTestNamespace20261122.testWidgets('conversation summary waits for explicit consent before sending messages', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(requests, 0);
    barqFlutterTestNamespace20261122.expect(find.text('إنشاء الملخص'), findsOneWidget);

    await tester.tap(find.text('إنشاء الملخص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    barqFlutterTestNamespace20261122.expect(requests, 1);
    barqFlutterTestNamespace20261122.expect(find.text('ملخص اختباري'), findsOneWidget);
  });

  barqFlutterTestNamespace20261122.testWidgets('conversation tools sheet exposes chat tools outside app settings', (tester) async {
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
    barqFlutterTestNamespace20261122.expect(find.text('أدوات المحادثة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('البحث في المحادثة'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.text('الرسائل المثبتة'), findsOneWidget);

    await tester.tap(find.text('الرسائل المثبتة'));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(selectedTool, 'pinned');
  });

  barqFlutterTestNamespace20261122.test('private and group message text share the server 5000-character limit', () {
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed('رسالة قصيرة'), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed('  رسالة قصيرة  '), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed(''), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed('   '), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed(List.filled(5000, 'س').join()), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqMessageTextAllowed(List.filled(5001, 'س').join()), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('translation failures become retryable after a cooldown', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final retryAfter = {'message-1': now.add(const Duration(minutes: 1))};
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter, now: now), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('message-1', retryAfter,
        now: now.add(const Duration(minutes: 1))), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('message-2', retryAfter, now: now), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqTranslationRetryAllowed('', retryAfter, now: now), barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('audio transcription enforces the worker two-megabyte limit', () {
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(0), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(1), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqTranscriptionSizeAllowed(2 * 1024 * 1024 + 1), barqFlutterTestNamespace20261122.isFalse);
  });


  barqFlutterTestNamespace20261122.test('SPARK media extensions map to exact supported MIME types', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('jpg'), 'image/jpeg');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('.JPEG'), 'image/jpeg');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('png'), 'image/png');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('webp'), 'image/webp');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('gif'), 'image/gif');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('mp4'), 'video/mp4');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('webm'), 'video/webm');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('MOV'), 'video/quicktime');
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType('exe'), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqSparkMediaContentType(''), barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.test('SPARK media client size limit rejects empty and oversized files', () {
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(0), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(1), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.isBarqSparkMediaSizeAllowed(60 * 1024 * 1024 + 1), barqFlutterTestNamespace20261122.isFalse);
  });


  barqFlutterTestNamespace20261122.test('private memory photo uploads continue after an individual failure', () async {
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

    barqFlutterTestNamespace20261122.expect(attempted, ['one.jpg', 'two.png', 'three.webp']);
    barqFlutterTestNamespace20261122.expect(failures, ['two.png']);
  });

  barqFlutterTestNamespace20261122.testWidgets('private memory load error explains retry instead of showing an empty vault', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: barqApp.PrivateMemoryLoadError(onRetry: () => retried = true),
        ),
      ),
    );

    barqFlutterTestNamespace20261122.expect(find.text('تعذر تحميل ذكرياتك'), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.textContaining('لم نحذف ذكرياتك المحفوظة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    barqFlutterTestNamespace20261122.expect(retried, barqFlutterTestNamespace20261122.isTrue);
  });

  barqFlutterTestNamespace20261122.testWidgets('private memory photo gallery shows a safe empty state without paging', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.byType(PageView), findsNothing);
    barqFlutterTestNamespace20261122.expect(find.textContaining('/'), findsNothing);
  });

  barqFlutterTestNamespace20261122.testWidgets('private memory photo gallery pages through multiple zoomable photos', (tester) async {
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

    barqFlutterTestNamespace20261122.expect(find.byType(PageView), findsOneWidget);
    barqFlutterTestNamespace20261122.expect(find.byType(InteractiveViewer), findsWidgets);
    barqFlutterTestNamespace20261122.expect(visiblePage, 0);
    barqFlutterTestNamespace20261122.expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    barqFlutterTestNamespace20261122.expect(visiblePage, 1);
    barqFlutterTestNamespace20261122.expect(find.text('2 / 3'), findsOneWidget);
  });


  barqFlutterTestNamespace20261122.test('BARQ has exactly the four approved visual identities', () {
    barqFlutterTestNamespace20261122.expect(BarqIdentity.values, [
      BarqIdentity.blueLightning,
      BarqIdentity.butterfly,
      BarqIdentity.purpleShadow,
      BarqIdentity.skyJewel,
    ]);
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.blueLightning), 'البرق الأزرق');
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.butterfly), 'الفراشة');
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.purpleShadow), 'الظل البنفسجي');
    barqFlutterTestNamespace20261122.expect(BarqIdentity.label(BarqIdentity.skyJewel), 'الجوهرة السماوية');
  });

  barqFlutterTestNamespace20261122.test('BARQ identity palettes keep four distinct readable theme foundations', () {
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
    barqFlutterTestNamespace20261122.expect(BarqIdentity.values, barqFlutterTestNamespace20261122.hasLength(4));
    barqFlutterTestNamespace20261122.expect(palettes.map((p) => p.background).toSet().length, 4);
    barqFlutterTestNamespace20261122.expect(palettes.map((p) => p.primary).toSet().length, 4);
    for (final palette in palettes) {
      barqFlutterTestNamespace20261122.expect(palette.text, barqFlutterTestNamespace20261122.isNot(palette.background));
      barqFlutterTestNamespace20261122.expect(palette.primary, barqFlutterTestNamespace20261122.isNot(palette.background));
      barqFlutterTestNamespace20261122.expect(palette.secondary, barqFlutterTestNamespace20261122.isNot(palette.surface));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.text, palette.background), greaterThanOrEqualTo(7));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.text, palette.surface), greaterThanOrEqualTo(7));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.mutedText, palette.surface), greaterThanOrEqualTo(4.5));
      barqFlutterTestNamespace20261122.expect(contrastRatio(palette.primary, palette.surface), greaterThanOrEqualTo(4.5));
    }
    final blue = BarqIdentityPalette.forIdentity(BarqIdentity.blueLightning);
    barqFlutterTestNamespace20261122.expect(blue.primary, const Color(0xFFD6AD55));
    barqFlutterTestNamespace20261122.expect(blue.secondary, const Color(0xFF168BFF));
    barqFlutterTestNamespace20261122.expect(blue.background, const Color(0xFF090909));
    barqFlutterTestNamespace20261122.expect(blue.surface, const Color(0xFF171717));
  });

  barqFlutterTestNamespace20261122.test('FCM token normalization trims valid tokens and rejects invalid values', () {
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken('  fcm-token-123  '), 'fcm-token-123');
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(null), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(''), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken('   '), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken('token with spaces'), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(List.filled(4097, 'x').join()), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.normalizeBarqFcmToken(List.filled(4096, 'x').join()), barqFlutterTestNamespace20261122.hasLength(4096));
  });

  barqFlutterTestNamespace20261122.test('foreground push uses generic labels and respects category preferences', () {
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqForegroundPushLabel(
        {'type': 'direct_message', 'body': 'secret message', 'sender': 'Private Name'},
        {'messages': true},
      ),
      'وصلتك رسالة جديدة',
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqForegroundPushLabel({'type': 'group_message', 'body': 'secret'}, {'groups': true}),
      'وصلتك رسالة جديدة في مجموعة',
    );
    barqFlutterTestNamespace20261122.expect(
      barqApp.barqForegroundPushLabel({'type': 'status_update', 'body': 'private'}, {'statuses': true}),
      'هناك لحظة جديدة في SPARK',
    );
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message'}, {'messages': false}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'group_message'}, {'groups': false}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'status_update'}, {'statuses': false}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'direct_message', 'ephemeral': true}, {'messages': true}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'group_message', 'temporary': 'true'}, {'groups': true}), barqFlutterTestNamespace20261122.isNull);
    barqFlutterTestNamespace20261122.expect(barqApp.barqForegroundPushLabel({'type': 'unknown'}, {}), barqFlutterTestNamespace20261122.isNull);
  });

  barqFlutterTestNamespace20261122.test('FCM logout revocation runs only with session and valid token', () async {
    String? revoked;
    final success = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: '  device-token  ',
      revoke: (value) async { revoked = value; },
    );
    barqFlutterTestNamespace20261122.expect(success, barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(revoked, 'device-token');

    revoked = null;
    final noSession = await barqApp.revokeBarqFcmTokenSafely(
      authToken: null,
      fcmToken: 'device-token',
      revoke: (value) async { revoked = value; },
    );
    barqFlutterTestNamespace20261122.expect(noSession, barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(revoked, barqFlutterTestNamespace20261122.isNull);

    final invalidToken = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'invalid token',
      revoke: (value) async { revoked = value; },
    );
    barqFlutterTestNamespace20261122.expect(invalidToken, barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(revoked, barqFlutterTestNamespace20261122.isNull);

    final networkFailure = await barqApp.revokeBarqFcmTokenSafely(
      authToken: 'session-token',
      fcmToken: 'device-token',
      revoke: (_) async { throw Exception('offline'); },
    );
    barqFlutterTestNamespace20261122.expect(networkFailure, barqFlutterTestNamespace20261122.isFalse);
  });

  barqFlutterTestNamespace20261122.test('FCM registration requires authorized or provisional notification permission', () {
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.authorized), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.provisional), barqFlutterTestNamespace20261122.isTrue);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.denied), barqFlutterTestNamespace20261122.isFalse);
    barqFlutterTestNamespace20261122.expect(barqApp.barqCanRegisterFcmToken(AuthorizationStatus.notDetermined), barqFlutterTestNamespace20261122.isFalse);
  });

}
