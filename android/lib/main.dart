import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';

import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:app_links/app_links.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'barq_identity.dart';

const Color gold = Color(0xFFD6AD55);
const Color dark = Color(0xFF090909);
const Color electricBlue = Color(0xFF168BFF);
const Color glass = Color(0xCC171B24);
// Production remains the safe default. Select isolated preview origins at build time
// without editing source: --dart-define=BARQ_API_BASE=https://<preview-api>.example
const String apiBase = String.fromEnvironment(
  'BARQ_API_BASE',
  defaultValue: 'https://siraj-api-2026.vercel.app',
);
// Route media through the same public API origin by default. Resumable 1 MiB
// chunks keep each request below the Vercel Function body limit and avoid a
// second workers.dev hostname on restricted mobile networks. A separate media
// origin is opt-in only for isolated diagnostics via BARQ_MEDIA_BASE.
const String mediaWorkerBase = String.fromEnvironment(
  'BARQ_MEDIA_BASE',
  defaultValue: 'https://siraj-api-2026.vercel.app',
);
const int maxAttachmentBytes = 60 * 1024 * 1024;

String? barqSparkMediaContentType(String extension) {
  final value = extension.trim().toLowerCase();
  switch (value.startsWith('.') ? value.substring(1) : value) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mov':
      return 'video/quicktime';
    default:
      return null;
  }
}

bool isBarqSparkMediaSizeAllowed(int byteLength) =>
    byteLength > 0 && byteLength <= maxAttachmentBytes;
const int maxTranscriptionBytes = 2 * 1024 * 1024;

bool isBarqTranscriptionSizeAllowed(int byteLength) =>
    byteLength > 0 && byteLength <= maxTranscriptionBytes;

/// Allows retrying a failed on-device translation after a short cooldown.
bool barqTranslationRetryAllowed(
  String messageId,
  Map<String, DateTime> retryAfter, {
  DateTime? now,
}) {
  if (messageId.isEmpty) return false;
  final retryAt = retryAfter[messageId];
  return retryAt == null || !retryAt.isAfter(now ?? DateTime.now());
}

bool isBarqMessageTextAllowed(String value) =>
    value.trim().isNotEmpty && value.trim().length <= 5000;

bool barqCanManageGroupRoles(String actorRole, {required bool targetIsOwner}) =>
    actorRole == 'owner' && !targetIsOwner;

bool barqCanRemoveGroupMember(
  String actorRole,
  String targetRole, {
  required bool targetIsOwner,
  required bool targetIsSelf,
}) =>
    !targetIsOwner &&
    !targetIsSelf &&
    (actorRole == 'owner' || (actorRole == 'admin' && targetRole == 'member'));

bool barqCanLeaveGroup({required bool isSelf, required bool isOwner}) =>
    isSelf && !isOwner;

bool barqCanTransferGroupOwnership(
  String actorRole, {
  required bool targetIsOwner,
  required bool targetIsSelf,
}) =>
    actorRole == 'owner' && !targetIsOwner && !targetIsSelf;

const int proxyMediaThresholdBytes = 4 * 1024 * 1024;

const storage = FlutterSecureStorage();

/// إعدادات الميزات المحلية التي لا تحتاج إلى اتصال بالخادم.
class BarqFeatures {
  static bool lightningMode = false;
  static bool autoTranslate = false;
  static const String _lightningKey = 'barq_lightning_mode';
  static const String _translationKey = 'barq_auto_translate';

  static Future<void> load() async {
    try {
      lightningMode = await storage.read(key: _lightningKey) == '1';
      autoTranslate = await storage.read(key: _translationKey) == '1';
    } catch (_) {
      // فشل قراءة إعداد محلي لا يمنع تشغيل التطبيق؛ تبقى الميزات الاختيارية متوقفة.
      lightningMode = false;
      autoTranslate = false;
    }
  }

  static Future<void> setLightningMode(bool enabled) async {
    await storage.write(key: _lightningKey, value: enabled ? '1' : '0');
    lightningMode = enabled;
  }

  static Future<void> setAutoTranslate(bool enabled) async {
    await storage.write(key: _translationKey, value: enabled ? '1' : '0');
    autoTranslate = enabled;
  }
}

/// يستخرج رمز الدعوة من رابط برق فقط، ويرفض الروابط الخارجية أو الرموز غير المطابقة.
String? barqInviteCodeFromUri(Uri uri) {
  if (uri.scheme != 'barq' ||
      uri.host != 'invite' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.fragment.isNotEmpty) {
    return null;
  }

  final segments = uri.pathSegments;
  final query = uri.queryParametersAll;
  String? rawCode;
  if (segments.length == 1 &&
      segments.single.isNotEmpty &&
      query.isEmpty) {
    rawCode = segments.single;
  } else if (segments.isEmpty &&
      query.length == 1 &&
      query['code']?.length == 1) {
    rawCode = query['code']!.single;
  } else {
    return null;
  }

  final code = rawCode.trim().toUpperCase();
  return RegExp(r'^[A-F0-9]{12}$').hasMatch(code) ? code : null;
}

/// يتحقق من هوية طرفي رسالة Nearby وحدودها قبل إدخالها إلى صندوق الرسائل المحلي.
bool isValidBarqNearbyTextPayload(
  Map<String, dynamic> payload, {
  required String peerId,
  required String currentUserId,
}) {
  final messageId = payload['id']?.toString() ?? '';
  final body = payload['body']?.toString() ?? '';
  return payload['kind'] == 'barq_text_message' &&
      payload['senderId']?.toString() == peerId &&
      payload['receiverId']?.toString() == currentUserId &&
      RegExp(r'^[a-f0-9]{32}$').hasMatch(messageId) &&
      body.trim().isNotEmpty &&
      body.length <= 5000;
}

/// أذونات Nearby Connections التي تتغير حسب إصدار Android.
List<String> barqNearbyPermissionNamesForAndroidSdk(int sdkInt) => [
  if (sdkInt <= 32) 'location',
  if (sdkInt >= 31) ...[
    'bluetoothAdvertise',
    'bluetoothConnect',
    'bluetoothScan',
  ] else
    'bluetooth',
  if (sdkInt >= 33) 'nearbyWifiDevices',
];

/// يتحقق من صلاحية رسالة Nearby الصادرة قبل إرسالها إلى جهاز آخر.
bool barqNearbyPayloadTransferFailed(PayloadStatus status) =>
    status == PayloadStatus.FAILURE || status == PayloadStatus.CANCELED;

bool isValidBarqNearbyOutgoingText({
  required String senderId,
  required String currentUserId,
  required String receiverId,
  required Set<String> knownContacts,
  required String messageId,
  required String body,
}) =>
    senderId == currentUserId &&
    receiverId.isNotEmpty &&
    knownContacts.contains(receiverId) &&
    RegExp(r'^[a-f0-9]{32}$').hasMatch(messageId) &&
    isBarqMessageTextAllowed(body);

/// استقبال روابط الدعوة barq://invite/CODE حتى عند فتح التطبيق من رابط خارجي.
class BarqInviteLinks {
  static final AppLinks _links = AppLinks();
  static StreamSubscription<Uri>? _subscription;
  static final ValueNotifier<String?> pendingCode = ValueNotifier<String?>(null);
  static const String _pendingKey = 'barq_pending_invite_code';

  static Future<void> initialize() async {
    _subscription ??= _links.uriLinkStream.listen((uri) => _handle(uri));
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) await _handle(initial);
    } catch (_) {}
    try {
      pendingCode.value = await storage.read(key: _pendingKey);
    } catch (_) {}
  }

  static Future<void> _handle(Uri uri) async {
    final code = barqInviteCodeFromUri(uri);
    if (code == null) return;
    pendingCode.value = code;
    try { await storage.write(key: _pendingKey, value: code); } catch (_) {}
  }

  static Future<void> clear() async {
    pendingCode.value = null;
    try { await storage.delete(key: _pendingKey); } catch (_) {}
  }
}

/// ترجمة محلية على الجهاز؛ النص الأصلي لا يُستبدل ولا يُرسل إلى الخادم.
class BarqTranslator {
  static Future<String> translateArabicEnglish(String original) async {
    final text = original.trim();
    if (text.isEmpty) return '';
    final containsArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    if (!containsArabic && !RegExp(r'[A-Za-z]').hasMatch(text)) return '';
    final translator = OnDeviceTranslator(
      sourceLanguage: containsArabic ? TranslateLanguage.arabic : TranslateLanguage.english,
      targetLanguage: containsArabic ? TranslateLanguage.english : TranslateLanguage.arabic,
    );
    try {
      return await translator.translateText(text);
    } finally {
      await translator.close();
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await BarqFeatures.load();
  await BarqIdentity.load();
  await BarqInviteLinks.initialize();
  runApp(const SirajApp());
}

/// تفعيل إذن الإشعارات وتسجيل رمز الجهاز بعد تسجيل الدخول.
class SirajPush {
  static bool _listening = false;

  static Future<void> register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await Api.registerDeviceToken(token);
      }
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          try {
            if (Api.token != null) await Api.registerDeviceToken(newToken);
          } catch (_) {}
        });
      }
    } catch (_) {
      // فشل الإشعارات لا يمنع الدخول أو استخدام التطبيق.
    }
  }
}

class SirajApp extends StatelessWidget {
  const SirajApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BarqIdentity>(
      valueListenable: BarqIdentity.selected,
      builder: (context, identity, _) {
        final palette = BarqIdentityPalette.forIdentity(identity);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'برق',
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: palette.background,
            colorScheme: ColorScheme.dark(
              primary: palette.primary,
              secondary: palette.secondary,
              surface: palette.surface,
              onPrimary: palette.onPrimary,
              onSecondary: palette.onSecondary,
            ),
            iconTheme: IconThemeData(color: palette.primary),
            progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.primary),
            dialogTheme: DialogThemeData(
              backgroundColor: palette.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: palette.surface,
              modalBackgroundColor: palette.surface,
              surfaceTintColor: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: palette.surface,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.primary, width: 1.5),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: palette.surface,
              foregroundColor: palette.text,
              surfaceTintColor: Colors.transparent,
            ),
            cardTheme: CardThemeData(
              color: palette.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: palette.border),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: palette.surface,
              indicatorColor: palette.secondary.withValues(alpha: .18),
              iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? palette.secondary : palette.mutedText,
              )),
              labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                color: states.contains(WidgetState.selected) ? palette.primary : palette.mutedText,
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              )),
            ),
            useMaterial3: true,
          ),
          home: const StartupPage(),
        );
      },
    );
  }
}

/// اتصال لحظي اختياري؛ REST يبقى المصدر الدائم للرسائل.
class SirajRealtime {
  SirajRealtime._();
  static final SirajRealtime instance = SirajRealtime._();
  static const String socketUrl = String.fromEnvironment(
    'BARQ_REALTIME_URL',
    defaultValue: '',
  );

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  WebSocket? _socket;
  Timer? _reconnectTimer;
  String? _token;
  bool _connecting = false;
  bool _stopped = true;
  int _retry = 0;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isConnected => _socket?.readyState == WebSocket.open;

  Future<void> start(String token) async {
    if (token.isEmpty) return;
    _token = token;
    _stopped = false;
    _retry = 0;
    _reconnectTimer?.cancel();
    await _connect();
  }

  Future<void> _connect() async {
    if (socketUrl.isEmpty || _stopped || _connecting || _token == null || isConnected) return;
    _connecting = true;
    try {
      final socket = await WebSocket.connect(
        socketUrl,
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 15));
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      _retry = 0;
      socket.pingInterval = const Duration(seconds: 25);
      socket.listen(
        (dynamic raw) {
          try {
            if (raw is String) {
              final value = jsonDecode(raw);
              if (value is Map<String, dynamic>) _events.add(value);
            }
          } catch (_) {
            // تجاهل أي إطار غير صالح دون إسقاط الاتصال.
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    _socket = null;
    if (_stopped || _token == null || _reconnectTimer?.isActive == true) return;
    final seconds = [1, 2, 4, 8, 15, 30][_retry.clamp(0, 5).toInt()];
    _retry = (_retry + 1).clamp(0, 5).toInt();
    _reconnectTimer = Timer(Duration(seconds: seconds), _connect);
  }

  Future<void> stop() async {
    _stopped = true;
    _token = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try { await socket.close(WebSocketStatus.normalClosure); } catch (_) {}
    }
  }
}

typedef PrivateMemoryPhotoUploader = Future<void> Function({
  required String memoryId,
  required List<int> bytes,
  required String fileName,
  required String contentType,
});

Future<List<String>> uploadPrivateMemoryPhotosSequentially({
  required String memoryId,
  required List<Map<String, dynamic>> photos,
  required PrivateMemoryPhotoUploader upload,
}) async {
  final failedFiles = <String>[];
  for (final photo in photos) {
    final fileName = photo['name'] as String? ?? 'صورة بدون اسم';
    try {
      await upload(
        memoryId: memoryId,
        bytes: photo['bytes'] as List<int>,
        fileName: fileName,
        contentType: photo['contentType'] as String,
      );
    } catch (_) {
      failedFiles.add(fileName);
    }
  }
  return failedFiles;
}

class Api {
  static String? token;
  static String? lastRecoveryCode;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$apiBase$path');
    late http.Response response;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers)
              .timeout(const Duration(seconds: 25));
          break;
        case 'DELETE':
          response = await http.delete(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ).timeout(const Duration(seconds: 25));
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          ).timeout(const Duration(seconds: 25));
          break;
        case 'PATCH':
          response = await http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          ).timeout(const Duration(seconds: 25));
          break;
        default:
          throw UnsupportedError('HTTP method is not supported: $method');
      }
    } catch (e) {
      throw Exception('NETWORK_DIAGNOSTIC: ${e.runtimeType}: $e');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data['error'] ?? data['message'] ?? 'حدث خطأ (${response.statusCode})';
      if (response.statusCode == 404 && message.toString().toLowerCase().contains('route')) {
        throw Exception('مسار غير موجود في الخادم: $method $path');
      }
      throw Exception(message.toString());
    }
    return data;
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await request('POST', '/api/login', body: {
      'username': username,
      'password': password,
    });
    token = data['token']?.toString();
    if (token == null || token!.isEmpty) throw Exception('لم يستلم التطبيق رمز الدخول من الخادم.');
    await storage.write(key: 'siraj_token', value: token);
    final user = _map(data['user']);
    await _cacheUser(user);
    return user;
  }

  static Future<Map<String, dynamic>> register({
    required String displayName,
    required String password,
    required String phone,
    String? inviteCode,
  }) async {
    lastRecoveryCode = null;
    final data = await request('POST', '/api/register', body: {
      'displayName': displayName,
      'password': password,
      'phone': phone,
      if (inviteCode != null && inviteCode.trim().isNotEmpty)
        'inviteCode': inviteCode.trim().toUpperCase(),
    });
    token = data['token']?.toString();
    if (token == null || token!.isEmpty) throw Exception('لم يستلم التطبيق رمز الدخول من الخادم.');
    lastRecoveryCode = data['recoveryCode']?.toString();
    await storage.write(key: 'siraj_token', value: token);
    final user = _map(data['user']);
    await _cacheUser(user);
    return user;
  }

  static Future<void> recoverPassword({
    required String identifier,
    required String recoveryCode,
    required String newPassword,
  }) async {
    await request('POST', '/api/password/recover', body: {
      'identifier': identifier.trim(),
      'recoveryCode': recoveryCode.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(),
      'newPassword': newPassword,
    });
  }

  static Future<String> rotateRecoveryCode(String currentPassword) async {
    final data = await request('POST', '/api/recovery-code', body: {
      'password': currentPassword,
    });
    final code = data['recoveryCode']?.toString();
    if (code == null || code.isEmpty) {
      throw Exception('لم يستلم التطبيق رمز الاسترداد من الخادم.');
    }
    return code;
  }

  static Future<Map<String, dynamic>> me() async {
    final user = _map((await request('GET', '/api/me'))['user']);
    await _cacheUser(user);
    return user;
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String displayName,
    required String phone,
  }) async => _map((await request('POST', '/api/profile', body: {
        'displayName': displayName.trim(),
        'phone': phone.trim(),
      }))['user']);

  static Future<void> uploadProfilePhoto(List<int> bytes, String contentType) async {
    final response = await http.post(
      Uri.parse('$apiBase/api/profile/photo/me'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': contentType,
      },
      body: bytes,
    ).timeout(const Duration(seconds: 45));
    dynamic decoded;
    try { decoded = jsonDecode(response.body); } catch (_) { decoded = <String, dynamic>{}; }
    final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((data['error'] ?? 'تعذر رفع صورة الملف الشخصي').toString());
    }
  }

  static Future<Map<String, dynamic>> privacy() async =>
      _map((await request('GET', '/api/privacy'))['privacy']);

  static Future<Map<String, dynamic>> savePrivacy({
    required bool searchable,
    required bool readReceipts,
  }) async => _map((await request('POST', '/api/privacy', body: {
        'searchable': searchable,
        'readReceipts': readReceipts,
      }))['privacy']);

  static Future<Map<String, dynamic>> notificationSettings() async =>
      _map((await request('GET', '/api/notification-settings'))['settings']);

  static Future<Map<String, dynamic>> saveNotificationSettings({
    required bool messages, required bool groups, required bool statuses,
  }) async => _map((await request('POST', '/api/notification-settings', body: {
        'messages': messages, 'groups': groups, 'statuses': statuses,
      }))['settings']);

  static Future<Map<String, dynamic>> referrals() async =>
      _map(await request('GET', '/api/referrals'));

  static Future<List<Map<String, dynamic>>> friends() async =>
      _list((await request('GET', '/api/friends'))['friends']);

  static Future<List<Map<String, dynamic>>> search(String query) async =>
      _list((await request(
        'GET',
        '/api/users/search?q=${Uri.encodeQueryComponent(query)}',
      ))['users']);

  // إضافة مباشرة إلى جهات الاتصال دون طلب صداقة.
  static Future<void> addContact(String userId) async {
    await request('POST', '/api/contacts', body: {'userId': userId});
  }

  static Future<List<Map<String, dynamic>>> matchPhoneContacts(
    List<String> phones,
  ) async => _list((await request('POST', '/api/contacts/match', body: {
        'phones': phones.take(500).toList(),
      }))['users']);

  static Future<Map<String, dynamic>> messagesPage(
    String friendId, {
    int limit = 100,
    Map<String, dynamic>? before,
  }) async {
    final query = <String, String>{
      'with': friendId,
      'limit': limit.toString(),
      if (before?['before'] != null) 'before': before!['before'].toString(),
      if (before?['beforeId'] != null) 'beforeId': before!['beforeId'].toString(),
    };
    return request('GET', '/api/messages?${Uri(queryParameters: query).query}');
  }

  static Future<List<Map<String, dynamic>>> messages(String friendId) async =>
      _list((await messagesPage(friendId))['messages']);

  static Future<Map<String, dynamic>> searchPrivateMessages(
    String friendId, String query, {int limit = 30, Map<String, dynamic>? before}
  ) async {
    final params = Uri(queryParameters: {
      'with': friendId, 'q': query.trim(), 'limit': limit.toString(),
      if (before?['before'] != null) 'before': before!['before'].toString(),
      if (before?['beforeId'] != null) 'beforeId': before!['beforeId'].toString(),
    }).query;
    return request('GET', '/api/messages/search?$params');
  }

  static Future<void> sendMessage(String receiverId, String body, {String? clientMessageId, String? replyToId}) async {
    await request('POST', '/api/messages', body: {
      'receiverId': receiverId,
      'body': body,
      if (clientMessageId != null && clientMessageId.isNotEmpty) 'clientMessageId': clientMessageId,
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
    });
  }

  /// رسائل مؤقتة منفصلة تمامًا عن جدول الرسائل العادي وإشعارات Firebase.
  static Future<void> sendEphemeralMessage(String receiverId, String body) async {
    await request('POST', '/api/ephemeral-messages', body: {
      'receiverId': receiverId,
      'body': body,
    });
  }

  static Future<List<Map<String, dynamic>>> ephemeralMessages(String friendId) async {
    final data = await request(
      'GET',
      '/api/ephemeral-messages?with=${Uri.encodeQueryComponent(friendId)}',
    );
    return _list(data['messages']).map((message) {
      final value = Map<String, dynamic>.from(message);
      final created = value['created_at'];
      if (created is num) {
        value['created_at'] = DateTime.fromMillisecondsSinceEpoch(
          created.toInt() * 1000,
          isUtc: true,
        ).toIso8601String();
      }
      value['is_ephemeral'] = true;
      return value;
    }).toList();
  }

  // تسجيل رمز جهاز المستخدم لدى الخادم لتهيئة الإشعارات لاحقاً.
  // يستدعى بعد الحصول على FCM token من Firebase Messaging.
  static Future<void> registerDeviceToken(String fcmToken) async {
    final value = fcmToken.trim();
    if (value.isEmpty) throw Exception('رمز الجهاز غير صالح.');
    await request('POST', '/api/devices/token', body: {
      'fcmToken': value,
    });
  }

  static Future<List<Map<String, dynamic>>> privateMemories() async =>
      _list((await request('GET', '/api/private-memories'))['memories']);

  static Future<Map<String, dynamic>> savePrivateMemory({
    required String content,
    String title = '',
    String sourceType = 'text',
  }) async => _map((await request('POST', '/api/private-memories', body: {
    'title': title,
    'content': content,
    'sourceType': sourceType,
  }))['memory']);

  static Future<Map<String, dynamic>> updatePrivateMemory({
    required String id,
    required String content,
    String title = '',
  }) async => _map((await request(
    'PATCH',
    '/api/private-memories/${Uri.encodeComponent(id)}',
    body: {'title': title, 'content': content},
  ))['memory']);

  static Future<void> deletePrivateMemory(String id) async {
    await request('DELETE', '/api/private-memories/${Uri.encodeComponent(id)}');
  }

  static Future<void> uploadPrivateMemoryPhoto({
    required String memoryId,
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw Exception('حجم صورة الذكرى يجب ألا يتجاوز 4 ميجابايت.');
    }
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(contentType)) {
      throw Exception('صيغة صورة الذكرى غير مدعومة.');
    }
    final response = await http.post(
      Uri.parse('$mediaWorkerBase/api/private-memories/${Uri.encodeComponent(memoryId)}/media'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': contentType,
        'X-File-Name': Uri.encodeComponent(fileName),
      },
      body: bytes,
    ).timeout(const Duration(minutes: 2));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((data['error'] ?? 'تعذر حفظ صورة الذكرى.').toString());
    }
  }

  static Future<List<Map<String, dynamic>>> statuses() async =>
      _list((await request('GET', '/api/statuses'))['statuses']);

  static Future<void> publishStatus(
    String content, {
    String backgroundKey = 'midnight',
    String textColorKey = 'white',
    String fontKey = 'modern',
  }) async {
    await request('POST', '/api/statuses', body: {
      'content': content,
      'backgroundKey': backgroundKey,
      'textColorKey': textColorKey,
      'fontKey': fontKey,
    });
  }

  static Future<String> publishSparkMedia({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String caption = '',
    String? statusId,
  }) async {
    if (BarqFeatures.lightningMode) {
      throw Exception('وضع البرق مفعّل: نشر الصور والفيديو متوقف مؤقتًا.');
    }
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw Exception('حجم الوسائط يجب ألا يتجاوز 60 ميجابايت.');
    }
    if (!RegExp(r'^(image/(jpeg|png|webp|gif)|video/(mp4|webm|quicktime))$').hasMatch(contentType)) {
      throw Exception('نوع الملف غير مدعوم في SPARK.');
    }
    final response = await http.post(
      Uri.parse('$mediaWorkerBase/api/statuses/media'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': contentType,
        'X-File-Name': Uri.encodeComponent(fileName),
        'X-Status-Caption': caption.trim(),
        if (statusId != null) 'X-Status-Id': statusId,
      },
      body: bytes,
    ).timeout(const Duration(minutes: 3));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((data['error'] ?? 'تعذر نشر الوسائط (${response.statusCode}).').toString());
    }
    final status = data['status'];
    if (status is Map && status['id'] != null) return status['id'].toString();
    throw Exception('لم يُرجع الخادم معرّف لحظة SPARK.');
  }

  static Future<void> markSparkViewed(String statusId) async {
    await request('POST', '/api/statuses/${Uri.encodeComponent(statusId)}/view');
  }

  static Future<List<Map<String, dynamic>>> sparkViewers(String statusId) async =>
      _list((await request('GET', '/api/statuses/${Uri.encodeComponent(statusId)}/viewers'))['viewers']);

  static Future<void> reactSparkStatus(String statusId, String emoji, {bool remove = false}) async {
    final path = '/api/statuses/${Uri.encodeComponent(statusId)}/reactions';
    if (remove) {
      await request('DELETE', '$path?emoji=${Uri.encodeQueryComponent(emoji)}');
    } else {
      await request('POST', path, body: {'emoji': emoji});
    }
  }

  static Future<List<Map<String, dynamic>>> sparkReplies(String statusId) async {
    final data = await request('GET', '/api/statuses/${Uri.encodeComponent(statusId)}/replies');
    final textReplies = _list(data['replies']).map((item) => {...item, 'kind': 'text'});
    final audioReplies = _list(data['audioReplies']).map((item) => {...item, 'kind': 'audio'});
    final combined = <Map<String, dynamic>>[...textReplies, ...audioReplies];
    combined.sort((a, b) => (a['createdAt'] ?? '').toString().compareTo((b['createdAt'] ?? '').toString()));
    return combined;
  }

  static Future<void> replyToSpark(String statusId, String body) async {
    await request('POST', '/api/statuses/${Uri.encodeComponent(statusId)}/replies', body: {'body': body});
  }

  static Future<void> uploadSparkAudioReply({
    required String statusId,
    required List<int> bytes,
    required int durationMs,
  }) async {
    if (BarqFeatures.lightningMode) {
      throw Exception('وضع البرق مفعّل: إرسال الردود الصوتية متوقف مؤقتًا.');
    }
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw Exception('حجم الرد الصوتي يجب ألا يتجاوز 5 ميجابايت.');
    }
    if (durationMs < 1000 || durationMs > 60000) {
      throw Exception('مدة الرد الصوتي يجب أن تكون بين ثانية و60 ثانية.');
    }
    final uri = Uri.parse('$mediaWorkerBase/api/statuses/${Uri.encodeComponent(statusId)}/audio-replies');
    final response = await http.post(uri, headers: {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'audio/mp4',
      'X-Audio-Duration-Ms': durationMs.toString(),
    }, body: bytes).timeout(const Duration(minutes: 2));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((data['error'] ?? 'تعذر إرسال الرد الصوتي (${response.statusCode}).').toString());
    }
  }

  static Future<Uint8List> fetchSparkAudioReplyBytes(String statusId, String replyId) async {
    final uri = Uri.parse('$mediaWorkerBase/api/statuses/${Uri.encodeComponent(statusId)}/audio-replies/${Uri.encodeComponent(replyId)}');
    final response = await http.get(uri, headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    }).timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر تشغيل الرد الصوتي (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  static Uri sparkMediaUri(String attachmentId) => Uri.parse(
    '$mediaWorkerBase/api/media/${Uri.encodeComponent(attachmentId)}',
  );

  static Future<List<Map<String, dynamic>>> groups() async =>
      _list((await request('GET', '/api/groups'))['groups']);

  static Future<Map<String, dynamic>> createGroup(String name, String description) async =>
      _map((await request('POST', '/api/groups', body: {
        'name': name,
        'description': description,
      }))['group']);

  static Future<void> addGroupMember(String groupId, String userId) async {
    await request('POST', '/api/groups/$groupId/members', body: {'userId': userId});
  }

  static Future<void> setGroupMemberRole(
    String groupId, String userId, String role,
  ) async {
    await request(
      'POST',
      '/api/groups/$groupId/members/$userId/role',
      body: {'role': role},
    );
  }

  static Future<void> removeGroupMember(String groupId, String userId) async {
    await request('DELETE', '/api/groups/$groupId/members/$userId');
  }

  static Future<void> transferGroupOwnership(String groupId, String userId) async {
    await request(
      'POST',
      '/api/groups/$groupId/owner',
      body: {'userId': userId},
    );
  }

  static Future<List<Map<String, dynamic>>> groupMembers(String groupId) async =>
      _list((await request('GET', '/api/groups/$groupId/members'))['members']);

  static Future<Map<String, dynamic>> groupMessagesPage(
    String groupId, {
    int limit = 100,
    Map<String, dynamic>? before,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      if (before?['before'] != null) 'before': before!['before'].toString(),
      if (before?['beforeId'] != null) 'beforeId': before!['beforeId'].toString(),
    };
    return request('GET', '/api/groups/$groupId/messages?${Uri(queryParameters: query).query}');
  }

  static Future<List<Map<String, dynamic>>> groupMessages(String groupId) async =>
      _list((await groupMessagesPage(groupId))['messages']);

  static Future<Map<String, dynamic>> searchGroupMessages(
    String groupId, String query, {int limit = 30, Map<String, dynamic>? before}
  ) async {
    final params = Uri(queryParameters: {
      'q': query.trim(), 'limit': limit.toString(),
      if (before?['before'] != null) 'before': before!['before'].toString(),
      if (before?['beforeId'] != null) 'beforeId': before!['beforeId'].toString(),
    }).query;
    return request('GET', '/api/groups/${Uri.encodeComponent(groupId)}/messages/search?$params');
  }

  static Future<void> sendGroupMessage(String groupId, String body, {String? replyToId}) async {
    await request('POST', '/api/groups/$groupId/messages', body: {
      'body': body,
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
    });
  }

  static Future<void> reactPrivateMessage(String messageId, String emoji, {bool remove = false}) async {
    final path = '/api/messages/${Uri.encodeComponent(messageId)}/reactions';
    if (remove) {
      await request('DELETE', '$path?emoji=${Uri.encodeQueryComponent(emoji)}');
    } else {
      await request('POST', path, body: {'emoji': emoji});
    }
  }

  static Future<void> pinPrivateMessage(String messageId, {bool pinned = true}) async {
    await request(pinned ? 'POST' : 'DELETE',
      '/api/messages/${Uri.encodeComponent(messageId)}/pin');
  }

  static Future<void> reactGroupMessage(String groupId, String messageId, String emoji, {bool remove = false}) async {
    final path = '/api/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}/reactions';
    if (remove) {
      await request('DELETE', '$path?emoji=${Uri.encodeQueryComponent(emoji)}');
    } else {
      await request('POST', path, body: {'emoji': emoji});
    }
  }

  static Future<void> pinGroupMessage(String groupId, String messageId, {bool pinned = true}) async {
    await request(pinned ? 'POST' : 'DELETE',
      '/api/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}/pin');
  }

  static Future<void> editPrivateMessage(String messageId, String body) async {
    await request('PATCH', '/api/messages/${Uri.encodeComponent(messageId)}', body: {'body': body});
  }

  static Future<void> editGroupMessage(String groupId, String messageId, String body) async {
    await request(
      'PATCH',
      '/api/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}',
      body: {'body': body},
    );
  }

  static Future<void> deletePrivateMessage(String messageId) async {
    await request('DELETE', '/api/messages/${Uri.encodeComponent(messageId)}');
  }

  static Future<void> deleteGroupMessage(String groupId, String messageId) async {
    await request(
      'DELETE',
      '/api/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}',
    );
  }

  static Future<Map<String, dynamic>> summarizePrivateConversation(String friendId) {
    return request('POST', '/api/messages/${Uri.encodeComponent(friendId)}/summary');
  }

  static Future<Map<String, dynamic>> summarizeGroupConversation(String groupId) {
    return request('POST', '/api/groups/${Uri.encodeComponent(groupId)}/summary');
  }

  static Future<void> _uploadAttachmentResumable({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? recipientId,
    String? groupId,
  }) async {
    final fingerprintInput = utf8.encode(
      '${recipientId ?? ''}|${groupId ?? ''}|$fileName|$contentType|${crypto.sha256.convert(bytes)}',
    );
    final resumeStorageKey = 'barq_upload_resume_${crypto.sha256.convert(fingerprintInput)}';
    final idempotencyKey = await storage.read(key: resumeStorageKey) ?? newBarqMessageId();
    await storage.write(key: resumeStorageKey, value: idempotencyKey);
    final start = await request('POST', '/api/media/uploads', body: {
      'size': bytes.length,
      'fileName': fileName,
      'contentType': contentType,
      if (recipientId != null) 'recipientId': recipientId,
      if (groupId != null) 'groupId': groupId,
      'idempotencyKey': idempotencyKey,
    });
    final session = start['session'];
    if (session is! Map) throw Exception('استجابة بدء رفع الملف غير صالحة.');
    final sessionId = session['id']?.toString() ?? '';
    if (sessionId.isEmpty) throw Exception('لم يُرجع الخادم معرّف جلسة الرفع.');
    if (session['state'] == 'completed') {
      await request('POST', '/api/media/uploads/${Uri.encodeComponent(sessionId)}/complete');
      await storage.delete(key: resumeStorageKey);
      return;
    }
    final totalChunks = (bytes.length + 1024 * 1024 - 1) ~/ (1024 * 1024);

    for (var chunkNumber = 1; chunkNumber <= totalChunks; chunkNumber++) {
      final startOffset = (chunkNumber - 1) * 1024 * 1024;
      final endOffset = math.min(startOffset + 1024 * 1024, bytes.length).toInt();
      final chunk = bytes.sublist(startOffset, endOffset);
      final uri = Uri.parse(
        '$apiBase/api/media/uploads/${Uri.encodeComponent(sessionId)}/chunks/$chunkNumber',
      );
      http.Response? response;
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          response = await http.put(uri, headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
            'Content-Length': chunk.length.toString(),
          }, body: chunk).timeout(const Duration(seconds: 90));
          if (response.statusCode >= 200 && response.statusCode < 300) break;
          if (response.statusCode < 500) {
            final decoded = jsonDecode(response.body);
            final message = decoded is Map ? decoded['error'] : null;
            throw Exception((message ?? 'تعذر رفع الجزء $chunkNumber').toString());
          }
          lastError = Exception('تعذر رفع الجزء $chunkNumber (${response.statusCode}).');
        } catch (error) {
          lastError = error;
          if (response != null && response.statusCode >= 400 && response.statusCode < 500) {
            rethrow;
          }
        }
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
      if (response == null || response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('توقف رفع الملف عند الجزء $chunkNumber ويمكن إعادة المحاولة. $lastError');
      }
    }

    final completed = await request(
      'POST',
      '/api/media/uploads/${Uri.encodeComponent(sessionId)}/complete',
    );
    final attachment = completed['attachment'];
    if (attachment is! Map || attachment['attachmentId'] == null) {
      throw Exception('اكتمل الرفع دون تأكيد بيانات المرفق.');
    }
    await storage.delete(key: resumeStorageKey);
  }

  static Future<void> uploadAttachment({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? recipientId,
    String? groupId,
  }) async {
    if (BarqFeatures.lightningMode) {
      throw Exception('وضع البرق مفعّل: إرسال الملفات والوسائط متوقف مؤقتًا.');
    }
    if ((recipientId == null) == (groupId == null)) {
      throw Exception('حدد محادثة فردية أو مجموعة واحدة.');
    }
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw Exception('حجم الملف يجب ألا يتجاوز 60 ميجابايت.');
    }
    // Preserve the existing fast path for files up to 4 MiB.
    if (bytes.length > proxyMediaThresholdBytes) {
      await _uploadAttachmentResumable(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        recipientId: recipientId,
        groupId: groupId,
      );
      return;
    }
    final uri = Uri.parse('$apiBase/api/media');
    final response = await http.post(uri, headers: {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': contentType,
      'X-File-Name': Uri.encodeComponent(fileName),
      if (recipientId != null) 'X-Recipient-Id': recipientId,
      if (groupId != null) 'X-Group-Id': groupId,
    }, body: bytes).timeout(const Duration(minutes: 3));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((data['error'] ?? 'تعذر إرسال الملف (${response.statusCode})').toString());
    }
  }

  // Try each configured media gateway once. By default mediaWorkerBase and
  // apiBase are identical, so retrying the same hostname would add delay without
  // providing a real failover path.
  static Future<http.Response> _getMediaResponse(
    String attachmentId, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final bases = <String>[mediaWorkerBase, if (apiBase != mediaWorkerBase) apiBase];
    Object? lastError;
    for (final base in bases) {
      try {
        final response = await http.get(
          Uri.parse('$base/api/media/${Uri.encodeComponent(attachmentId)}'),
          headers: headers,
        ).timeout(timeout);
        if (response.statusCode < 500) return response;
        lastError = HttpException('Media gateway returned ${response.statusCode}');
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const HttpException('No media gateway is configured');
  }

  /// يجلب المرفق الصوتي المصرح به ثم يرسله مباشرة إلى مسار التفريغ الصوتي.
  /// لا يُحفظ الملف الصوتي أو النص الناتج في جدول الرسائل العادي.
  static Future<String> transcribeAttachment(String attachmentId, {String? expectedContentType}) async {
    final requestHeaders = {if (token != null) 'Authorization': 'Bearer $token'};
    final audioResponse = await _getMediaResponse(
      attachmentId,
      headers: requestHeaders,
      timeout: const Duration(minutes: 2),
    );
    if (audioResponse.statusCode < 200 || audioResponse.statusCode >= 300) {
      throw Exception('تعذر جلب التسجيل الصوتي (${audioResponse.statusCode}).');
    }
    final responseContentType = (audioResponse.headers['content-type'] ?? '').split(';').first.toLowerCase();
    final fallbackContentType = (expectedContentType ?? '').split(';').first.toLowerCase();
    final contentType = responseContentType.startsWith('audio/') ? responseContentType : fallbackContentType;
    if (!contentType.startsWith('audio/')) {
      throw Exception('هذا المرفق ليس تسجيلًا صوتيًا.');
    }
    final audioBytes = audioResponse.bodyBytes;
    if (!isBarqTranscriptionSizeAllowed(audioBytes.length)) {
      throw Exception('تحويل الصوت إلى نص متاح للتسجيلات حتى 2 ميغابايت.');
    }
    // Keep transcription on the public API origin; avoid direct workers.dev
    // fallback so restricted networks use one hostname consistently.
    const primaryTranscribeBase = apiBase;
    const String? fallbackTranscribeBase = null;
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$primaryTranscribeBase/api/transcribe'),
        headers: {...requestHeaders, 'Content-Type': contentType},
        body: audioBytes,
      ).timeout(const Duration(minutes: 3));
      if (response.statusCode >= 500 && fallbackTranscribeBase != null) {
        response = await http.post(
          Uri.parse('$fallbackTranscribeBase/api/transcribe'),
          headers: {...requestHeaders, 'Content-Type': contentType},
          body: audioBytes,
        ).timeout(const Duration(minutes: 3));
      }
    } catch (_) {
      if (fallbackTranscribeBase == null) rethrow;
      response = await http.post(
        Uri.parse('$fallbackTranscribeBase/api/transcribe'),
        headers: {...requestHeaders, 'Content-Type': contentType},
        body: audioBytes,
      ).timeout(const Duration(minutes: 3));
    }
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((data['error'] ?? 'تعذر تحويل التسجيل إلى نص (${response.statusCode}).').toString());
    }
    final transcript = data['text']?.toString().trim() ?? '';
    if (transcript.isEmpty) throw Exception('لم يتم العثور على كلام واضح في التسجيل.');
    return transcript;
  }

  static Future<Uint8List> fetchAttachmentBytes(String attachmentId) async {
    final headers = {if (token != null) 'Authorization': 'Bearer $token'};
    final response = await _getMediaResponse(
      attachmentId,
      headers: headers,
      timeout: const Duration(minutes: 2),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر معاينة الملف (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  static Future<void> downloadAttachment({
    required String attachmentId,
    required String fileName,
  }) async {
    final requestHeaders = {if (token != null) 'Authorization': 'Bearer $token'};
    final response = await _getMediaResponse(
      attachmentId,
      headers: requestHeaders,
      timeout: const Duration(minutes: 3),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر تنزيل الملف (${response.statusCode}).');
    }
    final saved = await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: response.bodyBytes,
    );
    if (saved == null) throw Exception('تم إلغاء حفظ الملف.');
  }

  static Future<void> logout() async {
    // Revoke this installation's push token before clearing the auth session.
    // A network failure must never trap the user in the account.
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (token != null && fcmToken != null && fcmToken.isNotEmpty) {
        await request('DELETE', '/api/devices/token', body: {'fcmToken': fcmToken});
      }
    } catch (_) {}
    if (token != null) {
      try { await request('POST', '/api/logout'); } catch (_) {}
    }
    await SirajRealtime.instance.stop();
    await BarqNearbyService.instance.stop();
    token = null;
    await storage.delete(key: 'siraj_token');
    await storage.delete(key: 'barq_cached_user');
    await storage.delete(key: 'barq_cached_friends');
    await storage.delete(key: 'barq_offline_outbox_v1');
    await storage.delete(key: 'barq_offline_inbox_v1');
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static Future<void> _cacheUser(Map<String, dynamic> user) async {
    if (user.isEmpty) return;
    try { await storage.write(key: 'barq_cached_user', value: jsonEncode(user)); } catch (_) {}
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

String newBarqMessageId() {
  final random = math.Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// طابور محلي مشفر بواسطة flutter_secure_storage؛ لا يضم الرسائل المؤقتة.
bool barqOfflineSyncShouldPause(Object error) =>
    error.toString().contains('NETWORK_DIAGNOSTIC');

bool barqOfflineQueueIsFull(int length, {int limit = 200}) => length >= limit;

List<Map<String, dynamic>> decodeBarqOfflineQueue(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw const FormatException('بيانات صندوق الرسائل المحلي ليست قائمة صالحة.');
  }
  final items = <Map<String, dynamic>>[];
  for (final entry in decoded) {
    if (entry is! Map || entry.keys.any((key) => key is! String)) {
      throw const FormatException('توجد رسالة تالفة في صندوق الرسائل المحلي؛ أُوقف التحميل لحماية بقية الرسائل.');
    }
    items.add(Map<String, dynamic>.from(entry));
  }
  return items;
}

bool barqOfflineIncomingMessageMatches(
  Map<String, dynamic> existing,
  Map<String, dynamic> incoming,
) {
  return field(existing, ['id', 'message_id']) == field(incoming, ['id', 'message_id']) &&
      field(existing, ['sender_id', 'senderId']) == field(incoming, ['sender_id', 'senderId']) &&
      field(existing, ['receiver_id', 'receiverId']) == field(incoming, ['receiver_id', 'receiverId']) &&
      field(existing, ['body', 'content', 'message']) == field(incoming, ['body', 'content', 'message']) &&
      field(existing, ['reply_to_id', 'replyToId']) == field(incoming, ['reply_to_id', 'replyToId']);
}

List<Map<String, dynamic>> barqOfflineItemsNotOnServerPage(
  List<Map<String, dynamic>> queuedItems,
  List<Map<String, dynamic>> serverMessages,
) {
  if (serverMessages.isEmpty) return queuedItems;
  return queuedItems.where((queued) {
    final id = field(queued, ['id', 'message_id']);
    if (id.isEmpty) return true;
    final matchingServerMessage = serverMessages.where(
      (server) => field(server, ['id', 'message_id']) == id,
    );
    // لا نحذف نسخة الطابور لمجرد تطابق المعرّف؛ نتحقق أيضاً من
    // المرسل والمستلم والمحتوى حتى لا نفقد رسالة عند تعارض/انتحال ID.
    return !matchingServerMessage.any(
      (server) => barqOfflineIncomingMessageMatches(queued, server),
    );
  }).toList();
}

List<Map<String, dynamic>> barqOfflineQueueWithoutExactMessage(
  List<Map<String, dynamic>> queuedItems,
  Map<String, dynamic> acceptedMessage,
) => queuedItems
    .where((item) => !barqOfflineIncomingMessageMatches(item, acceptedMessage))
    .toList();

class BarqOfflineQueue {
  static const String _outboxKey = 'barq_offline_outbox_v1';
  static const String _inboxKey = 'barq_offline_inbox_v1';
  static bool _syncing = false;
  static Future<void> _mutationTail = Future<void>.value();

  static Future<void> _mutate(
    String key,
    FutureOr<List<Map<String, dynamic>>> Function(
      List<Map<String, dynamic>> items,
    ) update,
  ) async {
    final previous = _mutationTail;
    final completed = Completer<void>();
    _mutationTail = completed.future;
    await previous;
    try {
      final current = await _read(key);
      final next = await update(current);
      await _write(key, next);
    } finally {
      completed.complete();
    }
  }

  static Future<List<Map<String, dynamic>>> _read(String key) async {
    final raw = await storage.read(key: key);
    return decodeBarqOfflineQueue(raw);
  }

  static Future<void> _write(String key, List<Map<String, dynamic>> items) async {
    await storage.write(key: key, value: jsonEncode(items));
  }

  static Future<void> enqueueOutgoing(Map<String, dynamic> message) async {
    await _mutate(_outboxKey, (items) {
      final messageId = field(message, ['id', 'message_id']);
      final existingIndex = items.indexWhere(
        (item) => field(item, ['id', 'message_id']) == messageId,
      );
      if (existingIndex >= 0) {
        if (!barqOfflineIncomingMessageMatches(items[existingIndex], message)) {
          throw Exception('تعارض في معرّف رسالة الصادر؛ تم رفض إعادة استخدام المعرّف بمحتوى أو أطراف مختلفة.');
        }
        return items;
      }
      if (barqOfflineQueueIsFull(items.length)) {
        throw Exception('صندوق الرسائل دون إنترنت ممتلئ؛ اتصل بالإنترنت لمزامنة الرسائل أولاً.');
      }
      return [...items, message];
    });
  }

  static Future<void> enqueueIncoming(Map<String, dynamic> message) async {
    await _mutate(_inboxKey, (items) {
      final existingIndex = items.indexWhere(
        (item) => field(item, ['id', 'message_id']) == field(message, ['id', 'message_id']),
      );
      if (existingIndex >= 0) {
        if (!barqOfflineIncomingMessageMatches(items[existingIndex], message)) {
          throw Exception('تعارض في معرّف رسالة Nearby؛ تم رفض الرسالة المكررة غير المطابقة.');
        }
        return items;
      }
      if (barqOfflineQueueIsFull(items.length)) {
        throw Exception('صندوق الرسائل الواردة دون إنترنت ممتلئ؛ افتح الإنترنت لمزامنة الرسائل أولاً.');
      }
      return [...items, message];
    });
  }

  static Future<List<Map<String, dynamic>>> conversation(String friendId, String currentUserId) async {
    final outbox = await _read(_outboxKey);
    final inbox = await _read(_inboxKey);
    return [...outbox, ...inbox].where((item) {
      final sender = field(item, ['sender_id']);
      final receiver = field(item, ['receiver_id']);
      return (sender == currentUserId && receiver == friendId) ||
          (sender == friendId && receiver == currentUserId);
    }).map((item) => {...item, 'is_offline_pending': true}).toList();
  }

  static Future<void> reconcile(List<Map<String, dynamic>> serverMessages) async {
    if (serverMessages.isEmpty) return;
    await _mutate(_outboxKey, (items) =>
        barqOfflineItemsNotOnServerPage(items, serverMessages));
    await _mutate(_inboxKey, (items) =>
        barqOfflineItemsNotOnServerPage(items, serverMessages));
  }

  static Future<void> syncOutbox() async {
    if (_syncing || Api.token == null) return;
    _syncing = true;
    try {
      final items = await _read(_outboxKey);
      for (final item in items) {
        try {
          await Api.sendMessage(
            field(item, ['receiver_id']),
            field(item, ['body']),
            clientMessageId: field(item, ['id']),
            replyToId: field(item, ['reply_to_id']).isEmpty ? null : field(item, ['reply_to_id']),
          );
          await _mutate(_outboxKey, (remaining) =>
              barqOfflineQueueWithoutExactMessage(remaining, item));
        } catch (error) {
          // توقف عند انقطاع الشبكة؛ أما الرفض الخاص برسالة واحدة فلا ينبغي
          // أن يمنع إرسال بقية الرسائل المعلقة في الطابور.
          if (barqOfflineSyncShouldPause(error)) break;
          continue;
        }
      }
    } finally {
      _syncing = false;
    }
  }
}

/// نقل رسائل نصية فقط عبر Google Nearby Connections بين جهات الاتصال المعروفة.
class BarqNearbyService {
  BarqNearbyService._();
  static final BarqNearbyService instance = BarqNearbyService._();
  static const String _serviceId = 'com.barq.app';
  final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();
  final Map<String, ConnectionInfo> _pending = {};
  final Map<String, String> _connectedUsers = {};
  final Map<String, String> _discoveredUsers = {};
  Set<String> _knownContacts = {};
  String? _currentUserId;
  String _endpointName = 'BARQ';
  bool _running = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isRunning => _running;
  List<MapEntry<String, String>> get discovered => _discoveredUsers.entries.toList();
  List<MapEntry<String, String>> get connected => _connectedUsers.entries.toList();

  String? _userIdFromEndpoint(String name) {
    final parts = name.split('|');
    if (parts.length < 2 || parts.first != 'BARQ') return null;
    return parts[1].trim().isEmpty ? null : parts[1].trim();
  }

  Future<void> start({required String userId, required String displayName, required List<Map<String, dynamic>> friends}) async {
    if (_running) return;
    _currentUserId = userId;
    _knownContacts = friends.map((item) => field(item, ['id', 'user_id'])).where((id) => id.isNotEmpty).toSet();
    final safeName = displayName.replaceAll('|', '');
    _endpointName = 'BARQ|$userId|${safeName.substring(0, math.min(safeName.length, 12).toInt())}';
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final permissionByName = <String, Permission>{
      'location': Permission.location,
      'bluetooth': Permission.bluetooth,
      'bluetoothAdvertise': Permission.bluetoothAdvertise,
      'bluetoothConnect': Permission.bluetoothConnect,
      'bluetoothScan': Permission.bluetoothScan,
      'nearbyWifiDevices': Permission.nearbyWifiDevices,
    };
    final requestedPermissions = barqNearbyPermissionNamesForAndroidSdk(
      androidInfo.version.sdkInt,
    ).map((name) => permissionByName[name]!).toList();
    final permissionResults = await requestedPermissions.request();
    final deniedPermissions = permissionResults.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();
    if (deniedPermissions.isNotEmpty) {
      throw Exception(
        'تعذر تشغيل الاتصال القريب؛ اسمح بأذونات Bluetooth والأجهزة القريبة، وبإذن الموقع على إصدارات Android حتى 12L، ثم أعد المحاولة.',
      );
    }
    final locationServiceStatus = await Permission.location.serviceStatus;
    if (!locationServiceStatus.isEnabled) {
      throw Exception('شغّل خدمة الموقع في إعدادات الهاتف؛ مكتبة Nearby قد تحتاج تفعيلها لاكتشاف الأجهزة، ولا يتم جمع موقعك.');
    }

    var advertisingStarted = false;
    try {
      advertisingStarted = await Nearby().startAdvertising(
        _endpointName,
        Strategy.P2P_POINT_TO_POINT,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      if (!advertisingStarted) throw Exception('تعذر بدء الإعلان عن جهاز برق القريب.');
      final discoveryStarted = await Nearby().startDiscovery(
        _endpointName,
        Strategy.P2P_POINT_TO_POINT,
        serviceId: _serviceId,
        onEndpointFound: (id, name, serviceId) {
          final peerId = _userIdFromEndpoint(name);
          if (peerId == null || !_knownContacts.contains(peerId)) return;
          _discoveredUsers[id] = peerId;
          _events.add({'type': 'endpoint_found', 'endpointId': id, 'userId': peerId, 'name': name});
        },
        onEndpointLost: (id) {
          _discoveredUsers.remove(id);
          _events.add({'type': 'endpoint_lost', 'endpointId': id});
        },
      );
      if (!discoveryStarted) throw Exception('تعذر بدء البحث عن الأجهزة القريبة.');
      _running = true;
      _events.add({'type': 'started'});
    } catch (_) {
      try { await Nearby().stopAllEndpoints(); } catch (_) {}
      try { await Nearby().stopDiscovery(); } catch (_) {}
      if (advertisingStarted) {
        try { await Nearby().stopAdvertising(); } catch (_) {}
      }
      _pending.clear();
      _connectedUsers.clear();
      _discoveredUsers.clear();
      _running = false;
      rethrow;
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    final peerId = _userIdFromEndpoint(info.endpointName);
    if (peerId == null || !_knownContacts.contains(peerId)) {
      unawaited(Nearby().rejectConnection(id).then<bool>((_) => true, onError: (Object _) => false));
      return;
    }
    _pending[id] = info;
    _discoveredUsers[id] = peerId;
    _events.add({
      'type': 'connection_request',
      'endpointId': id,
      'userId': peerId,
      'name': info.endpointName,
      'authenticationToken': info.authenticationToken,
      'isIncoming': info.isIncomingConnection,
    });
  }

  void _onConnectionResult(String id, Status status) {
    final peerId = _discoveredUsers[id] ?? _userIdFromEndpoint(_pending[id]?.endpointName ?? '');
    if (status == Status.CONNECTED && peerId != null && _knownContacts.contains(peerId)) {
      _connectedUsers[id] = peerId;
    } else {
      _connectedUsers.remove(id);
      _pending.remove(id);
      if (status == Status.CONNECTED) {
        unawaited(Nearby().rejectConnection(id).then<bool>((_) => true, onError: (Object _) => false));
      }
    }
    _events.add({'type': 'connection_result', 'endpointId': id, 'userId': peerId ?? '', 'success': status == Status.CONNECTED && _connectedUsers.containsKey(id), 'status': status.toString()});
  }

  void _onDisconnected(String id) {
    _connectedUsers.remove(id);
    _pending.remove(id);
    _discoveredUsers.remove(id);
    _events.add({'type': 'disconnected', 'endpointId': id});
  }

  Future<void> requestConnection(String endpointId) async {
    final peerId = _discoveredUsers[endpointId];
    if (!_running || peerId == null || !_knownContacts.contains(peerId)) {
      throw Exception('الجهاز القريب لم يعد متاحاً أو ليس ضمن جهات اتصال برق.');
    }
    await Nearby().requestConnection(
      _endpointName,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  Future<void> acceptConnection(String endpointId) async {
    if (!_running) throw Exception('شغّل الاتصال القريب أولاً.');
    final info = _pending[endpointId];
    final peerId = _discoveredUsers[endpointId] ?? _userIdFromEndpoint(info?.endpointName ?? '');
    if (info == null || peerId == null || !_knownContacts.contains(peerId)) {
      throw Exception('الجهاز ليس ضمن جهات اتصال برق المعروفة.');
    }
    await Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) async {
        if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
        try {
          final decoded = jsonDecode(utf8.decode(payload.bytes!));
          if (decoded is! Map<String, dynamic> ||
              !isValidBarqNearbyTextPayload(
                decoded,
                peerId: peerId,
                currentUserId: _currentUserId ?? '',
              )) {
            return;
          }
          final body = decoded['body'].toString();
          final messageId = decoded['id'].toString();
          await BarqOfflineQueue.enqueueIncoming({
            'id': messageId,
            'sender_id': peerId,
            'receiver_id': _currentUserId,
            'body': body,
            'created_at': decoded['createdAt']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
          });
          _events.add({'type': 'message_received', 'senderId': peerId, 'id': messageId});
        } catch (error) {
          _events.add({
            'type': 'message_receive_failed',
            'senderId': peerId,
            'reason': error.toString(),
          });
        }
      },
      onPayloadTransferUpdate: (id, update) {
        if (barqNearbyPayloadTransferFailed(update.status)) {
          _events.add({
            'type': 'payload_transfer_failed',
            'senderId': peerId,
            'payloadId': update.id,
            'status': update.status.name,
          });
        }
      },
    );
    _events.add({'type': 'connection_accepted', 'endpointId': endpointId, 'userId': peerId});
  }

  Future<void> rejectConnection(String endpointId) async {
    _pending.remove(endpointId);
    await Nearby().rejectConnection(endpointId);
  }

  Future<bool> sendTextMessage({required String receiverId, required String messageId, required String body, required String senderId}) async {
    if (!_running || !isValidBarqNearbyOutgoingText(
      senderId: senderId,
      currentUserId: _currentUserId ?? '',
      receiverId: receiverId,
      knownContacts: _knownContacts,
      messageId: messageId,
      body: body,
    )) {
      throw Exception('بيانات رسالة Nearby غير صالحة أو أن الاتصال القريب متوقف.');
    }
    final targets = _connectedUsers.entries.where((entry) => entry.value == receiverId).toList();
    if (targets.isEmpty) return false;
    final payload = Uint8List.fromList(utf8.encode(jsonEncode({
      'kind': 'barq_text_message',
      'id': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'body': body,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    })));
    for (final target in targets) {
      await Nearby().sendBytesPayload(target.key, payload);
    }
    return true;
  }

  Future<void> stop() async {
    try { await Nearby().stopAllEndpoints(); } catch (_) {}
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}
    _pending.clear();
    _connectedUsers.clear();
    _discoveredUsers.clear();
    _knownContacts.clear();
    _currentUserId = null;
    _running = false;
    _events.add({'type': 'stopped'});
  }
}

const List<String> barqReactionEmojis = ["👍", "❤️", "😂", "😮", "😢", "😡", "🎉", "🔥"];

Future<String?> showMessageReactionPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final emoji in barqReactionEmojis)
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.pop(sheetContext, emoji),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(emoji, style: const TextStyle(fontSize: 30)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

List<Map<String, dynamic>> normalizeMessageReactions(dynamic raw) {
  if (raw is! List) return [];
  return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

Widget messageReactionBar({
  required BuildContext context,
  required Map<String, dynamic> message,
  required String currentUserId,
  required Future<void> Function(String emoji, bool remove) onReaction,
  Future<void> Function()? onPin,
  Future<void> Function()? onSaveMemory,
  bool isPinned = false,
}) {
  final reactions = normalizeMessageReactions(message['reactions']);
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final reaction in reactions) {
    final emoji = field(reaction, ['emoji']);
    if (barqReactionEmojis.contains(emoji)) {
      grouped.putIfAbsent(emoji, () => []).add(reaction);
    }
  }
  return Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [
        for (final entry in grouped.entries)
          Tooltip(
            message: entry.value.map((item) => field(item, ['display_name', 'user_id'], 'مستخدم')).join('، '),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              backgroundColor: entry.value.any((item) => field(item, ['user_id']) == currentUserId)
                  ? const Color(0x554A8DFF) : Colors.black26,
              label: Text('${entry.key} ${entry.value.length}', style: const TextStyle(fontSize: 11)),
              onPressed: () => onReaction(
                entry.key,
                entry.value.any((item) => field(item, ['user_id']) == currentUserId),
              ),
            ),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          tooltip: 'إضافة تفاعل',
          icon: const Icon(Icons.add_reaction_outlined, size: 18, color: Colors.white60),
          onPressed: () async {
            final emoji = await showMessageReactionPicker(context);
            if (emoji != null) await onReaction(emoji, false);
          },
        ),
        if (onPin != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: isPinned ? 'إلغاء تثبيت الرسالة' : 'تثبيت الرسالة',
            icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 17, color: isPinned ? Theme.of(context).colorScheme.primary : Colors.white60),
            onPressed: onPin,
          ),
      ],
    ),
  );
}

Future<void> showMessageActions(
  BuildContext context, {
  required Map<String, dynamic> message,
  required bool canDelete,
  required Future<void> Function() onDelete,
  Future<void> Function(Map<String, dynamic> message)? onReply,
  Future<void> Function(String body)? onEdit,
  Future<void> Function(String emoji)? onReact,
  Future<void> Function()? onPin,
  Future<void> Function()? onSaveMemory,
  bool isPinned = false,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('نسخ الرسالة'),
            onTap: () => Navigator.pop(sheetContext, 'copy'),
          ),
          if (onReact != null)
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('إضافة تفاعل'),
              onTap: () => Navigator.pop(sheetContext, 'react'),
            ),
          if (onPin != null)
            ListTile(
              leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(isPinned ? 'إلغاء تثبيت الرسالة' : 'تثبيت الرسالة'),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
          if (onSaveMemory != null)
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('حفظ في الذكريات الخاصة'),
              onTap: () => Navigator.pop(sheetContext, 'save_memory'),
            ),
          if (onReply != null)
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('الرد على الرسالة'),
              onTap: () => Navigator.pop(sheetContext, 'reply'),
            ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('تعديل الرسالة'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
          if (canDelete)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('حذف الرسالة'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (action == 'react' && onReact != null && context.mounted) {
    final emoji = await showMessageReactionPicker(context);
    if (emoji != null) await onReact(emoji);
  } else if (action == 'pin' && onPin != null) {
    await onPin();
  } else if (action == 'save_memory' && onSaveMemory != null) {
    await onSaveMemory();
  } else if (action == 'reply' && onReply != null) {
    await onReply(message);
  } else if (action == 'edit' && onEdit != null && context.mounted) {
    final initial = field(message, ['body', 'content', 'message']);
    final edited = await showEditMessageDialog(context, initial);
    if (edited != null && edited.trim() != initial.trim()) {
      try {
        await onEdit(edited.trim());
        if (context.mounted) showMsg(context, 'تم تعديل الرسالة');
      } catch (error) {
        if (context.mounted) showMsg(context, cleanError(error));
      }
    }
  } else if (action == 'copy') {
    final text = field(message, ['body', 'content', 'message']);
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showMsg(context, 'تم نسخ الرسالة');
    }
  } else if (action == 'delete' && canDelete && context.mounted) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('حذف الرسالة؟'),
        content: const Text('سيتم حذف الرسالة من المحادثة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await onDelete();
        if (context.mounted) showMsg(context, 'تم حذف الرسالة');
      } catch (error) {
        if (context.mounted) showMsg(context, cleanError(error));
      }
    }
  }
}

Future<String?> showEditMessageDialog(BuildContext context, String initialText) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditMessageDialog(initialText: initialText),
  );
}

class _EditMessageDialog extends StatefulWidget {
  final String initialText;
  const _EditMessageDialog({required this.initialText});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('تعديل الرسالة'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 5,
        minLines: 1,
        maxLength: 5000,
        decoration: const InputDecoration(hintText: 'اكتب نص الرسالة'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        TextButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty && value.length <= 5000) {
              Navigator.pop(context, value);
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

String messageReplyPreview(Map<String, dynamic> message) {
  final raw = message['reply_to_body'];
  if (raw == null) return 'رسالة';
  if (raw is Map) return 'مرفق';
  final value = raw.toString().trim();
  if (value.isEmpty) return 'رسالة';
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map &&
        (decoded['type'] == 'attachment' ||
         decoded.containsKey('attachmentId') ||
         decoded.containsKey('attachment_id') ||
         decoded.containsKey('fileName') ||
         decoded.containsKey('file_name'))) {
      return 'مرفق';
    }
  } catch (_) {}
  return value.length > 120 ? '${value.substring(0, 120)}…' : value;
}

List<Map<String, dynamic>> searchConversationMessages(
  Iterable<Map<String, dynamic>> items,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return items.where((message) {
    final body = field(message, ['body', 'content', 'message']).toLowerCase();
    final sender = field(message, ['display_name', 'displayName', 'username']).toLowerCase();
    return body.contains(needle) || sender.contains(needle);
  }).toList();
}

Future<void> showConversationSearch(
  BuildContext context,
  Future<Map<String, dynamic>> Function(String query, Map<String, dynamic>? before) search,
) async {
  final controller = TextEditingController();
  List<Map<String, dynamic>> matches = [];
  Map<String, dynamic>? nextCursor;
  bool searching = false;
  bool searched = false;
  bool hasMore = false;
  String? searchError;
  Future<void> runSearch(StateSetter refresh, {bool older = false}) async {
    final query = controller.text.trim();
    if (query.length < 2 || searching || (older && !hasMore)) return;
    refresh(() { searching = true; searchError = null; });
    try {
      final result = await search(query, older ? nextCursor : null);
      final found = Api._list(result['messages']);
      refresh(() {
        matches = older ? mergeMessages(matches, found) : found;
        nextCursor = result['nextCursor'] is Map
            ? Map<String, dynamic>.from(result['nextCursor']) : null;
        hasMore = result['hasMore'] == true;
        searched = true;
      });
    } catch (error) {
      refresh(() { searchError = cleanError(error); searched = true; });
    } finally {
      refresh(() { searching = false; });
    }
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('البحث في المحادثة'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: Column(
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => runSearch(refresh),
                decoration: inputDecoration('ابحث في جميع رسائل المحادثة', Icons.search).copyWith(
                  suffixIcon: IconButton(
                    onPressed: searching ? null : () => runSearch(refresh),
                    icon: searching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: searching && matches.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: gold))
                    : searchError != null
                        ? Center(child: Text(searchError!, textAlign: TextAlign.center))
                        : !searched
                            ? const Center(child: Text('اكتب كلمتين على الأقل ثم اضغط بحث'))
                            : matches.isEmpty
                                ? const Center(child: Text('لا توجد نتائج مطابقة'))
                                : ListView.separated(
                                    itemCount: matches.length + (hasMore ? 1 : 0),
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      if (index == matches.length) {
                                        return Center(child: TextButton.icon(
                                          onPressed: searching ? null : () => runSearch(refresh, older: true),
                                          icon: searching
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.history),
                                          label: const Text('نتائج أقدم'),
                                        ));
                                      }
                                      final message = matches[index];
                                      return ListTile(
                                        dense: true,
                                        title: Text(field(message, ['body', 'content', 'message']),
                                            maxLines: 3, overflow: TextOverflow.ellipsis),
                                        subtitle: Text('${field(message, ['display_name', 'username'])} · ${_messageTime(field(message, ['created_at', 'createdAt']))}'),
                                      );
                                    },
                                  ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
      ),
    ),
  );
  controller.dispose();
}

List<Map<String, dynamic>> mergeMessages(
  Iterable<Map<String, dynamic>> first,
  Iterable<Map<String, dynamic>> second,
) {
  final unique = <String, Map<String, dynamic>>{};
  for (final message in [...first, ...second]) {
    final id = field(message, ['id']);
    final fallbackKey = '${field(message, ['created_at', 'createdAt'])}|' 
        '${field(message, ['sender_id', 'senderId'])}|' 
        '${field(message, ['body', 'content'])}';
    unique[id.isNotEmpty ? id : fallbackKey] = message;
  }
  final result = unique.values.toList();
  result.sort((a, b) {
    final aTime = _messageSortTime(field(a, ['created_at', 'createdAt']));
    final bTime = _messageSortTime(field(b, ['created_at', 'createdAt']));
    final byTime = aTime.compareTo(bTime);
    return byTime != 0 ? byTime : field(a, ['id']).compareTo(field(b, ['id']));
  });
  return result;
}

int? _ephemeralDeleteAt(Map<String, dynamic> message) {
  if (message['is_ephemeral'] != true) return null;
  final value = message['delete_at'];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<Map<String, dynamic>> filterExpiredEphemeralMessages(
  Iterable<Map<String, dynamic>> items, {
  DateTime? now,
}) {
  final nowSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  return items.where((message) {
    final deleteAt = _ephemeralDeleteAt(message);
    return deleteAt == null || deleteAt > nowSeconds;
  }).toList();
}

DateTime _messageSortTime(String raw) {
  if (raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final normalized = raw.contains(' ') && !raw.contains('T') ? '${raw.replaceFirst(' ', 'T')}Z' : raw;
  return DateTime.tryParse(normalized)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

String field(Map<String, dynamic> data, List<String> keys, [String fallback = '']) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().isNotEmpty) return value.toString();
  }
  return fallback;
}

/// بعض استجابات المجموعات تعيد photo_updated_at دون photoUrl؛ نبني المسار
/// من معرّف صاحب الصورة فقط عند وجود توقيت تحديث صالح.
String profilePhotoPath(Map<String, dynamic> user) {
  final existing = field(user, ['photoUrl', 'photo_url']);
  if (existing.isNotEmpty) return existing;
  final id = field(user, ['id', 'user_id', 'friend_id', 'sender_id']);
  final updatedAt = field(user, ['photoUpdatedAt', 'photo_updated_at']);
  if (id.isEmpty || updatedAt.isEmpty) return '';
  return '/api/profile/photo/${Uri.encodeComponent(id)}';
}

Widget personAvatar(Map<String, dynamic> person, {double radius = 22}) {
  final user = person['user'] is Map
      ? Map<String, dynamic>.from(person['user'])
      : person;
  final name = field(user, ['displayName', 'display_name', 'name', 'username'], '؟');
  final photoUrl = profilePhotoPath(user);
  final photoUpdatedAt = field(user, ['photoUpdatedAt', 'photo_updated_at']);
  final imageUrl = photoUrl.isEmpty
      ? ''
      : '$apiBase$photoUrl?v=${Uri.encodeComponent(photoUpdatedAt)}';
  return CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFF46391F),
    child: imageUrl.isEmpty
        ? Text(name.characters.first, style: TextStyle(color: gold, fontSize: radius * 0.85))
        : ClipOval(
            child: Image.network(
              imageUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              headers: {'Authorization': 'Bearer ${Api.token}'},
              errorBuilder: (_, __, ___) => Center(
                child: Text(name.characters.first,
                    style: TextStyle(color: gold, fontSize: radius * 0.85)),
              ),
            ),
          ),
  );
}

class PrivateMemoryPhotoGallery extends StatefulWidget {
  final List<Map<String, dynamic>> media;
  final ValueChanged<int>? onPageChanged;

  const PrivateMemoryPhotoGallery({
    super.key,
    required this.media,
    this.onPageChanged,
  });

  @override
  State<PrivateMemoryPhotoGallery> createState() => _PrivateMemoryPhotoGalleryState();
}

class _PrivateMemoryPhotoGalleryState extends State<PrivateMemoryPhotoGallery> {
  int currentPage = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) {
      return const Center(child: Icon(Icons.photo_library_outlined, size: 42));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView(
          onPageChanged: (page) {
            setState(() => currentPage = page);
            widget.onPageChanged?.call(page);
          },
          children: [
            for (final item in widget.media)
              InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  Api.sparkMediaUri(field(item, ['attachmentId'])).toString(),
                  headers: {if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'},
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
          ],
        ),
        if (widget.media.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(
                    '${currentPage + 1} / ${widget.media.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PrivateMemoryLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const PrivateMemoryLoadError({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 12),
        const Text('تعذر تحميل ذكرياتك', style: TextStyle(color: gold, fontSize: 18)),
        const SizedBox(height: 8),
        const Text(
          'تحقق من اتصالك وحاول التحديث. لم نحذف ذكرياتك المحفوظة.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    ),
  );
}

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  bool checking = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final saved = await storage.read(key: 'siraj_token');
    if (saved != null && saved.isNotEmpty) {
      Api.token = saved;
      try {
        final user = await Api.me();
        await SirajPush.register();
        // اتصال REST عبر Vercel هو المسار المعتمد لتجنب workers.dev على الشبكات المقيدة.
      // المزامنة الدورية أدناه تُبقي الرسائل محدثة دون اتصال WebSocket مباشر.
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(user: user)));
        return;
      } catch (e) {
        if (e.toString().contains('NETWORK_DIAGNOSTIC')) {
          try {
            final rawUser = await storage.read(key: 'barq_cached_user');
            final decoded = rawUser == null ? null : jsonDecode(rawUser);
            if (decoded is Map) {
              final cachedUser = Map<String, dynamic>.from(decoded);
              if (cachedUser.isNotEmpty && mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(user: cachedUser)));
                return;
              }
            }
          } catch (_) {}
          // لا نحذف الرمز أو الجلسة لمجرد انقطاع الشبكة.
          if (mounted) setState(() => checking = false);
          return;
        }
        await Api.logout();
      }
    }
    if (mounted) setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: gold)),
      );
    }
    return const LoginPage();
  }
}

String normalizeBarqPhoneDigits(String raw) => raw.trim().replaceAllMapped(
  RegExp(r'[٠-٩۰-۹]'),
  (match) {
    final code = match.group(0)!.codeUnitAt(0);
    return String.fromCharCode(code >= 0x06f0 && code <= 0x06f9
        ? code - 0x06f0 + 48 : code - 0x0660 + 48);
  },
);

String normalizeBarqInternationalPhone(String raw) {
  var value = normalizeBarqPhoneDigits(raw).replaceAll(RegExp(r'[\s().-]'), '');
  if (value.startsWith('00')) value = ['+', value.substring(2)].join();
  if (!value.startsWith('+')) value = ['+', value].join();
  return value;
}

String normalizeBarqRegistrationPhone(String raw, String countryCode) {
  final value = normalizeBarqPhoneDigits(raw)
      .trim()
      .replaceAll(RegExp(r'[\s().-]'), '');
  if (value.startsWith('+') || value.startsWith('00')) {
    return normalizeBarqInternationalPhone(value);
  }
  final nationalNumber = value.replaceFirst(RegExp(r'^0+'), '');
  return normalizeBarqInternationalPhone(countryCode + nationalNumber);
}
/// Canonical digit-only form for comparing saved contact numbers.
/// Converts Arabic-Indic digits before stripping punctuation.
String normalizeBarqContactPhoneDigits(String raw) =>
    normalizeBarqPhoneDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');

const List<(String, String)> barqCountryCodes = [

    ('اليمن', '+967'), ('السعودية', '+966'), ('الإمارات', '+971'),
    ('إسرائيل', '+972'),
    ('عُمان', '+968'), ('الكويت', '+965'), ('قطر', '+974'),
    ('البحرين', '+973'), ('مصر', '+20'), ('الأردن', '+962'),
    ('العراق', '+964'), ('فلسطين', '+970'), ('لبنان', '+961'),
    ('سوريا', '+963'), ('تركيا', '+90'), ('الهند', '+91'),
    ('باكستان', '+92'), ('بنغلاديش', '+880'), ('إندونيسيا', '+62'),
    ('ماليزيا', '+60'), ('المملكة المتحدة وجيرزي وغيرنزي وجزيرة مان', '+44'), ('ألمانيا', '+49'),
    ('فرنسا', '+33'), ('إيطاليا ومدينة الفاتيكان', '+39'),
    ('جبل طارق', '+350'), ('إسبانيا', '+34'),
    ('الولايات المتحدة وكندا وبورتوريكو وجزر العذراء الأمريكية وساموا الأمريكية ومناطق أمريكا الشمالية', '+1'), ('أستراليا وجزر كوكوس وجزيرة الكريسماس', '+61'),
    ('جنوب أفريقيا', '+27'), ('نيجيريا', '+234'), ('المغرب والصحراء الغربية', '+212'),
    ('ألبانيا', '+355'), ('أندورا', '+376'), ('أرمينيا', '+374'),
    ('النمسا', '+43'), ('أذربيجان', '+994'),
    ('جورجيا', '+995'), ('بيلاروس', '+375'),
    ('بلجيكا', '+32'), ('البوسنة والهرسك', '+387'),
    ('مقدونيا الشمالية', '+389'), ('بلغاريا', '+359'),
    ('كرواتيا', '+385'), ('قبرص', '+357'), ('التشيك', '+420'),
    ('الدنمارك', '+45'), ('إستونيا', '+372'), ('فنلندا وجزر آلاند', '+358'),
    ('اليونان', '+30'), ('المجر', '+36'), ('آيسلندا', '+354'),
    ('أيرلندا', '+353'), ('لاتفيا', '+371'), ('ليتوانيا', '+370'),
    ('لوكسمبورغ', '+352'), ('مالطا', '+356'), ('مولدوفا', '+373'),
    ('موناكو', '+377'),
    ('سان مارينو', '+378'), ('الجبل الأسود', '+382'),
    ('كوسوفو', '+383'), ('هولندا', '+31'),
    ('النرويج وسفالبارد ويان ماين', '+47'), ('بولندا', '+48'), ('البرتغال', '+351'),
    ('رومانيا', '+40'), ('صربيا', '+381'), ('سلوفاكيا', '+421'),
    ('ليختنشتاين', '+423'),
    ('سلوفينيا', '+386'), ('السويد', '+46'), ('سويسرا', '+41'),
    ('أوكرانيا', '+380'), ('روسيا وكازاخستان', '+7'),
    ('اليابان', '+81'), ('كوريا الجنوبية', '+82'), ('الصين', '+86'),
    ('كوريا الشمالية', '+850'),
    ('هونغ كونغ', '+852'), ('ماكاو', '+853'), ('تايوان', '+886'),
    ('سنغافورة', '+65'), ('تايلاند', '+66'), ('فيتنام', '+84'),
    ('الفلبين', '+63'), ('ميانمار', '+95'), ('كمبوديا', '+855'),
    ('لاوس', '+856'), ('المالديف', '+960'), ('سريلانكا', '+94'),
    ('نيبال', '+977'), ('أفغانستان', '+93'), ('إيران', '+98'),
    ('أوزبكستان', '+998'), ('قيرغيزستان', '+996'), ('طاجيكستان', '+992'),
    ('تركمانستان', '+993'), ('منغوليا', '+976'), ('بوتان', '+975'),
    ('بروناي', '+673'), ('تيمور الشرقية', '+670'),
    ('جزيرة نورفولك', '+672'),
    ('كينيا', '+254'), ('تنزانيا', '+255'), ('أوغندا', '+256'),
    ('موزمبيق', '+258'), ('زامبيا', '+260'), ('زيمبابوي', '+263'),
    ('ناميبيا', '+264'), ('ملاوي', '+265'), ('بوتسوانا', '+267'),
    ('ليبيا', '+218'), ('غانا', '+233'), ('السنغال', '+221'),
    ('موريتانيا', '+222'), ('مالي', '+223'),
    ('ساحل العاج', '+225'), ('الكاميرون', '+237'), ('أنغولا', '+244'),
    ('رواندا', '+250'), ('مدغشقر', '+261'), ('موريشيوس', '+230'),
    ('المكسيك', '+52'), ('البرازيل', '+55'), ('الأرجنتين', '+54'),
    ('تشيلي', '+56'), ('كولومبيا', '+57'), ('فنزويلا', '+58'),
    ('بيرو', '+51'), ('الإكوادور', '+593'),
    ('غويانا الفرنسية', '+594'), ('بوليفيا', '+591'),
    ('باراغواي', '+595'),
    ('مارتينيك', '+596'), ('أوروغواي', '+598'), ('كوستاريكا', '+506'),
    ('بنما', '+507'), ('غواتيمالا', '+502'), ('السلفادور', '+503'),
    ('هندوراس', '+504'), ('نيكاراغوا', '+505'), ('كوبا', '+53'),
    ('هايتي', '+509'),
    ('غوادلوب وسان بارتيليمي وسان مارتان', '+590'), ('غيانا', '+592'), ('سورينام', '+597'),
    ('نيوزيلندا', '+64'),
    ('الجزائر', '+213'), ('تونس', '+216'), ('السودان', '+249'),
    ('الصومال', '+252'), ('جيبوتي', '+253'), ('إثيوبيا', '+251'),
    ('جنوب السودان', '+211'), ('غامبيا', '+220'), ('غينيا', '+224'),
    ('بوركينا فاسو', '+226'), ('النيجر', '+227'),
    ('توغو', '+228'), ('بنين', '+229'),
    ('ليبيريا', '+231'), ('سيراليون', '+232'), ('تشاد', '+235'),
    ('جمهورية أفريقيا الوسطى', '+236'), ('الرأس الأخضر', '+238'),
    ('ساو تومي وبرينسيب', '+239'), ('غينيا الاستوائية', '+240'),
    ('الغابون', '+241'), ('جمهورية الكونغو', '+242'),
    ('جمهورية الكونغو الديمقراطية', '+243'), ('غينيا بيساو', '+245'),
    ('إقليم المحيط الهندي البريطاني', '+246'), ('جزيرة أسينشين', '+247'),
    ('ليسوتو', '+266'), ('إسواتيني', '+268'),
    ('جزر القمر', '+269'), ('بوروندي', '+257'),
    ('إريتريا', '+291'),
    ('أروبا', '+297'), ('جزر فارو', '+298'), ('غرينلاند', '+299'), ('سيشل', '+248'), ('ريونيون ومايوت', '+262'),
    ('كاليدونيا الجديدة', '+687'), ('بولينيزيا الفرنسية', '+689'),
    ('فيجي', '+679'), ('بابوا غينيا الجديدة', '+675'), ('تونغا', '+676'),
    ('جزر سليمان', '+677'), ('فانواتو', '+678'), ('ساموا', '+685'),
    ('كيريباتي', '+686'), ('توفالو', '+688'), ('ولايات ميكرونيسيا المتحدة', '+691'),
    ('جزر مارشال', '+692'), ('بالاو', '+680'),
    ('واليس وفوتونا', '+681'), ('ناورو', '+674'),
    ('جزر كوك', '+682'), ('نيوي', '+683'), ('توكيلاو', '+690'),
    ('جزر فوكلاند', '+500'),
    ('بليز', '+501'), ('سانت هيلينا وتريستان دا كونا', '+290'),
    ('سان بيير وميكلون', '+508'), ('كوراساو وهولندا الكاريبية', '+599'),
  
];

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController();
  final username = TextEditingController(); // login identifier: phone or username
  final phone = TextEditingController();
  final password = TextEditingController();
  final inviteCode = TextEditingController();
  bool registering = false;
  bool busy = false;
  bool obscurePassword = true;
  String selectedCountryCode = '+967';
  static const List<(String, String)> countryCodes = barqCountryCodes;

  @override
  void initState() {
    super.initState();
    BarqInviteLinks.pendingCode.addListener(_applyPendingInvite);
    _applyPendingInvite();
  }

  void _applyPendingInvite() {
    final code = BarqInviteLinks.pendingCode.value;
    if (code != null && code.isNotEmpty && mounted) {
      inviteCode.text = code;
      if (!registering) setState(() => registering = true);
    }
  }

  @override
  void dispose() {
    BarqInviteLinks.pendingCode.removeListener(_applyPendingInvite);
    name.dispose(); username.dispose();
    phone.dispose(); password.dispose(); inviteCode.dispose();
    super.dispose();
  }

  String _normalizedInternationalPhone(String raw) =>
      normalizeBarqRegistrationPhone(raw, selectedCountryCode);

  Widget _countryCodePicker() => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: busy ? null : () async {
      final searchController = TextEditingController();
      final selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = countryCodes.where((country) =>
              country.$1.toLowerCase().contains(query) || country.$2.contains(query)
            ).toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      const Text('اختر الدولة أو ابحث عنها',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: _barqDecoration('اسم الدولة أو مفتاح الاتصال', Icons.search),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد دولة مطابقة', style: TextStyle(color: Colors.white70)))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final country = filtered[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(country.$1, style: const TextStyle(color: Colors.white)),
                                  trailing: Text(country.$2, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                                  onTap: () => Navigator.pop(sheetContext, country.$2),
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      searchController.dispose();
      if (selected != null && mounted) setState(() => selectedCountryCode = selected);
    },
    child: InputDecorator(
      decoration: _barqDecoration('رمز الدولة', Icons.public),
      child: Row(
        children: [
          Expanded(child: Text(
            countryCodes.firstWhere((country) => country.$2 == selectedCountryCode).$1,
            style: const TextStyle(color: Colors.white),
          )),
          Text(selectedCountryCode, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more, color: Colors.white70),
        ],
      ),
    ),
  );

  Future<void> submit() async {
    if (password.text.isEmpty ||
        (registering && (name.text.trim().isEmpty || phone.text.trim().isEmpty)) ||
        (!registering && username.text.trim().isEmpty)) {
      showMsg(context, registering
          ? 'أدخل الاسم الظاهر ورقم الهاتف وكلمة المرور.'
          : 'أدخل رقم الهاتف أو اسم المستخدم وكلمة المرور.');
      return;
    }
    if (registering && password.text.length < 8) {
      showMsg(context, 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
      return;
    }
    if (registering && !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_normalizedInternationalPhone(phone.text))) {
      showMsg(context, 'أدخل رقم الهاتف مع مفتاح الدولة بصيغة دولية صحيحة.');
      return;
    }
    setState(() => busy = true);
    try {
      final user = registering
          ? await Api.register(
              displayName: name.text.trim(),
              password: password.text,
              phone: _normalizedInternationalPhone(phone.text),
              inviteCode: inviteCode.text.trim().isEmpty ? null : inviteCode.text.trim(),
            )
          : await Api.login(username.text.trim(), password.text);
      if (registering) {
        await BarqInviteLinks.clear();
        final code = Api.lastRecoveryCode;
        if (code != null && code.isNotEmpty && mounted) {
          await showRecoveryCodeDialog(context, code);
        } else if (mounted) {
          showMsg(context, 'تم إنشاء الحساب، لكن لم يصدر الخادم رمز الاسترداد.');
        }
      }
      await SirajPush.register();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(user: user)));
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration _barqDecoration(String label, IconData icon, {String? prefix}) => InputDecoration(
    labelText: label,
    prefixText: prefix,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: glass,
    labelStyle: const TextStyle(color: Colors.white70),
    prefixStyle: const TextStyle(color: gold, fontWeight: FontWeight.bold),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: .09)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: const BorderSide(color: electricBlue, width: 1.5),
    ),
  );

  Widget _input(TextEditingController controller, String label, IconData icon,
      {bool isPhone = false, bool optional = false}) => TextField(
    controller: controller,
    keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
    textDirection: isPhone ? TextDirection.ltr : TextDirection.rtl,
    decoration: _barqDecoration(label, icon,
      prefix: null).copyWith(
        hintText: isPhone ? '+رمز الدولة ورقم الهاتف' : null,
        suffixText: optional ? 'اختياري' : null,
      ),
  );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topRight, end: Alignment.bottomLeft,
                colors: [Color(0xFF101722), Color(0xFF08090D), Color(0xFF050505)],
              )),
            )),
            Positioned(top: -110, right: -70, child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: electricBlue.withValues(alpha: .10),
                boxShadow: [BoxShadow(color: electricBlue.withValues(alpha: .12), blurRadius: 90, spreadRadius: 20)]),
            )),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: Container(
                          width: 86, height: 86,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(27),
                            gradient: const LinearGradient(colors: [Color(0xFFFFE08A), gold, Color(0xFF986B20)]),
                            boxShadow: [BoxShadow(color: gold.withValues(alpha: .24), blurRadius: 28, spreadRadius: 2)],
                          ),
                          child: const Icon(Icons.bolt_rounded, color: Colors.black, size: 54),
                        )),
                        const SizedBox(height: 14),
                        const Center(child: Text('بَرق', style: TextStyle(
                          color: Theme.of(context).colorScheme.primary, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 1,
                        ))),
                        const SizedBox(height: 5),
                        Center(child: Text(
                          registering ? 'أنشئ حسابك برقم هاتفك' : 'تواصل أسرع، أقرب، وأسهل',
                          style: const TextStyle(color: Colors.white70, fontSize: 15),
                        )),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xAA11151D),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withValues(alpha: .10)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .30), blurRadius: 28, offset: const Offset(0, 12))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(registering ? 'إنشاء حساب جديد' : 'مرحبًا بعودتك',
                                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 5),
                              const Text('رقم الهاتف هو معرّفك الأساسي في برق',
                                style: TextStyle(color: Colors.white54, fontSize: 12)),
                              const SizedBox(height: 20),
                              if (registering) ...[
                                _input(name, 'الاسم الظاهر', Icons.person_outline),
                                const SizedBox(height: 13),
                                _countryCodePicker(),
                                const SizedBox(height: 10),
                                _input(phone, 'رقم الهاتف', Icons.phone_android, isPhone: true),
                                const SizedBox(height: 13),
                                _input(inviteCode, 'رمز دعوة صديق', Icons.bolt_outlined, optional: true),
                              ] else ...[
                                _input(username, 'رقم الهاتف أو اسم المستخدم', Icons.person_search),
                              ],
                              const SizedBox(height: 13),
                              TextField(
                                controller: password,
                                obscureText: obscurePassword,
                                decoration: _barqDecoration('كلمة المرور', Icons.lock_outline).copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                                    icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.white54),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 56,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: gold, foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  ),
                                  onPressed: busy ? null : submit,
                                  icon: busy ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                    : Icon(registering ? Icons.person_add_alt_1 : Icons.bolt),
                                  label: Text(registering ? 'إنشاء الحساب' : 'تسجيل الدخول',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              if (!registering) ...[
                                const SizedBox(height: 5),
                                TextButton(
                                  onPressed: busy ? null : () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const PasswordRecoveryPage())),
                                  child: const Text('نسيت كلمة المرور؟'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(child: TextButton(
                          onPressed: busy ? null : () => setState(() => registering = !registering),
                          child: Text(registering ? 'لديك حساب؟ سجّل الدخول' : 'مستخدم جديد؟ أنشئ حسابًا',
                            style: const TextStyle(color: gold, fontSize: 15)),
                        )),
                        const Center(child: Text('لا نحتاج إلى رمز تحقق SMS',
                          style: TextStyle(color: Colors.white38, fontSize: 11))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


Future<void> showRecoveryCodeDialog(BuildContext context, String code) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('احفظ رمز استرداد حسابك'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('هذا الرمز يظهر مرة واحدة فقط. احتفظ به في مكان آمن ولا تشاركه مع أحد.'),
          const SizedBox(height: 16),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) showMsg(dialogContext, 'تم نسخ رمز الاسترداد.');
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ الرمز'),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('حفظته، متابعة'),
        ),
      ],
    ),
  );
}

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final identifier = TextEditingController();
  final recoveryCode = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool busy = false;
  bool obscureCode = true;

  @override
  void dispose() {
    identifier.dispose();
    recoveryCode.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (identifier.text.trim().isEmpty ||
        recoveryCode.text.trim().isEmpty ||
        newPassword.text.isEmpty ||
        confirmPassword.text.isEmpty) {
      showMsg(context, 'أكمل جميع الحقول.');
      return;
    }
    if (newPassword.text.length < 8 || newPassword.text.length > 128) {
      showMsg(context, 'كلمة المرور يجب أن تكون بين 8 و128 حرفًا.');
      return;
    }
    if (newPassword.text != confirmPassword.text) {
      showMsg(context, 'كلمتا المرور غير متطابقتين.');
      return;
    }
    setState(() => busy = true);
    try {
      await Api.recoverPassword(
        identifier: identifier.text,
        recoveryCode: recoveryCode.text,
        newPassword: newPassword.text,
      );
      if (!mounted) return;
      showMsg(context, 'تم تحديث كلمة المرور. يمكنك تسجيل الدخول الآن.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استرداد الحساب')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const Icon(Icons.shield_outlined, size: 58),
              const SizedBox(height: 12),
              const Text(
                'استعد الوصول إلى حسابك',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'أدخل اسم المستخدم أو رقم الهاتف ورمز الاسترداد الذي حفظته عند إنشاء الحساب أو تدويره.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: identifier,
                decoration: inputDecoration('اسم المستخدم أو رقم الهاتف', Icons.person_outline),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: recoveryCode,
                textCapitalization: TextCapitalization.characters,
                decoration: inputDecoration('رمز الاسترداد', Icons.key).copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => obscureCode = !obscureCode),
                    icon: Icon(obscureCode ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                obscureText: obscureCode,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassword,
                obscureText: true,
                decoration: inputDecoration('كلمة المرور الجديدة', Icons.lock_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassword,
                obscureText: true,
                decoration: inputDecoration('تأكيد كلمة المرور الجديدة', Icons.lock_reset),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('تحديث كلمة المرور'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'لا نستخدم رسائل SMS أو البريد الإلكتروني. رمز الاسترداد صالح للاستخدام مرة واحدة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration inputDecoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );

void showMsg(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmVoiceTranscription(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('تحويل التسجيل إلى نص'),
      content: const Text('سيُرسل الملف الصوتي إلى خدمة Cloudflare Workers AI لمعالجة الكلام وإرجاع النص. لا يُحفظ الملف في جدول الرسائل، لكن المعالجة تتم عبر الإنترنت وقد تُحتسب عليها تكلفة تشغيل. هل تريد المتابعة؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
          onPressed: () => Navigator.pop(dialogContext, true), child: const Text('متابعة')),
      ],
    ),
  );
  return accepted == true;
}

String cleanError(Object error) => error.toString().replaceFirst('Exception: ', '');

class HomePage extends StatefulWidget {
  final Map<String, dynamic> user;
  const HomePage({super.key, required this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int selectedTab = 0;
  late Map<String, dynamic> me = widget.user;
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> matchedContacts = [];
  bool matchingContacts = false;
  bool phoneContactsPermissionGranted = false;
  DateTime? lastPhoneContactsSyncAt;
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> statuses = [];
  List<Map<String, dynamic>> memories = [];
  bool memoriesLoadFailed = false;
  bool loading = true;
  Map<String, dynamic> privacySettings = {'searchable': true, 'readReceipts': true};
  Map<String, dynamic> notificationPrefs = {'messages': true, 'groups': true, 'statuses': true};
  Map<String, dynamic> referralStats = {};
  Timer? offlineSyncTimer;

  String get myId => field(me, ['id', 'user_id']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedFriends().whenComplete(() { if (mounted) refreshAll(); });
    offlineSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      BarqOfflineQueue.syncOutbox();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    offlineSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BarqOfflineQueue.syncOutbox();
      if (phoneContactsPermissionGranted) matchPhoneContacts(silent: true);
    }
  }

  Future<void> _loadCachedFriends() async {
    try {
      final raw = await storage.read(key: 'barq_cached_friends');
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is List && mounted) {
        setState(() => friends = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList());
      }
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        Api.friends(),
        Api.me(),
      ]);
      friends = results[0] as List<Map<String, dynamic>>;
      me = results[1] as Map<String, dynamic>;
      await storage.write(key: 'barq_cached_friends', value: jsonEncode(friends));
      await storage.write(key: 'barq_cached_user', value: jsonEncode(me));
      try {
        statuses = await Api.statuses();
      } catch (_) {
        statuses = [];
      }
      try {
        privacySettings = await Api.privacy();
      } catch (_) {
        // لا نعطل بقية التطبيق إذا لم يكن تحديث الخصوصية منشوراً على الخادم بعد.
      }
      try {
        notificationPrefs = await Api.notificationSettings();
      } catch (_) {
        // يبقى التطبيق متاحاً إذا لم يُنشر مسار إعدادات الإشعارات بعد.
      }
      try {
        groups = await Api.groups();
      } catch (_) {
        // لا نعطل المحادثات الفردية إذا لم تُنشر واجهة المجموعات على الخادم بعد.
      }
      try {
        memories = await Api.privateMemories();
        memoriesLoadFailed = false;
      } catch (_) {
        // Preserve previously loaded memories; a network error must not look like an empty vault.
        memoriesLoadFailed = true;
      }
      try {
        referralStats = await Api.referrals();
      } catch (_) {
        // يبقى التطبيق متاحًا قبل نشر مسارات الإحالات.
      }
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> matchPhoneContacts({bool silent = false, bool force = false}) async {
    if (matchingContacts) return;
    final lastSync = lastPhoneContactsSyncAt;
    if (!force && lastSync != null &&
        DateTime.now().difference(lastSync) < const Duration(minutes: 1)) {
      return;
    }
    if (mounted) setState(() => matchingContacts = true);
    try {
      final permitted = await FlutterContacts.requestPermission(readonly: true);
      if (!permitted) {
        phoneContactsPermissionGranted = false;
        if (mounted && !silent) showMsg(context, 'لم يتم منح إذن جهات الاتصال. يمكنك تفعيله من إعدادات الهاتف.');
        return;
      }
      phoneContactsPermissionGranted = true;
      final phoneContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      final phones = phoneContacts
          .expand((contact) => contact.phones)
          .map((phone) => phone.number.trim())
          .where((number) => number.isNotEmpty)
          .toSet()
          .take(500)
          .toList();
      final matches = await Api.matchPhoneContacts(phones);
      lastPhoneContactsSyncAt = DateTime.now();
      if (mounted) setState(() => matchedContacts = matches);
      if (mounted && !silent) showMsg(context, 'تم العثور على ${matches.length} شخص مسجل في برق من جهات هاتفك.');
    } catch (e) {
      if (mounted && !silent) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => matchingContacts = false);
    }
  }

  Future<void> searchUsers() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> found = [];
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('البحث عن مستخدم'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: inputDecoration('اسم المستخدم أو الهاتف', Icons.search),
                  onSubmitted: (_) async {
                    if (controller.text.trim().length < 2) return;
                    setDialog(() => busy = true);
                    try {
                      found = await Api.search(controller.text.trim());
                    } catch (e) {
                      if (mounted) showMsg(this.context, cleanError(e));
                    }
                    setDialog(() => busy = false);
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy ? null : () async {
                      if (controller.text.trim().length < 2) return;
                      setDialog(() => busy = true);
                      try {
                        found = await Api.search(controller.text.trim());
                      } catch (e) {
                        if (mounted) showMsg(this.context, cleanError(e));
                      }
                      setDialog(() => busy = false);
                    },
                    child: const Text('بحث'),
                  ),
                ),
                if (busy) const CircularProgressIndicator(color: gold),
                if (!busy && found.isEmpty) const Text('اكتب حرفين على الأقل ثم اضغط بحث.', style: TextStyle(color: Colors.white60)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: found.map((person) {
                      final id = field(person, ['id', 'user_id']);
                      final uname = field(person, ['username'], 'مستخدم');
                      return ListTile(
                        leading: personAvatar(person),
                        title: Text(field(person, ['displayName', 'display_name'], uname)),
                        subtitle: Text('@$uname'),
                        onTap: () => Navigator.push(this.context, MaterialPageRoute(
                          builder: (_) => PublicProfilePage(person: person, currentUserId: myId, canMessage: true),
                        )),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_add_alt_1),
                          onPressed: id.isEmpty ? null : () async {
                            try {
                              await Api.addContact(id);
                              if (mounted) {
                                showMsg(this.context, 'تمت إضافة الشخص إلى جهات اتصالك.');
                                await refreshAll();
                              }
                            } catch (e) {
                              if (mounted) showMsg(this.context, cleanError(e));
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _chatsPage(),
      _statusesPage(),
      _friendsPage(),
      _groupsPage(),
      _memoriesPage(),
      _accountPage(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('برق', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(onPressed: refreshAll, icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary), tooltip: 'تحديث'),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: gold))
            : pages[selectedTab],
        floatingActionButton: selectedTab >= 1 && selectedTab <= 4
            ? FloatingActionButton(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: selectedTab == 1
                    ? publishStatusDialog
                    : (selectedTab == 2
                        ? searchUsers
                        : (selectedTab == 3 ? createGroupDialog : _showPrivateMemoryDialog)),
                child: Icon(selectedTab == 1
                    ? Icons.add
                    : (selectedTab == 2
                        ? Icons.person_add
                        : (selectedTab == 3 ? Icons.group_add : Icons.auto_awesome))),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedTab,
          onDestinationSelected: (value) {
            setState(() => selectedTab = value);
            // Refresh phone matches automatically whenever the contacts tab is opened.
            // Permission is requested by the plugin only when the user first enters this tab.
            if (value == 2) matchPhoneContacts();
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'المحادثات'),
            NavigationDestination(icon: Icon(Icons.circle_outlined), label: 'SPARK'),
            NavigationDestination(icon: Icon(Icons.people_outline), label: 'الأشخاص'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'المجموعات'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'الذكريات'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
          ],
        ),
      ),
    );
  }

  Future<void> publishStatusDialog() async {
    final controller = TextEditingController();
    String backgroundKey = 'midnight';
    String textColorKey = 'white';
    String fontKey = 'modern';
    const backgrounds = <String, Color>{
      'electric_blue': Color(0xFF0757D5),
      'violet': Color(0xFF43206F),
      'gold': Color(0xFFB98B2F),
      'midnight': Color(0xFF101827),
    };
    const backgroundLabels = <String, String>{
      'electric_blue': 'أزرق برق',
      'violet': 'بنفسجي',
      'gold': 'ذهبي',
      'midnight': 'داكن',
    };
    const textColors = <String, Color>{
      'white': Colors.white, 'black': Colors.black, 'gold': Color(0xFFFFD166),
    };
    const textColorLabels = <String, String>{
      'white': 'أبيض', 'black': 'أسود', 'gold': 'ذهبي',
    };
    const fonts = <String, String>{
      'modern': 'حديث', 'classic': 'كلاسيكي', 'mono': 'تقني',
    };
    Color previewTextColor() => textColors[textColorKey]!;
    String? previewFontFamily() => switch (fontKey) {
      'classic' => 'serif',
      'mono' => 'monospace',
      _ => null,
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('النشر في SPARK'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                constraints: const BoxConstraints(minHeight: 116),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: backgrounds[backgroundKey], borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(
                  controller.text.isEmpty ? 'معاينة لحظتك' : controller.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: previewTextColor(), fontSize: 20, fontFamily: previewFontFamily(), fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                maxLines: 4,
                onChanged: (_) => setDialogState(() {}),
                decoration: inputDecoration('ماذا تريد أن تشارك؟', Icons.edit_note),
              ),
              const SizedBox(height: 8),
              const Text('الخلفية', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              Wrap(spacing: 7, runSpacing: 4, children: backgrounds.entries.map((entry) => ChoiceChip(
                label: Text(backgroundLabels[entry.key]!),
                selected: backgroundKey == entry.key,
                selectedColor: entry.value,
                onSelected: (_) => setDialogState(() {
                  backgroundKey = entry.key;
                  if (backgroundKey == 'gold') {
                    textColorKey = 'black';
                  } else if (textColorKey == 'black') {
                    textColorKey = 'white';
                  }
                }),
              )).toList()),
              const SizedBox(height: 6),
              const Text('لون النص', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              Wrap(spacing: 7, children: textColors.entries
                .where((entry) => backgroundKey == 'gold' ? entry.key == 'black' : entry.key != 'black')
                .map((entry) => ChoiceChip(
                label: Text(textColorLabels[entry.key]!),
                selected: textColorKey == entry.key,
                selectedColor: entry.value.withValues(alpha: .28),
                onSelected: (_) => setDialogState(() => textColorKey = entry.key),
              )).toList()),
              const SizedBox(height: 6),
              const Text('الخط', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              Wrap(spacing: 7, children: fonts.entries.map((entry) => ChoiceChip(
                label: Text(entry.value),
                selected: fontKey == entry.key,
                onSelected: (_) => setDialogState(() => fontKey = entry.key),
              )).toList()),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: () async {
                final content = controller.text.trim();
                if (content.isEmpty) return;
                try {
                  await Api.publishStatus(content, backgroundKey: backgroundKey, textColorKey: textColorKey, fontKey: fontKey);
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await refreshAll();
                  if (!context.mounted) return;
                  showMsg(context, 'نُشرت حالتك لمدة 24 ساعة.');
                } catch (e) {
                  if (context.mounted) showMsg(context, cleanError(e));
                }
              },
              child: const Text('نشر في SPARK'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> publishSparkMediaDialog() async {
    final pageContext = context;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.media, allowMultiple: true, withData: false,
    );
    if (picked == null || picked.files.isEmpty || !pageContext.mounted) return;
    if (picked.files.length > 10) {
      showMsg(pageContext, 'يمكن نشر 10 وسائط كحد أقصى في اللحظة الواحدة.');
      return;
    }
    final prepared = <Map<String, dynamic>>[];
    String? preparationError;
    for (final file in picked.files) {
      final extension = (file.extension ?? '').toLowerCase();
      final contentType = barqSparkMediaContentType(extension);
      if (contentType == null) {
        preparationError = 'الملف ${file.name} ليس بصيغة صورة أو فيديو مدعومة.';
        break;
      }
      if (!isBarqSparkMediaSizeAllowed(file.size)) {
        preparationError = 'حجم الملف ${file.name} غير صالح أو يتجاوز 60 ميجابايت.';
        break;
      }
      prepared.add({'file': file, 'contentType': contentType});
    }
    if (!pageContext.mounted) return;
    if (preparationError != null) {
      showMsg(pageContext, preparationError);
      return;
    }
    final captionController = TextEditingController();
    await showDialog<void>(
      context: pageContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        var uploading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: !uploading,
            child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text('نشر ${prepared.length} وسائط في SPARK'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(prepared.map((item) => (item['file'] as PlatformFile).name).join('، '),
                maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              TextField(
                controller: captionController, maxLength: 1000, maxLines: 3,
                decoration: inputDecoration('أضف تعليقًا للّحظة (اختياري)', Icons.edit_note),
              ),
              if (uploading) const LinearProgressIndicator(color: gold),
            ]),
            actions: [
              TextButton(
                onPressed: uploading ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
                onPressed: uploading ? null : () async {
                  setDialogState(() => uploading = true);
                  String? statusId;
                  var uploaded = 0;
                  try {
                    for (final item in prepared) {
                      final file = item['file'] as PlatformFile;
                      // Read one media file at a time to avoid retaining up to 600 MB in memory.
                      final bytes = file.bytes ??
                          (file.path == null ? null : await File(file.path!).readAsBytes());
                      if (bytes == null || !isBarqSparkMediaSizeAllowed(bytes.length)) {
                        throw Exception('تعذر قراءة ${file.name} أو تجاوز حجمه 60 ميجابايت.');
                      }
                      statusId = await Api.publishSparkMedia(
                        bytes: bytes,
                        fileName: file.name,
                        contentType: item['contentType'] as String,
                        caption: captionController.text,
                        statusId: statusId,
                      );
                      uploaded++;
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    try { await refreshAll(); } catch (_) {
                      // The upload is already committed; a refresh failure must not
                      // misreport the published media as an upload failure.
                    }
                    if (pageContext.mounted) {
                      showMsg(pageContext, 'نُشرت $uploaded وسائط في لحظة SPARK واحدة لمدة 24 ساعة.');
                    }
                  } catch (e) {
                    if (uploaded > 0) {
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      try { await refreshAll(); } catch (_) {
                        // Keep the partial-upload result truthful even if refresh fails.
                      }
                      if (pageContext.mounted) {
                        showMsg(pageContext, 'نُشر $uploaded من ${prepared.length} وسائط. تعذر إكمال البقية: ${cleanError(e)}');
                      }
                    } else {
                      if (dialogContext.mounted) setDialogState(() => uploading = false);
                      if (pageContext.mounted) showMsg(pageContext, cleanError(e));
                    }
                  }
                },
                child: const Text('نشر في SPARK'),
              ),
            ],
          ),
          ),
        );
      },
    );
    captionController.dispose();
  }

  Future<void> _showSparkViewers(String statusId) async {
    try {
      final viewers = await Api.sparkViewers(statusId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('مشاهدو SPARK', style: TextStyle(color: gold))),
              if (viewers.isEmpty)
                const ListTile(title: Text('لم يشاهدها أحد بعد', style: TextStyle(color: Colors.white60))),
              for (final viewer in viewers)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(field(viewer, ['displayName', 'username'], 'مستخدم برق')),
                  subtitle: Text(field(viewer, ['viewedAt'])),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  void _openSparkStatus(Map<String, dynamic> status) {
    final statusId = field(status, ['id']);
    Api.markSparkViewed(statusId).catchError((_) {});
    final rawMedia = status['media'];
    final media = rawMedia is List
        ? rawMedia.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SparkMediaViewer(
          statusId: field(status, ['id']),
          media: media,
          author: field(status, ['displayName', 'display_name', 'username'], 'مستخدم برق'),
          caption: field(status, ['content']),
          backgroundKey: field(status, ['backgroundKey', 'background_key'], 'midnight'),
          textColorKey: field(status, ['textColorKey', 'text_color_key'], 'white'),
          fontKey: field(status, ['fontKey', 'font_key'], 'modern'),
        ),
      ),
    );
  }

  Widget _statusesPage() {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('SPARK', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 21, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: publishStatusDialog,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('نشر نص'),
                  style: OutlinedButton.styleFrom(foregroundColor: gold, side: const BorderSide(color: gold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: publishSparkMediaDialog,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('صورة أو فيديو'),
                  style: OutlinedButton.styleFrom(foregroundColor: gold, side: const BorderSide(color: gold)),
                ),
              ),
            ]),
          ),
          if (statuses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 45, horizontal: 18),
              child: Column(children: [
                Icon(Icons.circle_outlined, size: 54),
                SizedBox(height: 12),
                Text('لا توجد حالات نشطة', style: TextStyle(color: gold, fontSize: 18)),
                SizedBox(height: 6),
                Text('انشر أول لحظة في SPARK أو اسحب للأسفل للتحديث.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              ]),
            ),
          for (final status in statuses)
            Card(
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                onTap: () => _openSparkStatus(status),
                leading: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [electricBlue, gold]),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF46391F),
                    child: ClipOval(
                      child: field(status, ['photoUrl', 'photo_url']).isEmpty
                          ? const Icon(Icons.person)
                          : Image.network(
                              '$apiBase${field(status, ['photoUrl', 'photo_url'])}?v=${Uri.encodeComponent(field(status, ['photoUpdatedAt', 'photo_updated_at']))}',
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              headers: {'Authorization': 'Bearer ${Api.token}'},
                              errorBuilder: (_, __, ___) => const Icon(Icons.person),
                            ),
                    ),
                  ),
                ),
                title: Text(field(status, ['displayName', 'display_name', 'username'], 'مستخدم برق')),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    field(status, ['content']).isNotEmpty
                        ? field(status, ['content'])
                        : ((status['media'] is List && (status['media'] as List).isNotEmpty)
                            ? 'اضغط لمشاهدة وسائط SPARK'
                            : 'لحظة جديدة في SPARK'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                trailing: status['userId']?.toString() == myId
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'المشاهدون',
                          onPressed: () => _showSparkViewers(field(status, ['id'])),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        Text((status['viewCount'] ?? 0).toString(), style: const TextStyle(color: Colors.white70)),
                      ])
                    : const Icon(Icons.play_circle_outline, size: 24),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chatsPage() {
    if (friends.isEmpty) {
      return _empty(Icons.chat_bubble_outline, 'لا توجد محادثات بعد', 'ابحث عن شخص وأضفه إلى جهات اتصالك لتبدأ المراسلة.');
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('محادثاتك', style: TextStyle(color: gold, fontSize: 21)),
        ),
        for (final friend in friends)
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              leading: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PublicProfilePage(person: friend, currentUserId: myId, canMessage: true),
                )),
                child: personAvatar(friend),
              ),
              title: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PublicProfilePage(person: friend, currentUserId: myId, canMessage: true),
                )),
                child: Text(_personName(friend)),
              ),
              subtitle: Text('@${_personUsername(friend)}'),
              trailing: IconButton(
                tooltip: 'فتح المحادثة',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatPage(friend: friend, currentUserId: myId),
                )),
              ),
            ),
          ),
      ],
    );
  }

  String _personName(Map<String, dynamic> p) {
    final nested = p['user'] is Map ? Map<String, dynamic>.from(p['user']) : p;
    return field(nested, ['displayName', 'display_name', 'name', 'username'], 'صديق');
  }

  String _personUsername(Map<String, dynamic> p) {
    final nested = p['user'] is Map ? Map<String, dynamic>.from(p['user']) : p;
    return field(nested, ['username'], 'user');
  }

  Widget _friendsPage() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(child: Text('جهات الاتصال', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 21))),
            IconButton(onPressed: searchUsers, icon: const Icon(Icons.search), tooltip: 'البحث والإضافة'),
            IconButton(
              onPressed: matchingContacts ? null : () => matchPhoneContacts(force: true),
              icon: matchingContacts
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.contacts_outlined),
              tooltip: 'مطابقة جهات الهاتف',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (matchedContacts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('أشخاص من جهات هاتفك على برق', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
          for (final person in matchedContacts)
            Card(
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                leading: personAvatar(person),
                title: Text(_personName(person)),
                subtitle: Text(field(person, ['phone'], '@${_personUsername(person)}')),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PublicProfilePage(person: person, currentUserId: myId, canMessage: true),
                )),
                trailing: IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'إضافة مباشرة',
                  onPressed: () async {
                    try {
                      await Api.addContact(field(person, ['id']));
                      if (mounted) {
                        setState(() => matchedContacts.removeWhere((item) => field(item, ['id']) == field(person, ['id'])));
                        await refreshAll();
                        if (mounted) {
                          showMsg(context, 'تمت الإضافة ويمكنك بدء المراسلة مباشرة.');
                        }
                      }
                    } catch (e) { if (mounted) showMsg(context, cleanError(e)); }
                  },
                ),
              ),
            ),
        ],
        if (friends.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text('لا توجد جهات اتصال بعد. ابحث باسم المستخدم أو رقم الهاتف وأضف الأشخاص مباشرة.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
          ),
        for (final person in friends)
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              leading: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PublicProfilePage(person: person, currentUserId: myId, canMessage: true),
                )),
                child: personAvatar(person),
              ),
              title: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PublicProfilePage(person: person, currentUserId: myId, canMessage: true),
                )),
                child: Text(_personName(person)),
              ),
              subtitle: Text('@${_personUsername(person)}'),
              trailing: IconButton(
                icon: const Icon(Icons.chat),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatPage(friend: person, currentUserId: myId),
                )),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> createGroupDialog() async {
    final name = TextEditingController();
    final description = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('إنشاء مجموعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, maxLength: 80, decoration: inputDecoration('اسم المجموعة', Icons.group)),
            const SizedBox(height: 8),
            TextField(controller: description, maxLength: 500, maxLines: 2,
              decoration: inputDecoration('وصف المجموعة (اختياري)', Icons.info_outline)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
            onPressed: () async {
              if (name.text.trim().length < 2) {
                showMsg(context, 'اكتب اسماً للمجموعة من حرفين على الأقل.');
                return;
              }
              try {
                await Api.createGroup(name.text.trim(), description.text.trim());
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await refreshAll();
                if (mounted) showMsg(context, 'تم إنشاء المجموعة. يمكنك فتحها وإضافة الأعضاء.');
              } catch (e) {
                if (mounted) showMsg(context, cleanError(e));
              }
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
  }

  Future<void> addMemberDialog(Map<String, dynamic> group) async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> found = [];
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('إضافة عضو للمجموعة'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: controller, decoration: inputDecoration('اسم المستخدم أو الهاتف', Icons.search)),
              Align(alignment: Alignment.centerLeft, child: TextButton(
                onPressed: busy ? null : () async {
                  if (controller.text.trim().length < 2) return;
                  setDialog(() => busy = true);
                  try { found = await Api.search(controller.text.trim()); }
                  catch (e) { if (mounted) showMsg(this.context, cleanError(e)); }
                  setDialog(() => busy = false);
                }, child: const Text('بحث'))),
              if (busy) const CircularProgressIndicator(color: gold),
              Flexible(child: ListView(shrinkWrap: true, children: found.map((person) {
                final id = field(person, ['id', 'user_id']);
                final uname = field(person, ['username'], 'مستخدم');
                return ListTile(
                  title: Text(field(person, ['displayName', 'display_name'], uname)),
                  subtitle: Text('@$uname'),
                  trailing: IconButton(icon: const Icon(Icons.person_add_alt_1),
                    onPressed: id.isEmpty ? null : () async {
                      try {
                        await Api.addGroupMember(field(group, ['id']), id);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) showMsg(this.context, 'تمت إضافة العضو.');
                      } catch (e) { if (mounted) showMsg(this.context, cleanError(e)); }
                    }),
                );
              }).toList())),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        ),
      ),
    );
    controller.dispose();
  }

  Widget _privateMemoryLeading(Map<String, dynamic> memory) {
    final rawMedia = memory['media'];
    if (rawMedia is List && rawMedia.isNotEmpty && rawMedia.first is Map) {
      final media = Map<String, dynamic>.from(rawMedia.first as Map);
      final attachmentId = field(media, ['attachmentId']);
      if (attachmentId.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            Api.sparkMediaUri(attachmentId).toString(),
            headers: {if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'},
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const CircleAvatar(
              backgroundColor: Color(0xFF46391F),
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      }
    }
    return CircleAvatar(
      backgroundColor: const Color(0xFF46391F),
      child: Icon(
        field(memory, ['sourceType']) == 'message' ? Icons.chat_bubble_outline : Icons.auto_awesome,
        color: gold,
      ),
    );
  }

  Future<void> _showPrivateMemoryPhotos(Map<String, dynamic> memory) async {
    final rawMedia = memory['media'];
    final media = rawMedia is List
        ? rawMedia.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    if (media.isEmpty) {
      await _showPrivateMemoryDialog(memory: memory);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(field(memory, ['title'], 'صور الذكرى')),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: PrivateMemoryPhotoGallery(media: media),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _memoriesPage() {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () async {
        try {
          final loaded = await Api.privateMemories();
          if (mounted) {
            setState(() {
              memories = loaded;
              memoriesLoadFailed = false;
            });
          }
        } catch (e) {
          if (mounted) setState(() => memoriesLoadFailed = true);
          if (mounted) showMsg(context, cleanError(e));
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('مساحة ذكرياتك الخاصة', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 21)),
          ),
          if (memoriesLoadFailed)
            PrivateMemoryLoadError(
              onRetry: () async {
                try {
                  final loaded = await Api.privateMemories();
                  if (mounted) {
                    setState(() {
                      memories = loaded;
                      memoriesLoadFailed = false;
                    });
                  }
                } catch (e) {
                  if (mounted) showMsg(context, cleanError(e));
                }
              },
            )
          else if (memories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
              child: Column(
                children: [
                  const Icon(Icons.auto_awesome, size: 54),
                  const SizedBox(height: 12),
                  const Text('احتفظ بلحظاتك المهمة هنا', style: TextStyle(color: gold, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('هذه المساحة خاصة بك وحدك. أضف ذكرى أو احفظ نصًا من محادثاتك.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _showPrivateMemoryDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة ذكرى'),
                  ),
                ],
              ),
            ),
          for (final memory in memories)
            Card(
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                leading: GestureDetector(
                  onTap: () => _showPrivateMemoryPhotos(memory),
                  child: _privateMemoryLeading(memory),
                ),
                title: Text(field(memory, ['title'], 'ذكرى محفوظة')),
                subtitle: Text(
                  field(memory, ['content'], 'صورة محفوظة'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _showPrivateMemoryDialog(memory: memory),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _showPrivateMemoryDialog(memory: memory);
                    if (value == 'delete') _deletePrivateMemory(memory);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showPrivateMemoryDialog({
    Map<String, dynamic>? memory,
    String initialContent = '',
    String sourceType = 'text',
  }) async {
    final pageContext = context;
    final titleController = TextEditingController(text: field(memory ?? {}, ['title']));
    final contentController = TextEditingController(
      text: memory == null ? initialContent : field(memory, ['content']),
    );
    final editing = memory != null;
    final existingPhotos = memory?['media'] is List
        ? (memory!['media'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final photos = <Map<String, dynamic>>[];
    await showDialog<void>(
      context: pageContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        var saving = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(editing ? 'تعديل الذكرى' : 'إضافة ذكرى خاصة'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      maxLength: 120,
                      decoration: inputDecoration('عنوان الذكرى (اختياري)', Icons.title),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contentController,
                      autofocus: true,
                      maxLength: 10000,
                      minLines: 4,
                      maxLines: 8,
                      decoration: inputDecoration('اكتب ما تريد الاحتفاظ به', Icons.edit_note),
                    ),
                    const SizedBox(height: 10),
                    if (existingPhotos.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text('الصور المحفوظة في هذه الذكرى', style: TextStyle(color: gold)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in existingPhotos)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                Api.sparkMediaUri(field(item, ['attachmentId'])).toString(),
                                headers: {if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'},
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 72,
                                  height: 72,
                                  color: const Color(0xFF292929),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: saving ? null : () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          allowMultiple: true,
                          withData: true,
                        );
                        if (result == null || result.files.isEmpty || !dialogContext.mounted) return;
                        final selected = <Map<String, dynamic>>[];
                        String? error;
                        for (final file in result.files) {
                          final extension = (file.extension ?? '').toLowerCase();
                          final contentType = switch (extension) {
                            'jpg' || 'jpeg' => 'image/jpeg',
                            'png' => 'image/png',
                            'webp' => 'image/webp',
                            _ => '',
                          };
                          final bytes = file.bytes;
                          if (contentType.isEmpty || bytes == null || bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
                            error = 'كل صورة يجب أن تكون JPG أو PNG أو WebP وألا يتجاوز حجمها 4 ميجابايت.';
                            break;
                          }
                          selected.add({'bytes': bytes, 'name': file.name, 'contentType': contentType});
                        }
                        if (error != null) {
                          showMsg(dialogContext, error);
                          return;
                        }
                        setDialogState(() => photos.addAll(selected));
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(photos.isEmpty ? 'إرفاق صور خاصة' : 'إضافة صور (${photos.length})'),
                    ),
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var index = 0; index < photos.length; index++)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    Uint8List.fromList(photos[index]['bytes'] as List<int>),
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black87,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: saving ? null : () => setDialogState(() => photos.removeAt(index)),
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                    if (saving) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(color: gold),
                    ],
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text('لا يراها سواك', style: TextStyle(color: gold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: saving ? null : () async {
                    final content = contentController.text.trim();
                    final title = titleController.text.trim();
                    final effectiveTitle = title.isEmpty && content.isEmpty && photos.isNotEmpty
                        ? 'صور محفوظة'
                        : title;
                    if ((content.isEmpty && effectiveTitle.isEmpty && photos.isEmpty) ||
                        content.length > 10000 || effectiveTitle.length > 120) {
                      showMsg(dialogContext, 'أضف عنوانًا أو محتوى أو صورة للذكرى.');
                      return;
                    }
                    setDialogState(() => saving = true);
                    late final Map<String, dynamic> saved;
                    try {
                      saved = editing
                          ? await Api.updatePrivateMemory(
                              id: field(memory, ['id']),
                              title: effectiveTitle,
                              content: content,
                            )
                          : await Api.savePrivateMemory(
                              title: effectiveTitle,
                              content: content,
                              sourceType: sourceType,
                            );
                    } catch (e) {
                      if (dialogContext.mounted) {
                        setDialogState(() => saving = false);
                        showMsg(dialogContext, cleanError(e));
                      }
                      return;
                    }
                    final failedPhotoNames = await uploadPrivateMemoryPhotosSequentially(
                      memoryId: field(saved, ['id']),
                      photos: photos,
                      upload: Api.uploadPrivateMemoryPhoto,
                    );
                    try {
                      final loaded = await Api.privateMemories();
                      if (mounted) {
                        setState(() {
                          memories = loaded;
                          memoriesLoadFailed = false;
                        });
                      }
                    } catch (_) {
                      if (mounted) setState(() => memoriesLoadFailed = true);
                      // The save/upload succeeded; a list refresh failure is not a save failure.
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (pageContext.mounted) {
                      if (failedPhotoNames.isEmpty) {
                        showMsg(pageContext, editing ? 'تم تحديث الذكرى.' : 'تم حفظ الذكرى بشكل خاص.');
                      } else {
                        final uploadedCount = photos.length - failedPhotoNames.length;
                        showMsg(
                          pageContext,
                          'تم حفظ الذكرى ورفع $uploadedCount من ${photos.length} صور. تعذر رفع: ${failedPhotoNames.join('، ')}',
                        );
                      }
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        );
      },
    );
    titleController.dispose();
    contentController.dispose();
  }

  Future<void> _deletePrivateMemory(Map<String, dynamic> memory) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('حذف الذكرى؟'),
        content: const Text('سيتم حذف هذه الذكرى من مساحتك الخاصة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await Api.deletePrivateMemory(field(memory, ['id']));
      if (mounted) {
        setState(() => memories.removeWhere((item) => item['id'] == memory['id']));
        showMsg(context, 'تم حذف الذكرى.');
      }
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  Widget _groupsPage() {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(padding: const EdgeInsets.all(12),
            child: Text('مجموعاتك', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 21))),
          if (groups.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text(
              'لا توجد مجموعات بعد. أنشئ مجموعة وابدأ بإضافة الأشخاص مباشرة.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
          for (final group in groups)
            Card(color: Theme.of(context).colorScheme.surface, child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF46391F), child: Icon(Icons.groups)),
              title: Text(field(group, ['name'], 'مجموعة')),
              subtitle: Text('${field(group, ['description'], 'مجموعة برق')} • ${field(group, ['member_count'], '1')} أعضاء'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => GroupChatPage(
                  group: group,
                  currentUserId: myId,
                  onAddMember: () => addMemberDialog(group),
                  onGroupChanged: refreshAll,
                ))),
            )),
        ],
      ),
    );
  }


  Widget _empty(IconData icon, String title, String subtitle) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: gold, fontSize: 22)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      );

  Future<void> pickProfilePhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        showMsg(context, 'تعذر قراءة الصورة المختارة. جرّب صورة أخرى.');
        return;
      }
      if (bytes.length > 4 * 1024 * 1024) {
        showMsg(context, 'حجم الصورة أكبر من 4 ميجابايت. اختر صورة أصغر.');
        return;
      }
      final extension = file.extension?.toLowerCase() ?? '';
      final contentType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => '',
      };
      if (contentType.isEmpty) {
        showMsg(context, 'الصيغ المدعومة هي JPG وPNG وWebP.');
        return;
      }
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('معاينة صورة الملف الشخصي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(bytes, width: 220, height: 220, fit: BoxFit.cover),
              ),
              const SizedBox(height: 10),
              Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              const Text('سيتم رفع الصورة بشكل خاص إلى حسابك.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('اعتماد الصورة'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      showMsg(context, 'جارٍ رفع الصورة...');
      await Api.uploadProfilePhoto(bytes, contentType);
      final refreshed = await Api.me();
      if (!mounted) return;
      setState(() => me = refreshed);
      showMsg(context, 'تم تحديث صورة الملف الشخصي.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  Future<void> editProfileDialog() async {
    final nameController = TextEditingController(
      text: field(me, ['displayName', 'display_name']),
    );
    final phoneController = TextEditingController(
      text: field(me, ['phone']),
    );
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('تعديل الملف الشخصي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                maxLength: 60,
                decoration: inputDecoration('الاسم الظاهر', Icons.person_outline),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 25,
                decoration: inputDecoration('رقم الهاتف', Icons.phone_outlined)
                    .copyWith(hintText: '+رمز الدولة ورقم الهاتف'),
              ),
              const SizedBox(height: 6),
              const Text('اسم المستخدم لا يتغير من هذه الشاشة.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: saving ? null : () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  showMsg(this.context, 'اكتب الاسم الظاهر أولاً.');
                  return;
                }
                final phone = normalizeBarqInternationalPhone(phoneController.text);
                if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
                  showMsg(this.context, 'أدخل رقم الهاتف مع مفتاح الدولة بصيغة دولية صحيحة.');
                  return;
                }
                setDialog(() => saving = true);
                try {
                  final updated = await Api.updateProfile(
                    displayName: name,
                    phone: phone,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  setState(() => me = updated);
                  Navigator.pop(dialogContext);
                  showMsg(this.context, 'تم تحديث الملف الشخصي على الخادم.');
                } catch (e) {
                  if (mounted) showMsg(this.context, cleanError(e));
                  setDialog(() => saving = false);
                }
              },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('حفظ التغييرات'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> rotateRecoveryCodeDialog() async {
    final passwordController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إنشاء رمز استرداد جديد'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'كلمة المرور الحالية'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final value = passwordController.text;
              if (value.isEmpty) {
                showMsg(dialogContext, 'أدخل كلمة المرور الحالية.');
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) {
      passwordController.dispose();
      return;
    }
    try {
      final recoveryCode = await Api.rotateRecoveryCode(code);
      if (mounted) await showRecoveryCodeDialog(context, recoveryCode);
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      passwordController.dispose();
    }
  }

  Future<void> inviteFriendsDialog() async {
    try {
      final stats = await Api.referrals();
      if (!mounted) return;
      setState(() => referralStats = stats);
      final code = field(stats, ['inviteCode']);
      if (code.isEmpty) throw Exception('لم يتم إنشاء رمز الدعوة بعد.');
      final link = 'barq://invite/$code';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('ادعُ أصدقاءك إلى برق'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('هذا رابط دعوتك الخاص لمشاركة برق مع من تختار.'),
            const SizedBox(height: 14),
            Text('رمز الدعوة', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 10),
            SelectableText(link, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            const Text('الرابط يفتح برق إذا كان مثبتًا على جهاز صديقك. ويمكنه إدخال الرمز يدويًا أثناء التسجيل.', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (dialogContext.mounted) showMsg(dialogContext, 'تم نسخ رابط الدعوة.');
              },
              icon: const Icon(Icons.copy), label: const Text('نسخ الرابط'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: 'انضم إلى برق! استخدم رمز الدعوة $code أو افتح الرابط: $link'),
              ),
              icon: const Icon(Icons.share), label: const Text('مشاركة'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  Future<void> notificationSettingsDialog() async {
    bool messages = notificationPrefs['messages'] != false;
    bool groupsEnabled = notificationPrefs['groups'] != false;
    bool statusesEnabled = notificationPrefs['statuses'] != false;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('تفضيلات الإشعارات'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: Theme.of(context).colorScheme.primary,
              title: const Text('الرسائل الخاصة'), value: messages,
              onChanged: saving ? null : (v) => setDialog(() => messages = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: Theme.of(context).colorScheme.primary,
              title: const Text('رسائل المجموعات'), value: groupsEnabled,
              onChanged: saving ? null : (v) => setDialog(() => groupsEnabled = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: Theme.of(context).colorScheme.primary,
              title: const Text('حالات SPARK الجديدة'), value: statusesEnabled,
              onChanged: saving ? null : (v) => setDialog(() => statusesEnabled = v)),
            const SizedBox(height: 8),
            const Text('هذه تفضيلات محفوظة في حسابك؛ وصول إشعارات الهاتف الفعلية يتطلب استكمال ربط خدمة الإرسال.', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: saving ? null : () async {
                setDialog(() => saving = true);
                try {
                  final saved = await Api.saveNotificationSettings(messages: messages, groups: groupsEnabled, statuses: statusesEnabled);
                  if (!mounted || !dialogContext.mounted) return;
                  setState(() => notificationPrefs = saved);
                  Navigator.pop(dialogContext);
                  showMsg(this.context, 'تم حفظ تفضيلات الإشعارات في حسابك.');
                } catch (e) {
                  if (mounted) showMsg(this.context, cleanError(e));
                  setDialog(() => saving = false);
                }
              }, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Text('حفظ')),
          ],
        ),
      ),
    );
  }

  Future<void> privacySettingsDialog() async {
    bool searchable = privacySettings['searchable'] != false;
    bool readReceipts = privacySettings['readReceipts'] != false;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('الخصوصية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                title: const Text('السماح بالعثور علي'),
                subtitle: const Text('عند الإيقاف لن يظهر حسابك في نتائج البحث عن الأشخاص.'),
                value: searchable,
                onChanged: saving ? null : (value) => setDialog(() => searchable = value),
              ),
              const Divider(color: Colors.white24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                title: const Text('إشعارات قراءة الرسائل'),
                subtitle: const Text('عند الإيقاف لن يُسجل التطبيق قراءة الرسائل الواردة عند فتح المحادثة.'),
                value: readReceipts,
                onChanged: saving ? null : (value) => setDialog(() => readReceipts = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: saving ? null : () async {
                setDialog(() => saving = true);
                try {
                  final saved = await Api.savePrivacy(searchable: searchable, readReceipts: readReceipts);
                  if (!mounted || !dialogContext.mounted) return;
                  setState(() => privacySettings = saved);
                  Navigator.pop(dialogContext);
                  showMsg(this.context, 'تم حفظ إعدادات الخصوصية في حسابك.');
                } catch (e) {
                  if (mounted) showMsg(this.context, cleanError(e));
                  setDialog(() => saving = false);
                }
              },
              child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountPage() {
    final displayName = field(me, ['displayName', 'display_name'], 'مستخدم برق');
    final username = field(me, ['username'], 'siraj_user');
    final phone = field(me, ['phone'], 'غير مضاف');
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary),
            title: const Text('هوية برق البصرية'),
            subtitle: Text('اختر هويتك المفضلة • الحالية: ${BarqIdentity.label(BarqIdentity.selected.value)}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _showBarqIdentityPicker(context),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF302719), Color(0xFF17130D)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: gold.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Container(
                width: 90,
                height: 90,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: electricBlue.withValues(alpha: 0.55), width: 2),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 39,
                      backgroundColor: const Color(0xFF46391F),
                      backgroundImage: field(me, ['photoUrl']).isNotEmpty
                          ? NetworkImage(
                              '$apiBase${field(me, ['photoUrl'])}?v=${Uri.encodeComponent(field(me, ['photoUpdatedAt']))}',
                              headers: {'Authorization': 'Bearer ${Api.token}'},
                            )
                          : null,
                      child: field(me, ['photoUrl']).isEmpty
                          ? Text(displayName.isNotEmpty ? displayName.characters.first : 'س',
                              style: const TextStyle(color: gold, fontSize: 32))
                          : null,
                    ),
                    Positioned(
                      right: -5,
                      bottom: -5,
                      child: Material(
                        color: electricBlue,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: pickProfilePhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(displayName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              Text('@$username', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              Text(phone, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Card(
                    child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('حالة الاتصال'),
            subtitle: Text('متصل بخادم برق'),
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل الملف الشخصي'),
            subtitle: const Text('تغيير الاسم الظاهر ورقم الهاتف'),
            trailing: const Icon(Icons.chevron_left),
            onTap: editProfileDialog,
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('رمز استرداد الحساب'),
            subtitle: const Text('إنشاء رمز جديد بعد تأكيد كلمة المرور'),
            trailing: const Icon(Icons.chevron_left),
            onTap: rotateRecoveryCodeDialog,
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('إعدادات الخصوصية'),
            subtitle: const Text('الظهور في البحث وإشعارات قراءة الرسائل'),
            trailing: const Icon(Icons.chevron_left),
            onTap: privacySettingsDialog,
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('تفضيلات الإشعارات'),
            subtitle: const Text('الرسائل الخاصة والمجموعات وSPARK'),
            trailing: const Icon(Icons.chevron_left),
            onTap: notificationSettingsDialog,
          ),
        ),
        Card(
                    child: SwitchListTile(
            secondary: const Icon(Icons.flash_on_rounded),
            title: const Text('وضع البرق'),
            subtitle: const Text('أولوية للرسائل النصية وتعطيل إرسال الصور والفيديو والملفات لتقليل استهلاك البيانات.'),
            value: BarqFeatures.lightningMode,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (enabled) async {
              try {
                await BarqFeatures.setLightningMode(enabled);
                if (mounted) setState(() {});
              } catch (e) {
                if (mounted) showMsg(context, 'تعذر حفظ الإعداد: ${cleanError(e)}');
              }
            },
          ),
        ),
        Card(
                    child: SwitchListTile(
            secondary: const Icon(Icons.translate_rounded),
            title: const Text('الترجمة التلقائية عربي / إنجليزي'),
            subtitle: const Text('تعرض ترجمة الرسائل بجانب النص الأصلي باستخدام نموذج محلي على الجهاز. يمكنك إيقافها في أي وقت.'),
            value: BarqFeatures.autoTranslate,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (enabled) async {
              try {
                await BarqFeatures.setAutoTranslate(enabled);
                if (mounted) setState(() {});
              } catch (e) {
                if (mounted) showMsg(context, 'تعذر حفظ الإعداد: ${cleanError(e)}');
              }
            },
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text('المراسلة دون إنترنت — الأجهزة القريبة'),
            subtitle: const Text('اكتشاف هاتف صديق قريب ونقل الرسائل النصية دون إنترنت.'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NearbyDevicesPage(user: me, friends: friends))),
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.bolt),
            title: const Text('رابط الدعوة الخاص'),
            subtitle: const Text('شارك رابطك الخاص للانضمام إلى برق.'),
            trailing: const Icon(Icons.chevron_left),
            onTap: inviteFriendsDialog,
          ),
        ),
        Card(
                    child: ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('تحديث البيانات'),
            onTap: refreshAll,
          ),
        ),
        const SizedBox(height: 12),
        const Card(
                    child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('حول برق'),
            subtitle: Text('المطور: يحيى المهدي'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Api.logout();
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
  Future<void> _showBarqIdentityPicker(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<BarqIdentity>(
        valueListenable: BarqIdentity.selected,
        builder: (context, selected, _) => AlertDialog(
          title: const Text('اختر هوية برق'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: BarqIdentity.values.map((identity) {
              final palette = BarqIdentityPalette.forIdentity(identity);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    try {
                      await BarqIdentity.set(identity);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (e) {
                      if (dialogContext.mounted) {
                        showMsg(dialogContext, 'تعذر حفظ الهوية: ${cleanError(e)}');
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected == identity ? palette.primary : palette.border,
                        width: selected == identity ? 2 : 1,
                      ),
                      color: palette.surface,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [palette.primary, palette.secondary],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: palette.glow.withValues(alpha: .24),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(palette.motif, color: palette.onPrimary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                BarqIdentity.label(identity),
                                style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                palette.tagline,
                                style: TextStyle(color: palette.mutedText, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (selected == identity)
                          Icon(Icons.check_circle_rounded, color: palette.primary),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

}

String _messageTime(String raw) {
  if (raw.isEmpty) return '';
  final value = _messageSortTime(raw).toLocal();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _mimeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg': case 'jpeg': return 'image/jpeg';
    case 'png': return 'image/png';
    case 'gif': return 'image/gif';
    case 'webp': return 'image/webp';
    case 'mp4': return 'video/mp4';
    case 'mov': return 'video/quicktime';
    case 'mp3': return 'audio/mpeg';
    case 'm4a': return 'audio/mp4';
    case 'wav': return 'audio/wav';
    case 'pdf': return 'application/pdf';
    case 'zip': return 'application/zip';
    case 'doc': return 'application/msword';
    case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls': return 'application/vnd.ms-excel';
    case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt': return 'application/vnd.ms-powerpoint';
    case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'txt': return 'text/plain';
    default: return 'application/octet-stream';
  }
}

class BarqConversationTool {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const BarqConversationTool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

Future<void> showBarqConversationTools(
  BuildContext context,
  List<BarqConversationTool> tools,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.build_circle_outlined),
              const SizedBox(width: 9),
              const Expanded(child: Text('أدوات المحادثة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ]),
            const Divider(color: Colors.white24),
            for (final tool in tools)
              ListTile(
                leading: Icon(tool.icon),
                title: Text(tool.title),
                subtitle: Text(tool.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  tool.onTap();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showBarqMessageCollectionDialog(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> messages,
  required bool attachmentsOnly,
}) async {
  final selected = messages.where((message) {
    final attachment = _attachmentData(message);
    return attachmentsOnly ? attachment != null : message['is_pinned'] == true;
  }).toList().reversed.toList();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      insetPadding: const EdgeInsets.all(14),
      child: SizedBox(
        width: 480,
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('من الرسائل المحمّلة حاليًا',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: IconButton(
              tooltip: 'إغلاق',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          if (selected.isEmpty)
            Expanded(child: Center(
              child: Text(
                attachmentsOnly ? 'لا توجد مرفقات ضمن الرسائل المحمّلة.' : 'لا توجد رسائل مثبتة ضمن الرسائل المحمّلة.',
                style: const TextStyle(color: Colors.white60),
              ),
            ))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: selected.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                itemBuilder: (context, index) {
                  final message = selected[index];
                  final attachment = _attachmentData(message);
                  final preview = attachment != null
                      ? field(attachment, ['fileName'], 'مرفق')
                      : field(message, ['body', 'content', 'message'], 'رسالة');
                  return ListTile(
                    leading: Icon(
                      attachmentsOnly ? Icons.attach_file : Icons.push_pin_outlined,
                    ),
                    title: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(field(message, ['display_name', 'username'], 'مستخدم'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: Text(_messageTime(field(message, ['created_at', 'createdAt'])),
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  );
                },
              ),
            ),
        ]),
      ),
    ),
  );
}

class BarqConversationSummaryDialog extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() loadSummary;

  const BarqConversationSummaryDialog({super.key, required this.loadSummary});

  @override
  State<BarqConversationSummaryDialog> createState() => _BarqConversationSummaryDialogState();
}

class _BarqConversationSummaryDialogState extends State<BarqConversationSummaryDialog> {
  Future<Map<String, dynamic>>? _summaryFuture;

  void _startSummary() {
    final future = widget.loadSummary();
    setState(() {
      _summaryFuture = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 9),
                const Expanded(child: Text('ملخص المحادثة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'لإنشاء الملخص، سيُرسل نص آخر 60 رسالة إلى خدمة الذكاء الاصطناعي لدى Cloudflare. لا تُرسل المرفقات، ولا يُحفظ الملخص كرسالة في المحادثة.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Divider(height: 22, color: Colors.white24),
              if (_summaryFuture == null)
                Column(children: [
                  const Text('لن يبدأ إرسال الرسائل قبل ضغطك على «إنشاء الملخص».',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
                    onPressed: _startSummary,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('إنشاء الملخص'),
                  ),
                ])
              else
                FutureBuilder<Map<String, dynamic>>(
                  future: _summaryFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Column(children: [
                          CircularProgressIndicator(color: gold),
                          SizedBox(height: 12),
                          Text('جارٍ قراءة الرسائل وإنشاء الملخص...', style: TextStyle(color: Colors.white70)),
                        ]),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 34),
                        const SizedBox(height: 8),
                        Text(cleanError(snapshot.error!), textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _startSummary,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ]);
                    }
                    final data = snapshot.data ?? <String, dynamic>{};
                    final summary = field(data, ['summary']);
                    if (summary.isEmpty) {
                      return Column(children: [
                        const Text('لا توجد رسائل نصية كافية لإنشاء ملخص.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                        TextButton(onPressed: _startSummary, child: const Text('إعادة المحاولة')),
                      ]);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(summary, style: const TextStyle(color: Colors.white, height: 1.55)),
                        const SizedBox(height: 12),
                        Text('اعتمد الملخص على ${field(data, ['messageCount'], '0')} رسالة نصية حديثة.',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _startSummary,
                            icon: const Icon(Icons.refresh, size: 17),
                            label: const Text('تحديث الملخص'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BarqVoiceRecordButton extends StatefulWidget {
  final bool disabled;
  final Future<void> Function(List<int> bytes, Duration duration) onSend;

  const BarqVoiceRecordButton({
    super.key,
    required this.disabled,
    required this.onSend,
  });

  @override
  State<BarqVoiceRecordButton> createState() => _BarqVoiceRecordButtonState();
}

class _BarqVoiceRecordButtonState extends State<BarqVoiceRecordButton> {
  final AudioRecorder _recorder = AudioRecorder();
  Stopwatch? _stopwatch;
  Timer? _ticker;
  String? _recordingPath;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _busy = false;

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_recording) {
      await _finishRecording();
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await _recorder.hasPermission()) {
        throw Exception('يلزم السماح لبرق باستخدام الميكروفون لتسجيل الرسائل الصوتية.');
      }
      if (!await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
        throw Exception('تسجيل الصوت بهذا التنسيق غير مدعوم على هذا الجهاز.');
      }
      final path = '${Directory.systemTemp.path}${Platform.pathSeparator}barq_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 24000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      _recordingPath = path;
      _stopwatch = Stopwatch()..start();
      _elapsed = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _stopwatch != null) {
          setState(() => _elapsed = _stopwatch!.elapsed);
        }
      });
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishRecording() async {
    setState(() {
      _busy = true;
      _recording = false;
    });
    _ticker?.cancel();
    _ticker = null;
    final duration = _stopwatch?.elapsed ?? _elapsed;
    _stopwatch?.stop();
    String? completedPath;
    try {
      completedPath = await _recorder.stop() ?? _recordingPath;
      _recordingPath = null;
      if (completedPath == null || completedPath.isEmpty) {
        throw Exception('تعذر حفظ التسجيل الصوتي.');
      }
      final file = File(completedPath);
      if (!await file.exists()) throw Exception('ملف التسجيل الصوتي غير موجود.');
      final bytes = await file.readAsBytes();
      try { await file.delete(); } catch (_) {}
      if (bytes.isEmpty) throw Exception('التسجيل الصوتي فارغ.');
      if (bytes.length > maxAttachmentBytes) {
        throw Exception('حجم التسجيل تجاوز الحد المسموح.');
      }
      await widget.onSend(bytes, duration);
    } catch (error) {
      try { await _recorder.cancel(); } catch (_) {}
      final leftoverPath = completedPath ?? _recordingPath;
      _recordingPath = null;
      if (leftoverPath != null) {
        try {
          final leftover = File(leftoverPath);
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _elapsed = Duration.zero;
          _stopwatch = null;
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (_busy) return;
    setState(() => _busy = true);
    _ticker?.cancel();
    _ticker = null;
    _stopwatch?.stop();
    try {
      await _recorder.cancel();
      final path = _recordingPath;
      _recordingPath = null;
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
          _elapsed = Duration.zero;
          _stopwatch = null;
        });
      }
    }
  }

  Future<void> _disposeRecorder() async {
    if (_recording) {
      try { await _recorder.cancel(); } catch (_) {}
    }
    try { await _recorder.dispose(); } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_disposeRecorder());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recording)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(formatBarqMediaDuration(_elapsed),
              style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
          ),
        IconButton(
          tooltip: _recording ? 'إنهاء التسجيل وإرساله' : 'تسجيل رسالة صوتية',
          onPressed: _busy || (widget.disabled && !_recording) ? null : _toggleRecording,
          icon: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_recording ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                  color: _recording ? Colors.redAccent : gold),
        ),
        if (_recording)
          IconButton(
            tooltip: 'إلغاء التسجيل',
            onPressed: _busy ? null : _cancelRecording,
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
          ),
      ],
    );
  }
}

List<Uri> extractBarqLinks(String text) {
  final matches = RegExp(r'(?:https?://|www\.)[^\s<>()]+', caseSensitive: false).allMatches(text);
  final links = <Uri>[];
  for (final match in matches) {
    final raw = match.group(0) ?? '';
    final visible = raw.replaceFirst(RegExp(r'[.,!?;:،؛\]\}]+$'), '');
    final uri = Uri.tryParse(visible.startsWith('www.') ? 'https://$visible' : visible);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) continue;
    if (!links.any((existing) => existing == uri)) links.add(uri);
  }
  return links;
}

class BarqMessageBody extends StatefulWidget {
  final String text;
  const BarqMessageBody({super.key, required this.text});
  @override
  State<BarqMessageBody> createState() => _BarqMessageBodyState();
}

class _BarqMessageBodyState extends State<BarqMessageBody> {
  final List<TapGestureRecognizer> _recognizers = [];
  @override
  void dispose() {
    for (final recognizer in _recognizers) { recognizer.dispose(); }
    super.dispose();
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) showMsg(context, 'تعذر فتح الرابط على هذا الجهاز.');
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) { recognizer.dispose(); }
    _recognizers.clear();
    final matches = RegExp(r'(?:https?://|www\.)[^\s<>()]+', caseSensitive: false).allMatches(widget.text);
    final spans = <TextSpan>[];
    var cursor = 0;
    final links = extractBarqLinks(widget.text);
    for (final match in matches) {
      final raw = match.group(0) ?? '';
      final visible = raw.replaceFirst(RegExp(r'[.,!?;:،؛\]\}]+$'), '');
      if (visible.isEmpty) continue;
      final start = match.start;
      final end = start + visible.length;
      if (start > cursor) spans.add(TextSpan(text: widget.text.substring(cursor, start)));
      final uri = Uri.tryParse(visible.startsWith('www.') ? 'https://$visible' : visible);
      if (uri != null && {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty) {
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(uri);
        _recognizers.add(recognizer);
        spans.add(TextSpan(text: visible,
          style: const TextStyle(color: gold, decoration: TextDecoration.underline),
          recognizer: recognizer));
      } else {
        spans.add(TextSpan(text: visible));
      }
      cursor = end;
    }
    if (cursor < widget.text.length) spans.add(TextSpan(text: widget.text.substring(cursor)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(TextSpan(children: spans), style: DefaultTextStyle.of(context).style),
        for (final uri in links.take(2))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: Colors.black.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _openLink(uri),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: electricBlue.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9)),
                      child: const Icon(Icons.link, color: electricBlue)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(uri.host, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 3),
                      Text(uri.path.isEmpty ? uri.toString() : '${uri.path}${uri.hasQuery ? '?…' : ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text('فتح الرابط', style: TextStyle(color: Colors.white54, fontSize: 10)),
                    ])),
                    const Icon(Icons.open_in_new, color: Colors.white54, size: 17),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Map<String, dynamic>? _attachmentData(Map<String, dynamic> message) {
  final raw = field(message, ['body', 'content', 'message']);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> && decoded['type'] == 'attachment') {
      return decoded;
    }
  } catch (_) {}
  return null;
}

Widget _attachmentTile(
  Map<String, dynamic> attachment,
  VoidCallback onDownload,
) => _AttachmentTile(attachment: attachment, onDownload: onDownload);

class _AttachmentTile extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final VoidCallback onDownload;

  const _AttachmentTile({required this.attachment, required this.onDownload});

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  Future<Uint8List>? _previewFuture;
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration>? _audioDurationSubscription;
  StreamSubscription<void>? _audioCompleteSubscription;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  bool _audioLoading = false;
  bool _audioPlaying = false;
  String? _audioError;

  String get _contentType => field(widget.attachment, ['contentType']).toLowerCase();
  bool get _isImage => _contentType.startsWith('image/');
  bool get _isAudio => _contentType.startsWith('audio/');
  bool get _isVideo => _contentType.startsWith('video/');
  bool get _isPdf => _contentType == 'application/pdf' || field(widget.attachment, ['fileName']).toLowerCase().endsWith('.pdf');
  bool get _isText => _contentType.startsWith('text/') || RegExp(r'\.(txt|md|csv|log)$', caseSensitive: false).hasMatch(field(widget.attachment, ['fileName']));
  bool get _hasDocumentPreview => _isPdf || _isText;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  void _loadPreview() {
    if (_isImage || _hasDocumentPreview) {
      final id = field(widget.attachment, ['attachmentId']);
      if (id.isNotEmpty) _previewFuture = Api.fetchAttachmentBytes(id);
    }
  }

  void _openDocument(Uint8List bytes) {
    final name = field(widget.attachment, ['fileName'], 'مستند');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.78,
          child: Column(children: [
            ListTile(
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isPdf ? PdfViewer.data(bytes, sourceName: name) : SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: SelectableText(utf8.decode(bytes, allowMalformed: true),
                  style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _openImage(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.7,
                maxScale: 5,
                child: Center(
                  child: Image.memory(bytes, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 56)),
                ),
              ),
            ),
            Positioned(
              top: 4, right: 4,
              child: IconButton(
                tooltip: 'إغلاق المعاينة',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAudio() async {
    final id = field(widget.attachment, ['attachmentId']);
    if (id.isEmpty || _audioLoading) return;
    final player = _audioPlayer ??= AudioPlayer();
    if (_audioStateSubscription == null) {
      _audioStateSubscription = player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _audioPlaying = state == PlayerState.playing);
      });
      _audioPositionSubscription = player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _audioPosition = position);
      });
      _audioDurationSubscription = player.onDurationChanged.listen((duration) {
        if (mounted) setState(() => _audioDuration = duration);
      });
      _audioCompleteSubscription = player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _audioPlaying = false;
            _audioPosition = _audioDuration;
          });
        }
      });
    }
    try {
      if (_audioPlaying) {
        await player.pause();
        return;
      }
      if (_audioPosition > Duration.zero && _audioPosition < _audioDuration) {
        await player.resume();
        return;
      }
      setState(() {
        _audioLoading = true;
        _audioError = null;
      });
      final bytes = await Api.fetchAttachmentBytes(id);
      if (!mounted) return;
      await player.play(BytesSource(bytes));
    } catch (error) {
      if (mounted) setState(() => _audioError = cleanError(error));
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _seekAudio(double milliseconds) async {
    final player = _audioPlayer;
    if (player == null) return;
    await player.seek(Duration(milliseconds: milliseconds.round()));
  }

  void _openVideo() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VideoAttachmentDialog(attachment: widget.attachment),
    );
  }

  @override
  void dispose() {
    _audioStateSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    _audioCompleteSubscription?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = field(widget.attachment, ['fileName'], 'ملف مرفق');
    final icon = _isImage ? Icons.image_outlined
        : _isVideo ? Icons.video_file_outlined
        : _isAudio ? Icons.audio_file_outlined
        : _isPdf ? Icons.picture_as_pdf_outlined
        : _isText ? Icons.description_outlined
        : Icons.insert_drive_file_outlined;

    Widget leading;
    if ((_isImage || _hasDocumentPreview) && _previewFuture != null) {
      leading = FutureBuilder<Uint8List>(
        future: _previewFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            if (_isImage) {
              return GestureDetector(
                onTap: () => _openImage(snapshot.data!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(snapshot.data!, width: 76, height: 76, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 76, height: 76, child: Icon(Icons.broken_image_outlined))),
                ),
              );
            }
            return SizedBox(
              width: 76, height: 76,
              child: Material(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openDocument(snapshot.data!),
                  child: Icon(_isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined, size: 34),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return IconButton(tooltip: 'إعادة تحميل المعاينة',
              onPressed: () => setState(() => _loadPreview()),
              icon: const Icon(Icons.refresh));
          }
          return const SizedBox(width: 76, height: 76,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        },
      );
    } else if (_isAudio) {
      leading = IconButton(
        tooltip: _audioPlaying ? 'إيقاف مؤقت' : 'تشغيل التسجيل الصوتي',
        onPressed: _audioLoading ? null : _toggleAudio,
        icon: _audioLoading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(_audioPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34),
      );
    } else if (_isVideo) {
      leading = IconButton(
        tooltip: 'تشغيل الفيديو',
        onPressed: _openVideo,
        icon: const Icon(Icons.play_circle_fill, size: 34),
      );
    } else {
      leading = Icon(icon, size: 28);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            leading,
            const SizedBox(width: 9),
            Flexible(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
            )),
            IconButton(onPressed: widget.onDownload, icon: const Icon(Icons.download), tooltip: 'تنزيل الملف'),
          ]),
          if (_isAudio) ...[
            Row(children: [
              Text(formatBarqMediaDuration(_audioPosition),
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: (_audioDuration.inMilliseconds > 0 ? _audioDuration.inMilliseconds : 1).toDouble(),
                  value: _audioPosition.inMilliseconds.clamp(
                    0, _audioDuration.inMilliseconds > 0 ? _audioDuration.inMilliseconds : 1,
                  ).toDouble(),
                  onChanged: _audioDuration > Duration.zero ? _seekAudio : null,
                  activeColor: gold,
                  inactiveColor: Colors.white24,
                ),
              ),
              Text(formatBarqMediaDuration(_audioDuration),
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
            if (_audioError != null)
              Text(_audioError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

String formatBarqMediaDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final hours = totalSeconds ~/ 3600;
  if (hours > 0) {
    final remainingMinutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    return '$hours:$remainingMinutes:$seconds';
  }
  return '$minutes:$seconds';
}

class _VideoAttachmentDialog extends StatefulWidget {
  final Map<String, dynamic> attachment;
  const _VideoAttachmentDialog({required this.attachment});

  @override
  State<_VideoAttachmentDialog> createState() => _VideoAttachmentDialogState();
}

class _VideoAttachmentDialogState extends State<_VideoAttachmentDialog> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    final id = field(widget.attachment, ['attachmentId']);
    if (id.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'معرّف الفيديو غير متوفر.';
        });
      }
      return;
    }
    final headers = {if (Api.token != null) 'Authorization': 'Bearer \${Api.token}'};
    final bases = <String>[mediaWorkerBase, if (apiBase != mediaWorkerBase) apiBase];
    Object? lastError;
    for (final base in bases) {
      VideoPlayerController? candidate;
      try {
        candidate = VideoPlayerController.networkUrl(
          Uri.parse('$base/api/media/\${Uri.encodeComponent(id)}'),
          httpHeaders: headers,
        );
        await candidate.initialize().timeout(const Duration(minutes: 2));
        if (!mounted) {
          await candidate.dispose();
          return;
        }
        await candidate.setLooping(false);
        setState(() {
          _controller = candidate;
          _loading = false;
          _error = null;
        });
        return;
      } catch (error) {
        lastError = error;
        await candidate?.dispose();
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _error = cleanError(lastError ?? 'تعذر تشغيل الفيديو.');
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Expanded(child: Text('مشغّل الفيديو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: gold),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _initializeVideo();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ]),
              )
            else if (controller != null)
              AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    IconButton.filled(
                      onPressed: () async {
                        if (controller.value.isPlaying) {
                          await controller.pause();
                        } else {
                          await controller.play();
                        }
                        if (mounted) setState(() {});
                      },
                      iconSize: 36,
                      icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    Positioned(
                      left: 8, right: 8, bottom: 4,
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: gold,
                          bufferedColor: Colors.white54,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NearbyDevicesPage extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> friends;
  const NearbyDevicesPage({super.key, required this.user, required this.friends});

  @override
  State<NearbyDevicesPage> createState() => _NearbyDevicesPageState();
}

class _NearbyDevicesPageState extends State<NearbyDevicesPage> {
  List<Map<String, dynamic>> friends = [];
  final Map<String, String> discovered = {};
  String statusText = 'جارٍ تجهيز الاتصال بالأجهزة القريبة...';
  bool starting = true;
  StreamSubscription<Map<String, dynamic>>? subscription;

  @override
  void initState() {
    super.initState();
    subscription = BarqNearbyService.instance.events.listen(_onNearbyEvent);
    _start();
  }

  void _onNearbyEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'];
    if (type == 'endpoint_found') {
      setState(() => discovered[event['endpointId'].toString()] = event['userId'].toString());
    } else if (type == 'endpoint_lost') {
      setState(() => discovered.remove(event['endpointId'].toString()));
    } else if (type == 'connection_request') {
      _confirmConnection(event);
    } else if (type == 'connection_result') {
      setState(() => statusText = event['success'] == true ? 'تم الاتصال بالجهاز القريب.' : 'تعذر الاتصال: ${event['status']}');
    } else if (type == 'message_received') {
      setState(() => statusText = 'وصلت رسالة دون إنترنت من أحد أصدقائك.');
    } else if (type == 'message_receive_failed') {
      setState(() => statusText = 'تعذر حفظ الرسالة الواردة: ${event['reason'] ?? 'حدث خطأ غير معروف'}');
    } else if (type == 'payload_transfer_failed') {
      setState(() => statusText = 'تعذر نقل رسالة عبر الاتصال القريب؛ تأكد من بقاء الجهازين متصلين، وستبقى الرسالة الصادرة محفوظة للمزامنة عبر الإنترنت.');
    } else if (type == 'stopped') {
      setState(() => statusText = 'تم إيقاف البحث والاتصالات القريبة.');
    }
  }

  Future<void> _start() async {
    if (mounted) setState(() => starting = true);
    try {
      if (BarqNearbyService.instance.isRunning) {
        await BarqNearbyService.instance.stop();
      }
      friends = widget.friends;
      if (friends.isEmpty) {
        final raw = await storage.read(key: 'barq_cached_friends');
        final decoded = raw == null ? null : jsonDecode(raw);
        if (decoded is List) {
          friends = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        }
      }
      if (friends.isEmpty) throw Exception('افتح برق مرة واحدة مع الإنترنت لمزامنة جهات اتصالك قبل استخدام المراسلة القريبة.');
      await BarqNearbyService.instance.start(
        userId: field(widget.user, ['id', 'user_id']),
        displayName: field(widget.user, ['displayName', 'display_name', 'username'], 'مستخدم برق'),
        friends: friends,
      );
      if (mounted) setState(() => statusText = 'يبحث برق عن أصدقائك القريبين. أبقِ هذه الخدمة نشطة على الهاتفين.');
    } catch (e) {
      await BarqNearbyService.instance.stop();
      if (mounted) setState(() => statusText = cleanError(e));
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> _confirmConnection(Map<String, dynamic> event) async {
    final endpointId = event['endpointId']?.toString() ?? '';
    final name = event['name']?.toString() ?? 'جهاز قريب';
    final token = event['authenticationToken']?.toString() ?? '';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('تأكيد اتصال جهاز قريب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(name),
          const SizedBox(height: 12),
          const Text('قارن رمز الأمان مع الرمز الظاهر على الهاتف الآخر. لا توافق إذا اختلف الرمزان.'),
          const SizedBox(height: 12),
          SelectableText(token, style: const TextStyle(color: gold, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رفض')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
            onPressed: () => Navigator.pop(dialogContext, true), child: const Text('الرمز متطابق — قبول')),
        ],
      ),
    );
    if (!mounted || endpointId.isEmpty) return;
    try {
      if (accepted == true) {
        await BarqNearbyService.instance.acceptConnection(endpointId);
      } else {
        await BarqNearbyService.instance.rejectConnection(endpointId);
      }
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  String _friendName(String id) {
    for (final friend in friends) {
      final person = friend['user'] is Map ? Map<String, dynamic>.from(friend['user']) : friend;
      if (field(person, ['id', 'user_id']) == id) {
        return field(person, ['displayName', 'display_name', 'username'], 'صديق برق');
      }
    }
    return 'صديق برق';
  }

  @override
  void dispose() {
    subscription?.cancel();
    // لا نوقف النقل عند مغادرة الشاشة؛ قد يعود المستخدم إلى المحادثة لإرسال النص.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = BarqNearbyService.instance.connected;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الأجهزة القريبة')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(color: Theme.of(context).colorScheme.surface, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.wifi_tethering), SizedBox(width: 8), Text('مراسلة محلية دون إنترنت', style: TextStyle(fontWeight: FontWeight.bold))]),
            const SizedBox(height: 8),
            Text(statusText),
            const SizedBox(height: 8),
            const Text('يعتمد على Bluetooth وWi‑Fi القريب. لا يقرأ موقعك ولا يخزنه، لكن قد يطلب Android إذن الموقع وتشغيل خدمة الموقع لأجل اكتشاف الأجهزة. لا تُرسل ملفات أو صور عبر هذا الوضع.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: starting ? null : _start, icon: const Icon(Icons.refresh), label: const Text('إعادة البحث'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () async { await BarqNearbyService.instance.stop(); if (mounted) setState(() => discovered.clear()); }, icon: const Icon(Icons.stop_circle_outlined), label: const Text('إيقاف'))),
            ]),
          ]))),
          const SizedBox(height: 12),
          Text('الأجهزة المتصلة (${connected.length})', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          if (connected.isEmpty) const ListTile(title: Text('لا توجد أجهزة متصلة بعد.')),
          ...connected.map((entry) => ListTile(leading: const Icon(Icons.link), title: Text(_friendName(entry.value)), subtitle: const Text('متصل وجاهز للرسائل النصية'))),
          const SizedBox(height: 12),
          Text('الأصدقاء القريبون (${discovered.length})', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          if (discovered.isEmpty) const ListTile(title: Text('لا يظهر أصدقاؤك الآن. افتح الشاشة نفسها على هاتف صديقك وتأكد من تشغيل Bluetooth والموقع.'), dense: true),
          ...discovered.entries.map((entry) => Card(color: Theme.of(context).colorScheme.surface, child: ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(_friendName(entry.value)),
            subtitle: const Text('قريب — لم يتم الاتصال بعد'),
            trailing: IconButton(icon: const Icon(Icons.link), tooltip: 'طلب اتصال', onPressed: () async {
              try { await BarqNearbyService.instance.requestConnection(entry.key); }
              catch (e) {
                if (!context.mounted) return;
                showMsg(context, cleanError(e));
              }
            }),
          ))),
        ]),
      ),
    );
  }
}

class PublicProfilePage extends StatelessWidget {
  final Map<String, dynamic> person;
  final String currentUserId;
  final bool canMessage;

  const PublicProfilePage({
    super.key,
    required this.person,
    required this.currentUserId,
    this.canMessage = false,
  });

  Map<String, dynamic> get profile => person['user'] is Map
      ? Map<String, dynamic>.from(person['user'])
      : person;

  Future<void> _savePhoneToContacts(BuildContext context, String name, String phone) async {
    try {
      final permitted = await FlutterContacts.requestPermission();
      if (!permitted) {
        if (context.mounted) showMsg(context, 'يلزم السماح بالوصول إلى جهات الاتصال لحفظ الرقم.');
        return;
      }
      final existing = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
      final target = normalizeBarqContactPhoneDigits(phone);
      final alreadySaved = target.isNotEmpty && existing.any((contact) =>
          contact.phones.any((entry) =>
              normalizeBarqContactPhoneDigits(entry.number) == target));
      if (alreadySaved) {
        if (context.mounted) showMsg(context, 'هذا الرقم محفوظ بالفعل في جهات الاتصال.');
        return;
      }
      await FlutterContacts.insertContact(Contact(
        displayName: name,
        phones: [Phone(phone)],
      ));
      if (context.mounted) showMsg(context, 'تم حفظ الرقم في جهات الاتصال.');
    } catch (error) {
      if (context.mounted) showMsg(context, cleanError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = profile;
    final id = field(user, ['id', 'user_id', 'friend_id', 'sender_id']).trim();
    final canOpenChat = id.isNotEmpty && id != currentUserId.trim();
    final name = field(user, ['displayName', 'display_name', 'name', 'username'], 'مستخدم برق');
    final username = field(user, ['username'], 'user');
    final phone = field(user, ['phone']);
    final photoUrl = profilePhotoPath(user);
    final photoUpdatedAt = field(user, ['photoUpdatedAt', 'photo_updated_at']);
    final imageUrl = photoUrl.isEmpty
        ? ''
        : '$apiBase$photoUrl?v=${Uri.encodeComponent(photoUpdatedAt)}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الملف الشخصي')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 132,
                height: 132,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: electricBlue.withValues(alpha: 0.75), width: 2),
                  boxShadow: [
                    BoxShadow(color: electricBlue.withValues(alpha: 0.18), blurRadius: 24),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFF46391F),
                  child: imageUrl.isEmpty
                      ? Text(name.characters.first, style: const TextStyle(color: gold, fontSize: 48))
                      : ClipOval(
                          child: Image.network(
                            imageUrl,
                            width: 124,
                            height: 124,
                            fit: BoxFit.cover,
                            headers: {'Authorization': 'Bearer ${Api.token}'},
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(name.characters.first,
                                  style: const TextStyle(color: gold, fontSize: 48)),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(name, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text('@$username', textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16)),
            const SizedBox(height: 26),
            Card(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('اسم المستخدم'),
                    subtitle: Text('@$username'),
                  ),
                  if (phone.isNotEmpty) const Divider(height: 1, indent: 16, endIndent: 16),
                  if (phone.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: const Text('رقم الهاتف'),
                      subtitle: Text(phone, textDirection: TextDirection.ltr),
                    ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  const ListTile(
                    leading: Icon(Icons.flash_on_rounded),
                    title: Text('على برق'),
                    subtitle: Text('التواصل بنبض الضوء'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (phone.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _savePhoneToContacts(context, name, phone),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('حفظ الرقم في جهات الاتصال'),
              ),
            if (canMessage)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: electricBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: canOpenChat
                    ? () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(friend: person, currentUserId: currentUserId),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('إرسال رسالة'),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final Map<String, dynamic> friend;
  final String currentUserId;
  const ChatPage({super.key, required this.friend, required this.currentUserId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final Map<String, String> translatedMessages = {};
  final Set<String> translatingMessageIds = {};
  final Map<String, DateTime> translationRetryAfter = {};
  final Map<String, String> voiceTranscripts = {};
  final Set<String> transcribingMessageIds = {};
  bool loading = true;
  bool sending = false;
  bool refreshing = false;
  bool ephemeralMode = false;
  bool hasOlderMessages = false;
  bool loadingOlderMessages = false;
  Map<String, dynamic>? olderMessageCursor;
  Map<String, dynamic>? replyToMessage;
  Timer? refreshTimer;
  Timer? _ephemeralExpiryTimer;
  StreamSubscription<Map<String, dynamic>>? realtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? nearbySubscription;

  Map<String, dynamic> get person =>
      widget.friend['user'] is Map
          ? Map<String, dynamic>.from(widget.friend['user'])
          : widget.friend;

  String get friendId => field(person, ['id', 'user_id', 'friend_id']);

  @override
  void initState() {
    super.initState();
    loadMessages();
    nearbySubscription = BarqNearbyService.instance.events.listen((event) {
      if (event['type'] == 'message_received' && event['senderId'] == friendId) {
        loadMessages(silent: true);
      }
    });
    realtimeSubscription = SirajRealtime.instance.events.listen((event) {
      if (event['type'] != 'message') return;
      final sender = event['senderId']?.toString();
      final receiver = event['receiverId']?.toString();
      if (sender == friendId || receiver == friendId) {
        loadMessages(silent: true);
      }
    });
    // مزامنة الرسائل عبر REST/Vercel كل 5 ثوانٍ دون الاعتماد على workers.dev.
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !sending && !refreshing) loadMessages(silent: true);
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    _ephemeralExpiryTimer?.cancel();
    realtimeSubscription?.cancel();
    nearbySubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _scheduleEphemeralExpiry() {
    _ephemeralExpiryTimer?.cancel();
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final deadlines = messages
        .map(_ephemeralDeleteAt)
        .where((value) => value != null)
        .map((value) => value! * 1000)
        .where((deadline) => deadline > nowMillis)
        .toList();
    if (deadlines.isEmpty) return;
    deadlines.sort();
    _ephemeralExpiryTimer = Timer(
      Duration(milliseconds: deadlines.first - nowMillis),
      () {
        if (!mounted) return;
        final visible = filterExpiredEphemeralMessages(messages);
        if (visible.length != messages.length) {
          setState(() => messages = visible);
        }
        _scheduleEphemeralExpiry();
      },
    );
  }

  Future<void> _transcribeVoiceMessage(
    Map<String, dynamic> message,
    Map<String, dynamic> attachment,
  ) async {
    final id = field(message, ['id', 'message_id']);
    if (id.isEmpty || transcribingMessageIds.contains(id) || voiceTranscripts.containsKey(id)) return;
    if (!await confirmVoiceTranscription(context) || !mounted) return;
    setState(() => transcribingMessageIds.add(id));
    try {
      final transcript = await Api.transcribeAttachment(
        field(attachment, ['attachmentId']),
        expectedContentType: field(attachment, ['contentType']),
      );
      if (mounted) setState(() => voiceTranscripts[id] = transcript);
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => transcribingMessageIds.remove(id));
    }
  }

  Future<void> _translateMessages(List<Map<String, dynamic>> items) async {
    if (!BarqFeatures.autoTranslate) return;
    for (final message in items) {
      final id = field(message, ['id', 'message_id']);
      final senderId = field(message, ['sender_id', 'senderId']);
      final original = field(message, ['body', 'content', 'message']);
      if (id.isEmpty || senderId == widget.currentUserId || original.isEmpty ||
          _attachmentData(message) != null || translatedMessages.containsKey(id) ||
          translatingMessageIds.contains(id) ||
          !barqTranslationRetryAllowed(id, translationRetryAfter)) {
        continue;
      }
      translatingMessageIds.add(id);
      try {
        final translated = await BarqTranslator.translateArabicEnglish(original);
        if (mounted && translated.isNotEmpty) {
          setState(() {
            translatedMessages[id] = translated;
            translationRetryAfter.remove(id);
          });
        } else {
          translationRetryAfter[id] = DateTime.now().add(const Duration(minutes: 1));
        }
      } catch (_) {
        translationRetryAfter[id] = DateTime.now().add(const Duration(minutes: 1));
        // تبقى الرسالة الأصلية ظاهرة، وتُعاد المحاولة بعد دقيقة إذا توفر النموذج المحلي.
      } finally {
        translatingMessageIds.remove(id);
      }
    }
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    try {
      await BarqOfflineQueue.syncOutbox();
      final page = await Api.messagesPage(friendId);
      final data = Api._list(page['messages']);
      await BarqOfflineQueue.reconcile(data);
      final localPending = await BarqOfflineQueue.conversation(friendId, widget.currentUserId);
      List<Map<String, dynamic>> temporary = [];
      try {
        temporary = await Api.ephemeralMessages(friendId);
      } catch (_) {
        // النسخ القديمة من الخادم لا تملك مسار الرسائل المؤقتة بعد.
      }
      if (mounted) {
        setState(() {
        final existingRegular = messages.where((item) => item['is_ephemeral'] != true).toList();
        final regular = silent && existingRegular.isNotEmpty
            ? mergeMessages(existingRegular, data) : data;
        messages = filterExpiredEphemeralMessages(
          mergeMessages(mergeMessages(regular, temporary), localPending),
        );
        if (!silent || olderMessageCursor == null) {
          olderMessageCursor = page['nextCursor'] is Map
              ? Map<String, dynamic>.from(page['nextCursor']) : null;
        }
        hasOlderMessages = page['hasMore'] == true || (silent && hasOlderMessages);
        loading = false;
      });
        _scheduleEphemeralExpiry();
        if (BarqFeatures.autoTranslate) _translateMessages(data);
      }
    } catch (e) {
      if (mounted) {
        final stillVisible = filterExpiredEphemeralMessages(messages);
        final localPending = await BarqOfflineQueue.conversation(friendId, widget.currentUserId);
        setState(() {
          messages = mergeMessages(stillVisible, localPending);
          loading = false;
        });
        _scheduleEphemeralExpiry();
        if (!silent && localPending.isEmpty && mounted) showMsg(context, cleanError(e));
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> loadOlderMessages() async {
    if (loadingOlderMessages || !hasOlderMessages || olderMessageCursor == null) return;
    setState(() => loadingOlderMessages = true);
    try {
      final page = await Api.messagesPage(friendId, before: olderMessageCursor);
      final older = Api._list(page['messages']);
      // Older pages can contain messages already received over Nearby. Reconcile
      // them too, or those inbox entries remain in secure storage indefinitely.
      await BarqOfflineQueue.reconcile(older);
      if (mounted) {
        setState(() {
        messages = mergeMessages(older, messages);
        olderMessageCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor']) : null;
        hasOlderMessages = page['hasMore'] == true;
      });
      }
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => loadingOlderMessages = false);
    }
  }

  Future<void> send() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    if (!isBarqMessageTextAllowed(text)) {
      showMsg(context, 'الرسالة طويلة جدًا؛ الحد الأقصى 5000 حرف.');
      return;
    }
    setState(() => sending = true);
    try {
      if (ephemeralMode) {
        if (replyToMessage != null) throw Exception('الرسائل المؤقتة لا تدعم الرد على رسالة أخرى. ألغِ الرد أولاً.');
        await Api.sendEphemeralMessage(friendId, text);
      } else {
        final messageId = newBarqMessageId();
        try {
          await Api.sendMessage(friendId, text, clientMessageId: messageId,
            replyToId: replyToMessage == null ? null : field(replyToMessage!, ['id', 'message_id']));
        } catch (e) {
          if (!e.toString().contains('NETWORK_DIAGNOSTIC')) rethrow;
          final localMessage = {
            'id': messageId,
            'sender_id': widget.currentUserId,
            'receiver_id': friendId,
            'body': text,
            if (replyToMessage != null) 'reply_to_id': field(replyToMessage!, ['id', 'message_id']),
            if (replyToMessage != null) 'reply_to_body': field(replyToMessage!, ['body', 'content', 'message']),
            if (replyToMessage != null) 'reply_to_sender_id': field(replyToMessage!, ['sender_id']),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          };
          await BarqOfflineQueue.enqueueOutgoing(localMessage);
          var deliveredNearby = false;
          try {
            if (replyToMessage == null) {
              deliveredNearby = await BarqNearbyService.instance.sendTextMessage(
                receiverId: friendId, messageId: messageId, body: text, senderId: widget.currentUserId,
              );
            }
          } catch (_) {}
          if (mounted) {
            setState(() => messages = mergeMessages(messages, [{...localMessage, 'is_offline_pending': true}]));
            showMsg(context, deliveredNearby
                ? 'أُرسلت الرسالة عبر الاتصال القريب، وستُزامن مع الخادم عند عودة الإنترنت.'
                : replyToMessage != null
                    ? 'تم حفظ الرد محليًا وسيُرسل مع الاقتباس عند عودة الإنترنت.'
                    : 'حُفظت الرسالة محليًا. افتح الأجهزة القريبة لتسليمها الآن، وستُزامن تلقائيًا عند عودة الإنترنت.');
          }
          controller.clear();
          if (mounted) setState(() => replyToMessage = null);
          return;
        }
      }
      controller.clear();
      if (mounted) setState(() => replyToMessage = null);
      await loadMessages();
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendVoiceRecording(List<int> bytes, Duration duration) async {
    if (BarqFeatures.lightningMode || sending) return;
    setState(() => sending = true);
    try {
      await Api.uploadAttachment(
        bytes: bytes,
        fileName: 'barq_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
        recipientId: friendId,
      );
      await loadMessages();
      if (mounted) showMsg(context, 'تم إرسال التسجيل الصوتي (${formatBarqMediaDuration(duration)}).');
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickAndSendFile() async {
    if (BarqFeatures.lightningMode) {
      showMsg(context, 'وضع البرق مفعّل: إرسال الوسائط والملفات متوقف مؤقتًا.');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('تعذر قراءة الملف من الجهاز.');
      setState(() => sending = true);
      await Api.uploadAttachment(
        bytes: bytes,
        fileName: file.name,
        contentType: file.extension == null ? 'application/octet-stream' : _mimeForExtension(file.extension!),
        recipientId: friendId,
      );
      await loadMessages();
      if (mounted) showMsg(context, 'تم إرسال الملف.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = field(person, ['displayName', 'display_name', 'name', 'username'], 'محادثة');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PublicProfilePage(person: widget.friend, currentUserId: widget.currentUserId, canMessage: true),
            )),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              personAvatar(widget.friend, radius: 17),
              const SizedBox(width: 9),
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
              if (BarqFeatures.lightningMode) ...[
                const SizedBox(width: 6),
                const Icon(Icons.flash_on_rounded, size: 18),
              ],
            ]),
          ),
          actions: [
            IconButton(
              onPressed: () => showBarqConversationTools(context, [
                BarqConversationTool(
                  icon: Icons.search,
                  title: 'البحث في المحادثة',
                  subtitle: 'ابحث داخل الرسائل المحمّلة',
                  onTap: () => showConversationSearch(context, (query, before) => Api.searchPrivateMessages(friendId, query, before: before)),
                ),
                BarqConversationTool(
                  icon: Icons.auto_awesome_outlined,
                  title: 'ملخص المحادثة',
                  subtitle: 'إنشاء ملخص ذكي بعد موافقتك',
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => BarqConversationSummaryDialog(
                      loadSummary: () => Api.summarizePrivateConversation(friendId),
                    ),
                  ),
                ),
                BarqConversationTool(
                  icon: Icons.push_pin_outlined,
                  title: 'الرسائل المثبتة (${messages.where((message) => message['is_pinned'] == true).length})',
                  subtitle: 'عرض المثبتة ضمن الرسائل المحمّلة',
                  onTap: () => showBarqMessageCollectionDialog(context,
                    title: 'الرسائل المثبتة', messages: messages, attachmentsOnly: false),
                ),
                BarqConversationTool(
                  icon: Icons.perm_media_outlined,
                  title: 'الوسائط والملفات (${messages.where((message) => _attachmentData(message) != null).length})',
                  subtitle: 'عرض المرفقات ضمن الرسائل المحمّلة',
                  onTap: () => showBarqMessageCollectionDialog(context,
                    title: 'الوسائط والملفات', messages: messages, attachmentsOnly: true),
                ),
              ]),
              icon: const Icon(Icons.build_circle_outlined),
              tooltip: 'أدوات المحادثة',
            ),
            IconButton(onPressed: loadMessages, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: gold))
                  : messages.isEmpty
                      ? const Center(child: Text('لا توجد رسائل بعد. ابدأ المحادثة.', style: TextStyle(color: Colors.white60)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: messages.length + (hasOlderMessages ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (hasOlderMessages && index == 0) {
                              return Center(child: TextButton.icon(
                                onPressed: loadingOlderMessages ? null : loadOlderMessages,
                                icon: loadingOlderMessages
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.history),
                                label: const Text('تحميل الرسائل الأقدم'),
                              ));
                            }
                            final m = messages[index - (hasOlderMessages ? 1 : 0)];
                            final sender = field(m, ['sender_id']);
                            final mine = sender == widget.currentUserId;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 300),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: mine ? Theme.of(context).colorScheme.primary.withValues(alpha: .18) : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (m['is_offline_pending'] == true)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 5),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.wifi_off_rounded, size: 12, color: Colors.white54),
                                          SizedBox(width: 4),
                                          Text('رسالة دون إنترنت — بانتظار المزامنة', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                        ]),
                                      ),
                                    if (m['is_ephemeral'] == true)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 5),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.timer_outlined, size: 13),
                                          SizedBox(width: 4),
                                          Text('رسالة مؤقتة', style: TextStyle(color: gold, fontSize: 10)),
                                        ]),
                                      ),
                                    if (field(m, ['reply_to_id']).isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(bottom: 7),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8),
                                          border: const Border(right: BorderSide(color: gold, width: 3))),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(field(m, ['reply_to_sender_id']) == widget.currentUserId ? 'رد على رسالتك' : 'رد على رسالة',
                                            style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.bold)),
                                          Text(messageReplyPreview(m), maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                        ]),
                                      ),
                                    if (_attachmentData(m) case final attachment?) ...[
                                      _attachmentTile(attachment, () async {
                                        try {
                                          await Api.downloadAttachment(
                                            attachmentId: field(attachment, ['attachmentId']),
                                            fileName: field(attachment, ['fileName'], 'attachment'),
                                          );
                                        } catch (e) { if (context.mounted) showMsg(context, cleanError(e)); }
                                      }),
                                      if (field(attachment, ['contentType']).startsWith('audio/'))
                                        TextButton.icon(
                                          onPressed: transcribingMessageIds.contains(field(m, ['id', 'message_id']))
                                              ? null : () => _transcribeVoiceMessage(m, attachment),
                                          icon: transcribingMessageIds.contains(field(m, ['id', 'message_id']))
                                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.subtitles_outlined, size: 16),
                                          label: const Text('تحويل الصوت إلى نص'),
                                        ),
                                      if (voiceTranscripts[field(m, ['id', 'message_id'])] != null)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                                          child: Text(voiceTranscripts[field(m, ['id', 'message_id'])]!),
                                        ),
                                    ] else ...[
                                      GestureDetector(
                                        onLongPress: () => showMessageActions(
                                          context,
                                          message: m,
                                          canDelete: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                          onDelete: () async {
                                            await Api.deletePrivateMessage(field(m, ['id', 'message_id']));
                                            if (mounted) await loadMessages();
                                          },
                                          onReply: (message) async {
                                            setState(() => replyToMessage = Map<String, dynamic>.from(message));
                                          },
                                          onEdit: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true && _attachmentData(m) == null
                                              ? (body) async {
                                                  await Api.editPrivateMessage(field(m, ['id', 'message_id']), body);
                                                  if (mounted) await loadMessages();
                                                }
                                              : null,
                                          onReact: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                              ? (emoji) async {
                                                  await Api.reactPrivateMessage(field(m, ['id', 'message_id']), emoji);
                                                  if (mounted) await loadMessages(silent: true);
                                                }
                                              : null,
                                          onPin: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                              ? () async {
                                                  await Api.pinPrivateMessage(field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
                                                  if (mounted) await loadMessages(silent: true);
                                                }
                                              : null,
                                          onSaveMemory: m['is_ephemeral'] != true && m['is_offline_pending'] != true &&
                                                  field(m, ['body', 'content', 'message']).trim().isNotEmpty
                                              ? () async {
                                                  await Api.savePrivateMemory(
                                                    title: 'رسالة محفوظة',
                                                    content: field(m, ['body', 'content', 'message']),
                                                    sourceType: 'message',
                                                  );
                                                  if (context.mounted) showMsg(context, 'تم حفظ الرسالة في ذكرياتك الخاصة.');
                                                }
                                              : null,
                                          isPinned: m['is_pinned'] == true,
                                        ),
                                        child: BarqMessageBody(text: field(m, ['body', 'content', 'message'])),
                                      ),
                                      if (BarqFeatures.autoTranslate && translatedMessages[field(m, ['id', 'message_id'])] != null) ...[
                                        const SizedBox(height: 6),
                                        const Divider(height: 1, color: Colors.white24),
                                        const SizedBox(height: 6),
                                        Text(translatedMessages[field(m, ['id', 'message_id'])]!,
                                          style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                                      ],
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_messageTime(field(m, ['created_at', 'createdAt'])),
                                          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55))),
                                        if (field(m, ['edited_at', 'editedAt']).isNotEmpty)
                                          const Text('تم التعديل', style: TextStyle(fontSize: 9, color: Colors.white54)),
                                        if (mine) ...[
                                          const SizedBox(width: 4),
                                          Icon(field(m, ['read_at', 'readAt']).isNotEmpty ? Icons.done_all : Icons.done,
                                            size: 13, color: field(m, ['read_at', 'readAt']).isNotEmpty ? Colors.lightBlueAccent : Colors.white54),
                                        ],
                                      ],
                                    ),
                                    if (m['is_pinned'] == true)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.push_pin, size: 12),
                                          SizedBox(width: 3),
                                          Text('مثبتة', style: TextStyle(color: gold, fontSize: 10)),
                                        ]),
                                      ),
                                    if (m['is_ephemeral'] != true && m['is_offline_pending'] != true)
                                      messageReactionBar(
                                        context: context,
                                        message: m,
                                        currentUserId: widget.currentUserId,
                                        onReaction: (emoji, remove) async {
                                          await Api.reactPrivateMessage(field(m, ['id', 'message_id']), emoji, remove: remove);
                                          if (mounted) await loadMessages(silent: true);
                                        },
                                        isPinned: m['is_pinned'] == true,
                                        onPin: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                            ? () async {
                                                await Api.pinPrivateMessage(field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
                                                if (mounted) await loadMessages(silent: true);
                                              }
                                            : null,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: sending ? null : () => setState(() { ephemeralMode = !ephemeralMode; replyToMessage = null; }),
                      icon: Icon(Icons.timer_outlined, color: ephemeralMode ? gold : Colors.white54),
                      tooltip: ephemeralMode ? 'إيقاف الرسائل المؤقتة' : 'إرسال رسالة تختفي بعد قراءتها',
                    ),
                    if (!BarqFeatures.lightningMode)
                      IconButton(
                        onPressed: sending ? null : pickAndSendFile,
                        icon: const Icon(Icons.attach_file),
                        tooltip: 'إرسال ملف أو صورة أو فيديو',
                      ),
                    if (!BarqFeatures.lightningMode && !ephemeralMode)
                      BarqVoiceRecordButton(disabled: sending, onSend: _sendVoiceRecording),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: inputDecoration(
                          ephemeralMode ? 'رسالة مؤقتة — تختفي بعد القراءة' : 'اكتب رسالتك...',
                          ephemeralMode ? Icons.timer_outlined : Icons.message,
                        ).copyWith(
                          helperText: replyToMessage == null ? null : 'الرد على: ${messageReplyPreview(replyToMessage!)}',
                          helperStyle: const TextStyle(color: gold, fontSize: 10),
                        ),
                        onSubmitted: (_) => send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (replyToMessage != null)
                      IconButton(onPressed: sending ? null : () => setState(() => replyToMessage = null),
                        icon: const Icon(Icons.close, color: Colors.white70), tooltip: 'إلغاء الرد'),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
                      onPressed: sending ? null : send,
                      icon: sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}


class SparkMediaViewer extends StatefulWidget {
  final String statusId;
  final List<Map<String, dynamic>> media;
  final String author;
  final String caption;
  final String backgroundKey;
  final String textColorKey;
  final String fontKey;
  const SparkMediaViewer({
    super.key, required this.statusId, required this.media, required this.author, required this.caption,
    this.backgroundKey = 'midnight', this.textColorKey = 'white', this.fontKey = 'modern',
  });

  @override
  State<SparkMediaViewer> createState() => _SparkMediaViewerState();
}

class _SparkMediaViewerState extends State<SparkMediaViewer> {
  final TextEditingController _replyController = TextEditingController();
  List<Map<String, dynamic>> _replies = [];
  bool _loadingReplies = true;
  bool _sendingReply = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _audioRecordingTimer;
  Stopwatch? _audioRecordingWatch;
  bool _recordingAudioReply = false;
  bool _uploadingAudioReply = false;
  int _recordingSeconds = 0;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  Future<void> _loadReplies() async {
    try {
      final replies = await Api.sparkReplies(widget.statusId);
      if (mounted) setState(() { _replies = replies; _loadingReplies = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingReplies = false);
    }
  }

  Future<void> _react(String emoji) async {
    try {
      await Api.reactSparkStatus(widget.statusId, emoji);
      if (mounted) showMsg(context, 'تم إرسال تفاعلك.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  Future<void> _sendReply() async {
    final value = _replyController.text.trim();
    if (value.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    try {
      await Api.replyToSpark(widget.statusId, value);
      _replyController.clear();
      await _loadReplies();
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _toggleAudioReplyRecording() async {
    if (_uploadingAudioReply) return;
    if (_recordingAudioReply) {
      await _finishAudioReplyRecording();
      return;
    }
    if (BarqFeatures.lightningMode) {
      showMsg(context, 'وضع البرق مفعّل: الردود الصوتية متوقفة.');
      return;
    }
    try {
      final allowed = await _audioRecorder.hasPermission();
      if (!allowed) {
        if (mounted) showMsg(context, 'اسمح لبرق باستخدام الميكروفون لإرسال رد صوتي.');
        return;
      }
      final path = '${Directory.systemTemp.path}/barq_spark_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      _recordingPath = path;
      _audioRecordingWatch = Stopwatch()..start();
      if (mounted) setState(() { _recordingAudioReply = true; _recordingSeconds = 0; });
      _audioRecordingTimer?.cancel();
      _audioRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final seconds = _audioRecordingWatch?.elapsed.inSeconds ?? 0;
        if (mounted) setState(() => _recordingSeconds = seconds.clamp(0, 60).toInt());
        if (seconds >= 60) _finishAudioReplyRecording();
      });
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    }
  }

  String _recordingClock(int seconds) {
    final safeSeconds = seconds.clamp(0, 60).toInt();
    return '${(safeSeconds ~/ 60).toString().padLeft(2, '0')}:${(safeSeconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _finishAudioReplyRecording() async {
    if (!_recordingAudioReply || _uploadingAudioReply) return;
    _audioRecordingTimer?.cancel();
    _audioRecordingTimer = null;
    _audioRecordingWatch?.stop();
    final durationMs = (_audioRecordingWatch?.elapsedMilliseconds ?? 0).clamp(0, 60000).toInt();
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    }
    if (mounted) setState(() { _recordingAudioReply = false; _uploadingAudioReply = true; });
    try {
      if (path == null || path.isEmpty) throw Exception('تعذر حفظ التسجيل الصوتي.');
      if (durationMs < 1000) throw Exception('سجّل ثانية واحدة على الأقل.');
      final file = File(path);
      final bytes = await file.readAsBytes();
      await Api.uploadSparkAudioReply(statusId: widget.statusId, bytes: bytes, durationMs: durationMs);
      await _loadReplies();
      if (mounted) showMsg(context, 'تم إرسال الرد الصوتي.');
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      final filePath = path ?? _recordingPath;
      if (filePath != null) {
        try { await File(filePath).delete(); } catch (_) {}
      }
      _recordingPath = null;
      _audioRecordingWatch = null;
      if (mounted) setState(() { _uploadingAudioReply = false; _recordingSeconds = 0; });
    }
  }

  @override
  void dispose() {
    _audioRecordingTimer?.cancel();
    if (_recordingAudioReply) _audioRecorder.stop();
    _audioRecorder.dispose();
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final headers = <String, String>{if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'};
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.author), foregroundColor: Colors.white),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: widget.media.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    color: const <String, Color>{
                      'electric_blue': Color(0xFF0757D5),
                      'violet': Color(0xFF43206F),
                      'gold': Color(0xFFB98B2F),
                      'midnight': Color(0xFF101827),
                    }[widget.backgroundKey] ?? const Color(0xFF101827),
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      child: Text(
                        widget.caption,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const <String, Color>{
                            'white': Colors.white, 'black': Colors.black, 'gold': Color(0xFFFFD166),
                          }[widget.textColorKey] ?? Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          fontFamily: switch (widget.fontKey) {
                            'classic' => 'serif',
                            'mono' => 'monospace',
                            _ => null,
                          },
                        ),
                      ),
                    ),
                  )
                : PageView.builder(
                    itemCount: widget.media.length,
                    itemBuilder: (context, index) {
                      final item = widget.media[index];
                      final attachmentId = (item['attachmentId'] ?? '').toString();
                      final contentType = (item['contentType'] ?? '').toString();
                      if (attachmentId.isEmpty) return const Center(child: Text('الوسائط غير متاحة', style: TextStyle(color: Colors.white)));
                      final uri = Api.sparkMediaUri(attachmentId);
                      return Stack(fit: StackFit.expand, children: [
                        if (contentType.startsWith('video/'))
                          _SparkVideoPage(uri: uri, headers: headers)
                        else
                          Center(child: InteractiveViewer(
                            minScale: 0.8, maxScale: 4,
                            child: Image.network(
                              uri.toString(), headers: headers, fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 52),
                              loadingBuilder: (context, child, progress) => progress == null
                                  ? child
                                  : const Center(child: CircularProgressIndicator(color: gold)),
                            ),
                          )),
                        if (widget.caption.trim().isNotEmpty)
                          Positioned(left: 16, right: 16, bottom: 16, child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.caption, style: const TextStyle(color: Colors.white, fontSize: 16))),
                          )),
                      ]);
                    },
                  ),
          ),
          Container(
            width: double.infinity, padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(color: Color(0xFF151515), border: Border(top: BorderSide(color: Colors.white12))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final emoji in ['❤️', '🔥', '😂', '👍'])
                  TextButton(onPressed: () => _react(emoji), child: Text(emoji, style: const TextStyle(fontSize: 24))),
              ]),
              SizedBox(
                height: 84,
                child: _loadingReplies
                    ? const Center(child: CircularProgressIndicator(color: gold))
                    : _replies.isEmpty
                        ? const Center(child: Text('لا توجد ردود بعد', style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            itemCount: _replies.length,
                            itemBuilder: (context, index) {
                              final reply = _replies[index];
                              final author = (reply['displayName'] ?? reply['username'] ?? 'مستخدم').toString();
                              if (reply['kind'] == 'audio') {
                                return _SparkAudioReplyTile(statusId: widget.statusId, reply: reply, author: author);
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Text(
                                  '$author: ${reply['body'] ?? ''}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              );
                            },
                          ),
              ),
              if (_recordingAudioReply)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('جارٍ التسجيل ${_recordingClock(_recordingSeconds)} / 01:00',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              Row(children: [
                Expanded(child: TextField(
                  controller: _replyController, maxLength: 1000,
                  decoration: const InputDecoration(
                    hintText: 'اكتب ردًا...', counterText: '',
                    hintStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _sendReply(),
                )),
                IconButton(
                  tooltip: _recordingAudioReply ? 'إيقاف وإرسال الرد الصوتي' : 'تسجيل رد صوتي',
                  onPressed: _uploadingAudioReply ? null : _toggleAudioReplyRecording,
                  icon: _uploadingAudioReply
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_recordingAudioReply ? Icons.stop_circle_rounded : Icons.mic_rounded,
                          color: _recordingAudioReply ? Colors.redAccent : gold),
                ),
                IconButton(
                  onPressed: _sendingReply ? null : _sendReply,
                  icon: _sendingReply
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SparkAudioReplyTile extends StatefulWidget {
  final String statusId;
  final Map<String, dynamic> reply;
  final String author;
  const _SparkAudioReplyTile({required this.statusId, required this.reply, required this.author});

  @override
  State<_SparkAudioReplyTile> createState() => _SparkAudioReplyTileState();
}

class _SparkAudioReplyTileState extends State<_SparkAudioReplyTile> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _positionSubscription = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSubscription = _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_position > Duration.zero && _position < _duration) {
        await _player.resume();
        return;
      }
      setState(() => _loading = true);
      final id = (widget.reply['id'] ?? '').toString();
      final bytes = await Api.fetchSparkAudioReplyBytes(widget.statusId, id);
      await _player.play(BytesSource(bytes));
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _clock(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final declaredMs = int.tryParse((widget.reply['durationMs'] ?? 0).toString()) ?? 0;
    final total = _duration > Duration.zero ? _duration : Duration(milliseconds: declaredMs);
    final maximum = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
    final current = _position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _toggle,
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.author, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Slider(
            value: current, min: 0, max: maximum,
            onChanged: _duration > Duration.zero ? (value) => _player.seek(Duration(milliseconds: value.round())) : null,
          ),
        ])),
        Text('${_clock(_position)} / ${_clock(total)}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ]),
    );
  }
}

class _SparkVideoPage extends StatefulWidget {
  final Uri uri;
  final Map<String, String> headers;
  const _SparkVideoPage({required this.uri, required this.headers});
  @override
  State<_SparkVideoPage> createState() => _SparkVideoPageState();
}

class _SparkVideoPageState extends State<_SparkVideoPage> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(widget.uri, httpHeaders: widget.headers);
    _controller.initialize().then((_) {
      if (!mounted) return;
      _controller.setLooping(true);
      setState(() {});
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return const Center(child: Text('تعذر تشغيل الفيديو', style: TextStyle(color: Colors.white70)));
    if (!_controller.value.isInitialized) return const Center(child: CircularProgressIndicator(color: gold));
    return Center(
      child: GestureDetector(
        onTap: () => setState(() {
          _controller.value.isPlaying ? _controller.pause() : _controller.play();
        }),
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(alignment: Alignment.center, children: [
            VideoPlayer(_controller),
            if (!_controller.value.isPlaying)
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
          ]),
        ),
      ),
    );
  }
}

class GroupChatPage extends StatefulWidget {
  final Map<String, dynamic> group;
  final String currentUserId;
  final VoidCallback onAddMember;
  final Future<void> Function() onGroupChanged;
  const GroupChatPage({
    super.key,
    required this.group,
    required this.currentUserId,
    required this.onAddMember,
    required this.onGroupChanged,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final Map<String, String> translatedMessages = {};
  final Set<String> translatingMessageIds = {};
  final Map<String, DateTime> translationRetryAfter = {};
  final Map<String, String> voiceTranscripts = {};
  final Set<String> transcribingMessageIds = {};
  bool loading = true;
  bool sending = false;
  bool refreshing = false;
  bool hasOlderMessages = false;
  bool loadingOlderMessages = false;
  Map<String, dynamic>? olderMessageCursor;
  Map<String, dynamic>? replyToMessage;
  Timer? refreshTimer;
  String get groupId => field(widget.group, ['id']);

  @override
  void initState() {
    super.initState();
    loadMessages();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !sending && !refreshing) loadMessages(silent: true);
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> _transcribeVoiceMessage(
    Map<String, dynamic> message,
    Map<String, dynamic> attachment,
  ) async {
    final id = field(message, ['id', 'message_id']);
    if (id.isEmpty || transcribingMessageIds.contains(id) || voiceTranscripts.containsKey(id)) return;
    if (!await confirmVoiceTranscription(context) || !mounted) return;
    setState(() => transcribingMessageIds.add(id));
    try {
      final transcript = await Api.transcribeAttachment(
        field(attachment, ['attachmentId']),
        expectedContentType: field(attachment, ['contentType']),
      );
      if (mounted) setState(() => voiceTranscripts[id] = transcript);
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => transcribingMessageIds.remove(id));
    }
  }

  Future<void> _translateMessages(List<Map<String, dynamic>> items) async {
    if (!BarqFeatures.autoTranslate) return;
    for (final message in items) {
      final id = field(message, ['id', 'message_id']);
      final senderId = field(message, ['sender_id', 'senderId']);
      final original = field(message, ['body', 'content', 'message']);
      if (id.isEmpty || senderId == widget.currentUserId || original.isEmpty ||
          _attachmentData(message) != null || translatedMessages.containsKey(id) ||
          translatingMessageIds.contains(id) ||
          !barqTranslationRetryAllowed(id, translationRetryAfter)) {
        continue;
      }
      translatingMessageIds.add(id);
      try {
        final translated = await BarqTranslator.translateArabicEnglish(original);
        if (mounted && translated.isNotEmpty) {
          setState(() {
            translatedMessages[id] = translated;
            translationRetryAfter.remove(id);
          });
        } else {
          translationRetryAfter[id] = DateTime.now().add(const Duration(minutes: 1));
        }
      } catch (_) {
        translationRetryAfter[id] = DateTime.now().add(const Duration(minutes: 1));
        // تبقى الرسالة الأصلية ظاهرة، وتُعاد المحاولة بعد دقيقة إذا توفر النموذج المحلي.
      } finally {
        translatingMessageIds.remove(id);
      }
    }
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    try {
      final page = await Api.groupMessagesPage(groupId);
      final data = Api._list(page['messages']);
      if (mounted) {
        setState(() {
        messages = silent && messages.isNotEmpty ? mergeMessages(messages, data) : data;
        if (!silent || olderMessageCursor == null) {
          olderMessageCursor = page['nextCursor'] is Map
              ? Map<String, dynamic>.from(page['nextCursor']) : null;
        }
        hasOlderMessages = page['hasMore'] == true || (silent && hasOlderMessages);
        loading = false;
      });
        if (BarqFeatures.autoTranslate) _translateMessages(data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        if (!silent) showMsg(context, cleanError(e));
      }
    } finally { refreshing = false; }
  }

  Future<void> loadOlderMessages() async {
    if (loadingOlderMessages || !hasOlderMessages || olderMessageCursor == null) return;
    setState(() => loadingOlderMessages = true);
    try {
      final page = await Api.groupMessagesPage(groupId, before: olderMessageCursor);
      final older = Api._list(page['messages']);
      if (mounted) {
        setState(() {
        messages = mergeMessages(older, messages);
        olderMessageCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor']) : null;
        hasOlderMessages = page['hasMore'] == true;
      });
      }
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => loadingOlderMessages = false);
    }
  }

  Future<void> send() async {
    final body = controller.text.trim();
    if (body.isEmpty || sending) return;
    if (!isBarqMessageTextAllowed(body)) {
      showMsg(context, 'الرسالة طويلة جدًا؛ الحد الأقصى 5000 حرف.');
      return;
    }
    setState(() => sending = true);
    try {
      await Api.sendGroupMessage(groupId, body,
        replyToId: replyToMessage == null ? null : field(replyToMessage!, ['id', 'message_id']));
      controller.clear();
      if (mounted) setState(() => replyToMessage = null);
      await loadMessages();
    } catch (e) { if (mounted) showMsg(context, cleanError(e)); }
    finally { if (mounted) setState(() => sending = false); }
  }

  Future<void> _sendVoiceRecording(List<int> bytes, Duration duration) async {
    if (BarqFeatures.lightningMode || sending) return;
    setState(() => sending = true);
    try {
      await Api.uploadAttachment(
        bytes: bytes,
        fileName: 'barq_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
        groupId: groupId,
      );
      await loadMessages();
      if (mounted) showMsg(context, 'تم إرسال التسجيل الصوتي (${formatBarqMediaDuration(duration)}) للمجموعة.');
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickAndSendFile() async {
    if (BarqFeatures.lightningMode) {
      showMsg(context, 'وضع البرق مفعّل: إرسال الوسائط والملفات متوقف مؤقتًا.');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('تعذر قراءة الملف من الجهاز.');
      setState(() => sending = true);
      await Api.uploadAttachment(
        bytes: bytes,
        fileName: file.name,
        contentType: file.extension == null ? 'application/octet-stream' : _mimeForExtension(file.extension!),
        groupId: groupId,
      );
      await loadMessages();
      if (mounted) showMsg(context, 'تم إرسال الملف للمجموعة.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> showGroupMembers() async {
    try {
      final members = await Api.groupMembers(groupId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('أعضاء المجموعة'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: members.isEmpty
                ? const Center(child: Text('لا يوجد أعضاء لعرضهم.'))
                : ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isOwner = member['is_owner'] == 1 || member['is_owner'] == true;
                      final memberRole = isOwner ? 'owner' : field(member, ['role'], 'member');
                      final actorRole = field(widget.group, ['current_role'], 'member');
                      final memberId = field(member, ['id', 'user_id']);
                      final isSelf = memberId == widget.currentUserId;
                      final canManageRoles = barqCanManageGroupRoles(
                        actorRole,
                        targetIsOwner: isOwner,
                      );
                      final canRemove = barqCanRemoveGroupMember(
                        actorRole,
                        memberRole,
                        targetIsOwner: isOwner,
                        targetIsSelf: isSelf,
                      );
                      final canLeave = barqCanLeaveGroup(
                        isSelf: isSelf,
                        isOwner: isOwner,
                      );
                      final canTransferOwnership = barqCanTransferGroupOwnership(
                        actorRole,
                        targetIsOwner: isOwner,
                        targetIsSelf: isSelf,
                      );
                      return ListTile(
                        leading: personAvatar(member),
                        title: Text(field(member, ['display_name', 'displayName', 'username'], 'عضو')),
                        subtitle: Text(isOwner
                            ? 'مالك المجموعة'
                            : memberRole == 'admin'
                                ? 'مشرف'
                                : '@${field(member, ['username'])}'),
                        trailing: (canManageRoles || canRemove || canLeave || canTransferOwnership)
                            ? PopupMenuButton<String>(
                                onSelected: (action) async {
                                  final actionLabel = action == 'remove' ? 'إزالة هذا العضو من المجموعة؟'
                                      : action == 'leave' ? 'هل تريد مغادرة المجموعة؟'
                                      : action == 'admin' ? 'تعيين هذا العضو مشرفًا؟'
                                      : action == 'owner' ? 'نقل ملكية المجموعة إلى هذا العضو؟ لن تعود مالكًا للمجموعة.'
                                      : 'إلغاء صلاحية الإشراف عن هذا العضو؟';
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (confirmContext) => AlertDialog(
                                      backgroundColor: Theme.of(context).colorScheme.surface,
                                      title: const Text('تأكيد الإجراء'),
                                      content: Text(actionLabel),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('إلغاء')),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(confirmContext, true),
                                          child: const Text('تأكيد'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !mounted) return;
                                  try {
                                    if (action == 'owner') {
                                      await Api.transferGroupOwnership(groupId, memberId);
                                    } else if (action == 'admin' || action == 'member') {
                                      await Api.setGroupMemberRole(groupId, memberId, action);
                                    } else {
                                      await Api.removeGroupMember(groupId, memberId);
                                    }
                                    if (!dialogContext.mounted) return;
                                    Navigator.pop(dialogContext);
                                    if (!mounted) return;
                                    showMsg(
                                      context,
                                      action == 'leave'
                                          ? 'غادرت المجموعة.'
                                          : action == 'owner'
                                              ? 'تم نقل ملكية المجموعة.'
                                              : 'تم تحديث عضوية المجموعة.',
                                    );
                                    if (action == 'owner') {
                                      final onGroupChanged = widget.onGroupChanged;
                                      Navigator.pop(context);
                                      await onGroupChanged();
                                      return;
                                    }
                                    await showGroupMembers();
                                  } catch (e) {
                                    if (mounted) showMsg(this.context, cleanError(e));
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (canTransferOwnership)
                                    const PopupMenuItem(value: 'owner', child: Text('نقل الملكية')),
                                  if (canManageRoles && memberRole != 'admin')
                                    const PopupMenuItem(value: 'admin', child: Text('تعيين مشرف')),
                                  if (canManageRoles && memberRole == 'admin')
                                    const PopupMenuItem(value: 'member', child: Text('إلغاء الإشراف')),
                                  if (canRemove)
                                    const PopupMenuItem(value: 'remove', child: Text('إزالة من المجموعة')),
                                  if (canLeave)
                                    const PopupMenuItem(value: 'leave', child: Text('مغادرة المجموعة')),
                                ],
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(dialogContext);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PublicProfilePage(
                              person: member,
                              currentUserId: widget.currentUserId,
                            ),
                          ));
                        },
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(field(widget.group, ['name'], 'مجموعة'), overflow: TextOverflow.ellipsis)),
            if (BarqFeatures.lightningMode) ...[
              const SizedBox(width: 6),
              const Icon(Icons.flash_on_rounded, size: 18),
            ],
          ]),
          actions: [
            IconButton(
              onPressed: () => showBarqConversationTools(context, [
                BarqConversationTool(
                  icon: Icons.search,
                  title: 'البحث في المحادثة',
                  subtitle: 'ابحث داخل رسائل المجموعة المحمّلة',
                  onTap: () => showConversationSearch(context, (query, before) => Api.searchGroupMessages(groupId, query, before: before)),
                ),
                BarqConversationTool(
                  icon: Icons.auto_awesome_outlined,
                  title: 'ملخص المحادثة',
                  subtitle: 'إنشاء ملخص ذكي بعد موافقتك',
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => BarqConversationSummaryDialog(
                      loadSummary: () => Api.summarizeGroupConversation(groupId),
                    ),
                  ),
                ),
                BarqConversationTool(
                  icon: Icons.push_pin_outlined,
                  title: 'الرسائل المثبتة (${messages.where((message) => message['is_pinned'] == true).length})',
                  subtitle: 'عرض المثبتة ضمن الرسائل المحمّلة',
                  onTap: () => showBarqMessageCollectionDialog(context,
                    title: 'الرسائل المثبتة', messages: messages, attachmentsOnly: false),
                ),
                BarqConversationTool(
                  icon: Icons.perm_media_outlined,
                  title: 'الوسائط والملفات (${messages.where((message) => _attachmentData(message) != null).length})',
                  subtitle: 'عرض المرفقات ضمن الرسائل المحمّلة',
                  onTap: () => showBarqMessageCollectionDialog(context,
                    title: 'الوسائط والملفات', messages: messages, attachmentsOnly: true),
                ),
              ]),
              icon: const Icon(Icons.build_circle_outlined),
              tooltip: 'أدوات المحادثة',
            ),
            IconButton(onPressed: showGroupMembers, icon: const Icon(Icons.people_alt_outlined), tooltip: 'أعضاء المجموعة'),
            if (['owner', 'admin'].contains(field(widget.group, ['current_role'], 'member')))
              IconButton(onPressed: widget.onAddMember, icon: const Icon(Icons.person_add_alt_1), tooltip: 'إضافة عضو'),
            IconButton(onPressed: loadMessages, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Column(children: [
          Expanded(child: loading
            ? const Center(child: CircularProgressIndicator(color: gold))
            : messages.isEmpty
              ? const Center(child: Text('لا توجد رسائل بعد. ابدأ الحديث مع مجموعتك.', style: TextStyle(color: Colors.white60)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12), itemCount: messages.length + (hasOlderMessages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasOlderMessages && index == 0) {
                      return Center(child: TextButton.icon(
                        onPressed: loadingOlderMessages ? null : loadOlderMessages,
                        icon: loadingOlderMessages
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.history),
                        label: const Text('تحميل الرسائل الأقدم'),
                      ));
                    }
                    final m = messages[index - (hasOlderMessages ? 1 : 0)];
                    final mine = field(m, ['sender_id']) == widget.currentUserId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 310),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(15)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (field(m, ['reply_to_id']).isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 7),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8),
                                border: const Border(right: BorderSide(color: gold, width: 3))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(field(m, ['reply_to_sender_id']) == widget.currentUserId ? 'رد على رسالتك' : 'رد على رسالة',
                                  style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(messageReplyPreview(m), maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ]),
                            ),
                          if (!mine)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PublicProfilePage(
                                  person: {
                                    'id': field(m, ['sender_id']),
                                    'username': field(m, ['username']),
                                    'display_name': field(m, ['display_name']),
                                    'photo_updated_at': field(m, ['photo_updated_at']),
                                  },
                                  currentUserId: widget.currentUserId,
                                ),
                              )),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Text(field(m, ['display_name', 'username'], 'عضو'),
                                  style: const TextStyle(color: gold, fontSize: 11)),
                              ),
                            ),
                          if (_attachmentData(m) case final attachment?) ...[
                            _attachmentTile(attachment, () async {
                              try {
                                await Api.downloadAttachment(
                                  attachmentId: field(attachment, ['attachmentId']),
                                  fileName: field(attachment, ['fileName'], 'attachment'),
                                );
                              } catch (e) { if (context.mounted) showMsg(context, cleanError(e)); }
                            }),
                            if (field(attachment, ['contentType']).startsWith('audio/'))
                              TextButton.icon(
                                onPressed: transcribingMessageIds.contains(field(m, ['id', 'message_id']))
                                    ? null : () => _transcribeVoiceMessage(m, attachment),
                                icon: transcribingMessageIds.contains(field(m, ['id', 'message_id']))
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.subtitles_outlined, size: 16),
                                label: const Text('تحويل الصوت إلى نص'),
                              ),
                            if (voiceTranscripts[field(m, ['id', 'message_id'])] != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                                child: Text(voiceTranscripts[field(m, ['id', 'message_id'])]!),
                              ),
                          ] else ...[
                            GestureDetector(
                              onLongPress: () => showMessageActions(
                                context,
                                message: m,
                                canDelete: mine,
                                onDelete: () async {
                                  await Api.deleteGroupMessage(groupId, field(m, ['id', 'message_id']));
                                  if (mounted) await loadMessages();
                                },
                                onReply: (message) async {
                                  setState(() => replyToMessage = Map<String, dynamic>.from(message));
                                },
                                onEdit: mine && _attachmentData(m) == null
                                    ? (body) async {
                                        await Api.editGroupMessage(groupId, field(m, ['id', 'message_id']), body);
                                        if (mounted) await loadMessages();
                                      }
                                    : null,
                                onReact: (emoji) async {
                                  await Api.reactGroupMessage(groupId, field(m, ['id', 'message_id']), emoji);
                                  if (mounted) await loadMessages(silent: true);
                                },
                                onPin: () async {
                                  await Api.pinGroupMessage(groupId, field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
                                  if (mounted) await loadMessages(silent: true);
                                },
                                onSaveMemory: m['is_ephemeral'] != true && m['is_offline_pending'] != true &&
                                        field(m, ['body', 'content', 'message']).trim().isNotEmpty
                                    ? () async {
                                        await Api.savePrivateMemory(
                                          title: 'رسالة محفوظة',
                                          content: field(m, ['body', 'content', 'message']),
                                          sourceType: 'message',
                                        );
                                        if (context.mounted) showMsg(context, 'تم حفظ الرسالة في ذكرياتك الخاصة.');
                                      }
                                    : null,
                                isPinned: m['is_pinned'] == true,
                              ),
                              child: BarqMessageBody(text: field(m, ['body'])),
                            ),
                            if (BarqFeatures.autoTranslate && translatedMessages[field(m, ['id', 'message_id'])] != null) ...[
                              const SizedBox(height: 6),
                              const Divider(height: 1, color: Colors.white24),
                              const SizedBox(height: 6),
                              Text(translatedMessages[field(m, ['id', 'message_id'])]!,
                                style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                            ],
                          ],
                          Align(alignment: Alignment.centerLeft, child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_messageTime(field(m, ['created_at'])),
                                style: const TextStyle(color: Colors.white54, fontSize: 10)),
                              if (field(m, ['edited_at', 'editedAt']).isNotEmpty) ...[
                                const SizedBox(width: 5),
                                const Text('تم التعديل', style: TextStyle(color: Colors.white54, fontSize: 9)),
                              ],
                            ],
                          )),
                          if (m['is_pinned'] == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.push_pin, size: 12),
                                SizedBox(width: 3),
                                Text('مثبتة', style: TextStyle(color: gold, fontSize: 10)),
                              ]),
                            ),
                          messageReactionBar(
                            context: context,
                            message: m,
                            currentUserId: widget.currentUserId,
                            onReaction: (emoji, remove) async {
                              await Api.reactGroupMessage(groupId, field(m, ['id', 'message_id']), emoji, remove: remove);
                              if (mounted) await loadMessages(silent: true);
                            },
                            isPinned: m['is_pinned'] == true,
                            onPin: () async {
                              await Api.pinGroupMessage(groupId, field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
                              if (mounted) await loadMessages(silent: true);
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                )),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(children: [
              if (!BarqFeatures.lightningMode)
                IconButton(onPressed: sending ? null : pickAndSendFile,
                  icon: const Icon(Icons.attach_file), tooltip: 'إرسال ملف أو صورة أو فيديو'),
              if (!BarqFeatures.lightningMode)
                BarqVoiceRecordButton(disabled: sending, onSend: _sendVoiceRecording),
              Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 4,
                decoration: inputDecoration('اكتب رسالة للمجموعة...', Icons.message).copyWith(
                  helperText: replyToMessage == null ? null : 'الرد على: ${messageReplyPreview(replyToMessage!)}',
                  helperStyle: const TextStyle(color: gold, fontSize: 10),
                ), onSubmitted: (_) => send())),
              const SizedBox(width: 8),
              if (replyToMessage != null)
                IconButton(onPressed: sending ? null : () => setState(() => replyToMessage = null),
                  icon: const Icon(Icons.close, color: Colors.white70), tooltip: 'إلغاء الرد'),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
                onPressed: sending ? null : send,
                icon: sending ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.send),
              ),
            ]),
          )),
        ]),
      ),
    );
  }
}
