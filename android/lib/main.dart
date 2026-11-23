import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';

import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'barq_identity.dart';

const Color gold = Color(0xFFD6AD55);
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
  defaultValue: apiBase,
);
const String barqPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.barq.app';

String get barqInviteMessage =>
    'جرّب تطبيق برق — BARQ للتواصل السريع مع الأصدقاء. حمّل التطبيق من هنا: $barqPlayStoreUrl';

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
    case 'm4v':
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

/// Preserve the real extension returned by the device gallery. Some Android
/// providers expose an asset title without its extension, which otherwise
/// caused valid photos/videos to be uploaded as application/octet-stream.
String barqMediaPickerFileName({
  required String title,
  required String path,
  required String fallbackExtension,
}) {
  final cleanTitle = title.trim();
  final baseName = cleanTitle.isEmpty ? 'barq_media' : cleanTitle;
  final hasExtension = baseName.contains('.') &&
      baseName.split('.').last.trim().isNotEmpty;
  if (hasExtension) return baseName;
  final pathName = File(path).uri.pathSegments.isEmpty
      ? ''
      : File(path).uri.pathSegments.last;
  final pathExtension = pathName.contains('.')
      ? pathName.split('.').last.trim()
      : '';
  final extension = pathExtension.isNotEmpty
      ? pathExtension
      : fallbackExtension.trim().replaceFirst(RegExp(r'^\.'), '');
  return extension.isEmpty ? baseName : '$baseName.$extension';
}
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

final ValueNotifier<Map<String, String>?> barqPendingNotificationTap =
    ValueNotifier<Map<String, String>?>(null);

final GlobalKey<ScaffoldMessengerState> barqScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final FlutterLocalNotificationsPlugin barqLocalNotifications =
    FlutterLocalNotificationsPlugin();

/// Known push categories only; never expose sender names or message bodies.
String? barqForegroundPushLabel(
  Map<String, dynamic> data,
  Map<String, dynamic> preferences,
) {
  final ephemeral = data['ephemeral'] == true ||
      data['temporary'] == true ||
      data['ephemeral']?.toString().toLowerCase() == 'true' ||
      data['temporary']?.toString().toLowerCase() == 'true';
  if (ephemeral) return null;
  switch (data['type']?.toString()) {
    case 'direct_message':
      return preferences['messages'] == false ? null : 'وصلتك رسالة جديدة';
    case 'group_message':
      return preferences['groups'] == false ? null : 'وصلتك رسالة جديدة في مجموعة';
    case 'status_update':
      return preferences['statuses'] == false ? null : 'هناك لحظة جديدة في SPARK';
    default:
      return null;
  }
}

Future<bool> revokeBarqFcmTokenSafely({
  required String? authToken,
  required String? fcmToken,
  required Future<void> Function(String token) revoke,
}) async {
  final token = normalizeBarqFcmToken(fcmToken);
  if ((authToken ?? '').isEmpty || token == null) return false;
  try {
    await revoke(token);
    return true;
  } catch (_) {
    return false;
  }
}


/// إعدادات الميزات المحلية التي لا تحتاج إلى اتصال بالخادم.
Future<FilePickerResult?> showBarqMediaPicker(
  BuildContext context, {
  required bool allowMultiple,
  required String title,
  bool withData = false,
  bool allowFiles = true,
  RequestType requestType = RequestType.common,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final palette = Theme.of(sheetContext).colorScheme;
      return Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: palette.primary.withValues(alpha: .22)),
          boxShadow: [BoxShadow(color: palette.primary.withValues(alpha: .12), blurRadius: 28)],
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(
            color: palette.onSurface.withValues(alpha: .22), borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.perm_media_rounded, color: palette.primary),
            const SizedBox(width: 9),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 14),
          if (allowFiles)
            Row(children: [
              Expanded(child: _BarqMediaChoice(
                icon: Icons.photo_library_rounded, title: 'الصور والفيديو',
                subtitle: 'من معرض جهازك', onTap: () => Navigator.pop(sheetContext, 'media'))),
              const SizedBox(width: 10),
              Expanded(child: _BarqMediaChoice(
                icon: Icons.folder_rounded, title: 'الملفات',
                subtitle: 'مستندات وملفات أخرى', onTap: () => Navigator.pop(sheetContext, 'files'))),
            ])
          else
            SizedBox(width: double.infinity, child: _BarqMediaChoice(
              icon: Icons.photo_library_rounded, title: 'اختيار الصور',
              subtitle: 'من معرض جهازك', onTap: () => Navigator.pop(sheetContext, 'media'))),
          const SizedBox(height: 10),
          Text(allowMultiple ? 'يمكنك تحديد عدة وسائط معاً.' : 'اختر عنصراً واحداً للإرسال.',
            style: TextStyle(color: palette.onSurface.withValues(alpha: .58), fontSize: 11)),
        ])),
      );
    },
  );
  if (choice == null || !context.mounted) return null;
  if (choice == 'files') {
    return FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: allowMultiple,
      withData: withData,
    );
  }

  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: AssetPickerConfig(
      maxAssets: allowMultiple ? 10 : 1,
      requestType: requestType,
      gridCount: 4,
      pageSize: 80,
      themeColor: Theme.of(context).colorScheme.primary,
      textDelegate: const ArabicAssetPickerTextDelegate(),
    ),
  );
  if (assets == null || assets.isEmpty || !context.mounted) return null;

  final selectedFiles = <PlatformFile>[];
  for (final asset in assets) {
    final file = await asset.file;
    if (file == null) continue;
    selectedFiles.add(PlatformFile(
      name: barqMediaPickerFileName(
        title: asset.title ?? 'barq_media_${asset.id}',
        path: file.path,
        fallbackExtension: asset.type == AssetType.video ? 'mp4' : 'jpg',
      ),
      path: file.path,
      size: await file.length(),
      bytes: withData ? await file.readAsBytes() : null,
    ));
  }
  if (selectedFiles.isEmpty) {
    throw Exception('تعذر قراءة الوسائط المختارة من الجهاز.');
  }
  if (!context.mounted) return null;
  return FilePickerResult(selectedFiles);
}

Future<void> _openBarqPickedMediaPreview(
  BuildContext context,
  PlatformFile file,
  bool isVideo,
) async {
  final path = file.path;
  if (path == null || path.isEmpty) return;
  if (isVideo) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BarqMediaViewer(videoFile: File(path), title: file.name),
    );
    return;
  }
  try {
    final bytes = await readBarqPickedFileBytes(file);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _BarqMediaViewer(imageBytes: Uint8List.fromList(bytes), title: file.name),
    );
  } catch (error) {
    if (context.mounted) showMsg(context, cleanError(error));
  }
}

// ignore: unused_element
Future<bool?> _showBarqMediaPreview(
  BuildContext context,
  List<PlatformFile> files,
) {
  const videoExtensions = {'mp4', 'mov', 'm4v', 'webm'};
  final palette = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: palette.surface,
      title: Text('معاينة ${files.length} ${files.length == 1 ? 'وسيط' : 'وسائط'}'),
      content: SizedBox(
        width: 360,
        height: 280,
        child: GridView.builder(
          itemCount: files.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final file = files[index];
            final extension = (file.extension ?? '').toLowerCase();
            final isVideo = videoExtensions.contains(extension);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: file.path == null
                  ? null
                  : () => _openBarqPickedMediaPreview(context, file, isVideo),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isVideo && file.path != null)
                      _BarqPickedVideoThumbnail(file: file)
                    else if (!isVideo && file.path != null)
                      Image.file(
                        File(file.path!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: palette.surfaceContainerHighest,
                          child: Icon(Icons.broken_image_outlined, color: palette.onSurfaceVariant),
                        ),
                      )
                    else
                      ColoredBox(
                        color: palette.surfaceContainerHighest,
                        child: Icon(Icons.insert_drive_file_rounded, size: 38, color: palette.primary),
                      ),
                    if (isVideo)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.play_arrow_rounded, color: palette.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('متابعة'),
        ),
      ],
    ),
  );
}

class _BarqPickedVideoThumbnail extends StatefulWidget {
  final PlatformFile file;
  const _BarqPickedVideoThumbnail({required this.file});

  @override
  State<_BarqPickedVideoThumbnail> createState() => _BarqPickedVideoThumbnailState();
}

class _BarqPickedVideoThumbnailState extends State<_BarqPickedVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final path = widget.file.path;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      await controller.setVolume(0);
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
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
    if (controller == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: _failed
              ? const Icon(Icons.video_file_outlined, size: 34)
              : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _BarqMediaChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _BarqMediaChoice({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return Material(
      color: palette.primary.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.primary.withValues(alpha: .20))),
          child: Column(children: [
            Icon(icon, size: 30, color: palette.primary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: palette.onSurface.withValues(alpha: .58))),
          ]),
        ),
      ),
    );
  }
}

class BarqFeatures {
  static bool autoTranslate = false;
  static const String _translationKey = 'barq_auto_translate';

  static Future<void> load() async {
    try {
      autoTranslate = await storage.read(key: _translationKey) == '1';
    } catch (_) {
      // فشل قراءة إعداد محلي لا يمنع تشغيل التطبيق؛ تبقى الميزات الاختيارية متوقفة.
      autoTranslate = false;
    }
  }

  static Future<void> setAutoTranslate(bool enabled) async {
    await storage.write(key: _translationKey, value: enabled ? '1' : '0');
    autoTranslate = enabled;
  }
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

/// Android 13+ nearby-device permissions no longer require the device location
/// service to be enabled; Android 12L and earlier still use location discovery.
bool barqNearbyRequiresLocationService(int sdkInt) => sdkInt <= 32;

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
  await SirajPush.initializeLocalNotifications();
  FirebaseMessaging.onBackgroundMessage(barqFcmBackgroundHandler);
  try {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      SirajPush.queueNotificationTap(initialMessage);
    }
  } catch (_) {}
  await BarqFeatures.load();
  await BarqIdentity.load();
  runApp(const SirajApp());
}

/// Firebase requires a top-level background handler. Notification payloads are
/// displayed by the Android FCM SDK; this handler intentionally avoids private data.
@pragma('vm:entry-point')
Future<void> barqFcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Converts only supported notification payloads into safe navigation intents.
Map<String, String>? barqNotificationRouteFromData(Map<String, dynamic> data) {
  final type = data['type']?.toString().trim() ?? '';
  if (type == 'direct_message') {
    final senderId = data['senderId']?.toString().trim() ?? '';
    if (senderId.isEmpty) return null;
    return {'type': type, 'senderId': senderId};
  }
  if (type == 'group_message') {
    final groupId = data['groupId']?.toString().trim() ?? '';
    if (groupId.isEmpty) return null;
    return {'type': type, 'groupId': groupId};
  }
  if (type == 'status_update') {
    final statusId = data['statusId']?.toString().trim() ?? '';
    return {'type': type, if (statusId.isNotEmpty) 'statusId': statusId};
  }
  return null;
}

/// Normalize an FCM token before sending it to the authenticated API.
String? normalizeBarqFcmToken(String? token) {
  final value = token?.trim() ?? '';
  if (value.isEmpty || value.length > 4096 || RegExp(r'\s').hasMatch(value)) {
    return null;
  }
  return value;
}

/// Only authorized or provisional permission states may register an FCM token.
bool barqCanRegisterFcmToken(AuthorizationStatus status) =>
    status == AuthorizationStatus.authorized ||
    status == AuthorizationStatus.provisional;

/// تفعيل إذن الإشعارات وتسجيل رمز الجهاز بعد تسجيل الدخول.
class SirajPush {
  static bool _foregroundListening = false;
  static bool _tokenRefreshListening = false;
  static bool _tapListening = false;
  static String? _lastTapFingerprint;
  static DateTime? _lastRegistrationAttempt;

  static void queueNotificationTap(RemoteMessage message) {
    final route = barqNotificationRouteFromData(message.data);
    if (route == null) return;
    final fingerprint = message.messageId ??
        '${route['type']}:${route['senderId'] ?? route['groupId'] ?? route['statusId'] ?? ''}';
    if (_lastTapFingerprint == fingerprint) return;
    _lastTapFingerprint = fingerprint;
    barqPendingNotificationTap.value = route;
  }
  static Map<String, dynamic> _preferences = {
    'messages': true, 'groups': true, 'statuses': true,
  };

  static void updatePreferences(Map<String, dynamic> preferences) {
    _preferences = {
      'messages': preferences['messages'] != false,
      'groups': preferences['groups'] != false,
      'statuses': preferences['statuses'] != false,
    };
    unawaited(storage.write(
      key: 'barq_notification_prefs',
      value: jsonEncode(_preferences),
    ).catchError((_) {}));
  }

  static Future<void> loadCachedPreferences() async {
    try {
      final raw = await storage.read(key: 'barq_notification_prefs');
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _preferences = {
          'messages': decoded['messages'] != false,
          'groups': decoded['groups'] != false,
          'statuses': decoded['statuses'] != false,
        };
      }
    } catch (_) {}
  }

  static Future<void> clearPreferences() async {
    _preferences = {'messages': true, 'groups': true, 'statuses': true};
    _lastRegistrationAttempt = null;
    try { await storage.delete(key: 'barq_notification_prefs'); } catch (_) {}
  }

  static bool _localNotificationsReady = false;

  static Future<void> initializeLocalNotifications() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      final initialized = await barqLocalNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final raw = response.payload;
          if (raw == null || raw.isEmpty) return;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              queueNotificationTap(RemoteMessage(
                data: Map<String, dynamic>.from(decoded),
              ));
            }
          } catch (_) {}
        },
      );
      _localNotificationsReady = initialized != false;
      final launchDetails = await barqLocalNotifications.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null && launchPayload.isNotEmpty) {
        try {
          final decoded = jsonDecode(launchPayload);
          if (decoded is Map) {
            queueNotificationTap(RemoteMessage(
              data: Map<String, dynamic>.from(decoded),
            ));
          }
        } catch (_) {}
      }
    } catch (_) {
      _localNotificationsReady = false;
    }
  }

  static String _channelFor(RemoteMessage message) {
    switch (message.data['type']?.toString()) {
      case 'group_message':
        return 'barq_groups';
      case 'status_update':
        return 'barq_statuses';
      default:
        return 'barq_messages';
    }
  }

  static Future<void> _showForegroundNotification(
    RemoteMessage message,
    String label,
  ) async {
    if (_localNotificationsReady) {
      final type = message.data['type']?.toString();
      final title = message.notification?.title ??
          (type == 'group_message' ? 'رسالة جديدة في مجموعة برق'
            : type == 'status_update' ? 'لحظة جديدة في SPARK'
            : 'رسالة جديدة في برق');
      final body = message.notification?.body ?? label;
      final channelId = _channelFor(message);
      final channelName = channelId == 'barq_groups' ? 'رسائل مجموعات برق'
          : channelId == 'barq_statuses' ? 'SPARK برق' : 'رسائل برق الخاصة';
      try {
        await barqLocalNotifications.show(
          message.messageId?.hashCode.abs() ?? DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: 'إشعارات تطبيق برق',
              importance: channelId == 'barq_statuses'
                  ? Importance.defaultImportance : Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              playSound: true,
              enableVibration: true,
            ),
          ),
          payload: jsonEncode(message.data),
        );
        return;
      } catch (_) {}
    }
    final messenger = barqScaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Text(label),
        ));
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    if (Api.token == null) return;
    SirajRealtime.instance.acceptPush(message.data);
    final label = barqForegroundPushLabel(message.data, _preferences);
    if (label == null) return;
    unawaited(_showForegroundNotification(message, label));
  }

  static Future<void> register({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastRegistrationAttempt != null &&
        now.difference(_lastRegistrationAttempt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastRegistrationAttempt = now;
    try {
      final messaging = FirebaseMessaging.instance;
      // Foreground in-app alerts are independent from OS notification permission.
      if (!_foregroundListening) {
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        _foregroundListening = true;
      }
      if (!_tapListening) {
        FirebaseMessaging.onMessageOpenedApp.listen(queueNotificationTap);
        _tapListening = true;
      }

      final permission = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (!barqCanRegisterFcmToken(permission.authorizationStatus)) return;

      if (!_tokenRefreshListening) {
        messaging.onTokenRefresh.listen((newToken) async {
          final refreshedToken = normalizeBarqFcmToken(newToken);
          if (Api.token == null || refreshedToken == null) return;
          try {
            await Api.registerDeviceToken(refreshedToken);
          } catch (_) {}
        });
        _tokenRefreshListening = true;
      }

      final token = normalizeBarqFcmToken(await messaging.getToken());
      if (token != null) await Api.registerDeviceToken(token);
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
          scaffoldMessengerKey: barqScaffoldMessengerKey,
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
              onSurface: palette.text,
              outline: palette.border,
            ),
            textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: palette.text,
              displayColor: palette.text,
            ),
            dividerColor: palette.border,
            dividerTheme: DividerThemeData(color: palette.border, thickness: 1),
            listTileTheme: ListTileThemeData(
              iconColor: palette.primary,
              textColor: palette.text,
              tileColor: Colors.transparent,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: palette.primary,
              selectionColor: palette.primary.withValues(alpha: .28),
              selectionHandleColor: palette.primary,
            ),
            checkboxTheme: CheckboxThemeData(
              fillColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? palette.primary : Colors.transparent),
              checkColor: WidgetStateProperty.all(palette.onPrimary),
              side: BorderSide(color: palette.border),
            ),
            radioTheme: RadioThemeData(
              fillColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? palette.primary : palette.mutedText),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? palette.onPrimary : palette.mutedText),
              trackColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? palette.primary : palette.border),
            ),
            sliderTheme: SliderThemeData(
              activeTrackColor: palette.primary,
              inactiveTrackColor: palette.border,
              thumbColor: palette.primary,
              overlayColor: palette.primary.withValues(alpha: .16),
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
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.primary, width: 1.5),
              ),
              labelStyle: TextStyle(color: palette.mutedText),
              hintStyle: TextStyle(color: palette.mutedText),
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

bool barqRealtimeCanConnect({required String? authToken, required bool appResumed, required String socketUrl}) =>
    appResumed && authToken != null && authToken.isNotEmpty && socketUrl.trim().isNotEmpty;

bool barqRealtimeMessageMatchesConversation(
  Map<String, dynamic> event,
  String conversationUserId,
) {
  if (conversationUserId.isEmpty || event['type'] != 'message') return false;
  final sender = event['senderId']?.toString();
  final receiver = event['receiverId']?.toString();
  return sender == conversationUserId || receiver == conversationUserId;
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

  /// Forward foreground FCM events to open chats immediately; REST remains the source of truth.
  void acceptPush(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'direct_message') {
      _events.add({'type': 'message', 'senderId': data['senderId']?.toString() ?? ''});
    } else if (type == 'group_message') {
      _events.add({'type': 'group_message', 'groupId': data['groupId']?.toString() ?? ''});
    } else if (type == 'status_update') {
      _events.add({'type': 'status_update', 'statusId': data['statusId']?.toString() ?? ''});
    }
  }

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

bool isBarqPrivateMemoryPhotoContentTypeAllowed(String contentType) =>
    const {'image/jpeg', 'image/png', 'image/webp'}
        .contains(contentType.trim().toLowerCase());

Future<List<String>> uploadPrivateMemoryPhotosSequentially({
  required String memoryId,
  required List<Map<String, dynamic>> photos,
  required PrivateMemoryPhotoUploader upload,
}) async {
  final failedFiles = <String>[];
  for (final photo in photos) {
    final fileName = photo['name'] as String? ?? 'صورة بدون اسم';
    try {
      final storedBytes = photo['bytes'];
      final bytes = storedBytes is List<int>
          ? storedBytes
          : await File(photo['path'] as String).readAsBytes();
      if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
        throw Exception('حجم الصورة غير مسموح.');
      }
      final contentType = (photo['contentType'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (!isBarqPrivateMemoryPhotoContentTypeAllowed(contentType)) {
        throw Exception('صيغة صورة الذكرى غير مدعومة.');
      }
      await upload(
        memoryId: memoryId,
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
      );
    } catch (_) {
      failedFiles.add(fileName);
    }
  }
  return failedFiles;
}

Future<Uint8List> readBarqPickedFileBytes(PlatformFile file) async {
  final existingBytes = file.bytes;
  if (existingBytes != null && existingBytes.isNotEmpty) {
    return Uint8List.fromList(existingBytes);
  }
  final path = file.path;
  if (path == null || path.isEmpty) {
    throw Exception('تعذر قراءة الملف المختار من الجهاز.');
  }
  return File(path).readAsBytes();
}

class Api {
  // Reuse a persistent client so sequential chat, media and sync requests can reuse keep-alive connections.
  static final http.Client _client = http.Client();
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
          response = await _client.get(uri, headers: headers)
              .timeout(const Duration(seconds: 25));
          break;
        case 'DELETE':
          response = await _client.delete(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ).timeout(const Duration(seconds: 25));
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          ).timeout(const Duration(seconds: 25));
          break;
        case 'PATCH':
          response = await _client.patch(
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
  }) async {
    lastRecoveryCode = null;
    final privateUsername = barqPrivateRegistrationUsername(phone);
    final data = await request('POST', '/api/register', body: {
      // Send both legacy and current name keys while API gateways are being aligned.
      'name': displayName,
      'displayName': displayName,
      // Phone stays the primary identifier; this private handle satisfies older gateways.
      'username': privateUsername,
      'password': password,
      'phone': phone,
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
  }) async => _map((await request('POST', '/api/profile', body: {
        'displayName': displayName.trim(),
      }))['user']);

  static Future<void> uploadProfilePhoto(List<int> bytes, String contentType) async {
    final response = await _client.post(
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

  static Future<List<Map<String, dynamic>>> friends() async =>
      _list((await request('GET', '/api/friends'))['friends']);

  static Future<List<Map<String, dynamic>>> blockedUsers() async =>
      _list((await request('GET', '/api/blocks'))['blockedUsers']);

  static Future<void> blockUser(String userId) async {
    await request('POST', '/api/blocks', body: {'userId': userId});
  }

  static Future<void> unblockUser(String userId) async {
    await request('DELETE', '/api/blocks?userId=${Uri.encodeQueryComponent(userId)}');
  }

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
    if (!isBarqPrivateMemoryPhotoContentTypeAllowed(contentType)) {
      throw Exception('صيغة صورة الذكرى غير مدعومة.');
    }
    final response = await _postMediaPathResponse(
      '/api/private-memories/${Uri.encodeComponent(memoryId)}/media',
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': contentType,
        'X-File-Name': Uri.encodeComponent(fileName),
      },
      bytes: bytes,
      timeout: const Duration(minutes: 2),
    );
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
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw Exception('حجم الوسائط يجب ألا يتجاوز 60 ميجابايت.');
    }
    if (!RegExp(r'^(image/(jpeg|png|webp|gif)|video/(mp4|webm|quicktime))$').hasMatch(contentType)) {
      throw Exception('نوع الملف غير مدعوم في SPARK.');
    }
    // Small SPARK media travels through Vercel first, with Worker fallback.
    // Large uploads stay direct to the Worker to avoid Vercel's body-size cap.
    final response = await _postMediaPathResponse(
      '/api/statuses/media',
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': contentType,
        'X-File-Name': Uri.encodeComponent(fileName),
        'X-Status-Caption': caption.trim(),
        if (statusId != null) 'X-Status-Id': statusId,
      },
      bytes: bytes,
      timeout: const Duration(minutes: 3),
    );
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
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw Exception('حجم الرد الصوتي يجب ألا يتجاوز 5 ميجابايت.');
    }
    if (durationMs < 1000 || durationMs > 60000) {
      throw Exception('مدة الرد الصوتي يجب أن تكون بين ثانية و60 ثانية.');
    }
    final response = await _postMediaPathResponse(
      '/api/statuses/${Uri.encodeComponent(statusId)}/audio-replies',
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'audio/mp4',
        'X-Audio-Duration-Ms': durationMs.toString(),
      },
      bytes: bytes,
      timeout: const Duration(minutes: 2),
    );
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
    final response = await _getMediaPathResponse(
      '/api/statuses/${Uri.encodeComponent(statusId)}/audio-replies/${Uri.encodeComponent(replyId)}',
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
      timeout: const Duration(minutes: 2),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر تشغيل الرد الصوتي (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  // Route image/video reads through the public Vercel proxy first; it streams
  // bytes and Range responses while avoiding a direct workers.dev dependency.
  static Uri sparkMediaUri(String attachmentId) => Uri.parse(
    '$apiBase/api/media/${Uri.encodeComponent(attachmentId)}',
  );

  static Future<List<Map<String, dynamic>>> groups() async =>
      _list((await request('GET', '/api/groups'))['groups']);

  static Future<Map<String, dynamic>> createGroup(String name, String description) async =>
      _map((await request('POST', '/api/groups', body: {
        'name': name,
        'description': description,
      }))['group']);

  static Future<Map<String, dynamic>> createGroupInvite(String groupId) async =>
      request('POST', '/api/groups/${Uri.encodeComponent(groupId)}/invites');

  static Future<Map<String, dynamic>> joinGroupInvite(String inviteCode) async =>
      request('POST', '/api/groups/invites/${Uri.encodeComponent(inviteCode)}/accept');

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

  static Future<void> hidePrivateMessageForMe(String messageId) async {
    await request('DELETE',
      '/api/messages/${Uri.encodeComponent(messageId)}?scope=me');
  }

  static Future<void> clearPrivateConversation(String friendId) async {
    await request('POST',
      '/api/conversations/${Uri.encodeComponent(friendId)}/clear');
  }

  static Future<void> deletePrivateConversation(String friendId) async {
    await request('DELETE',
      '/api/conversations/${Uri.encodeComponent(friendId)}');
  }

  static Future<void> deleteGroupMessage(String groupId, String messageId) async {
    await request(
      'DELETE',
      '/api/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}',
    );
  }

  static Future<void> hideGroupMessageForMe(String groupId, String messageId) async {
    await request(
      'DELETE',
      '/api/groups/${Uri.encodeComponent(groupId)}/messages/${Uri.encodeComponent(messageId)}?scope=me',
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
    String caption = '',
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0);
    final fingerprintInput = utf8.encode(
      '${recipientId ?? ''}|${groupId ?? ''}|$fileName|$contentType|$caption|${crypto.sha256.convert(bytes)}',
    );
    final resumeStorageKey = 'barq_upload_resume_${crypto.sha256.convert(fingerprintInput)}';
    final idempotencyKey = await storage.read(key: resumeStorageKey) ?? newBarqMessageId();
    await storage.write(key: resumeStorageKey, value: idempotencyKey);
    final start = await request('POST', '/api/media/uploads', body: {
      'size': bytes.length,
      'fileName': fileName,
      'contentType': contentType,
      'caption': caption.trim(),
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
      onProgress?.call(1);
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
          response = await _client.put(uri, headers: {
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
      onProgress?.call(endOffset / bytes.length);
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
    onProgress?.call(1);
  }

  static Future<void> uploadAttachment({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? recipientId,
    String? groupId,
    String caption = '',
    void Function(double progress)? onProgress,
  }) async {
    if ((recipientId == null) == (groupId == null)) {
      throw Exception('حدد محادثة فردية أو مجموعة واحدة.');
    }
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw Exception('حجم الملف يجب ألا يتجاوز 60 ميجابايت.');
    }
    onProgress?.call(0);
    // Preserve the existing fast path for files up to 4 MiB.
    if (bytes.length > proxyMediaThresholdBytes) {
      await _uploadAttachmentResumable(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        recipientId: recipientId,
        groupId: groupId,
        caption: caption,
        onProgress: onProgress,
      );
      return;
    }
    final uri = Uri.parse('$apiBase/api/media');
    final client = http.Client();
    try {
      final upload = http.StreamedRequest('POST', uri)
        ..headers.addAll({
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': contentType,
          'X-File-Name': Uri.encodeComponent(fileName),
          if (recipientId != null) 'X-Recipient-Id': recipientId,
          if (groupId != null) 'X-Group-Id': groupId,
          if (caption.trim().isNotEmpty) 'X-Caption': Uri.encodeComponent(caption.trim()),
        })
        ..contentLength = bytes.length;
      final responseFuture = client.send(upload);
      // The request sink only queues bytes; it does not report network delivery.
      // Keep the UI indeterminate until the server confirms the upload.
      upload.sink.add(bytes);
      await upload.sink.close();
      final streamed = await responseFuture.timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception((data['error'] ?? 'تعذر إرسال الملف (${response.statusCode})').toString());
      }
      onProgress?.call(1);
    } finally {
      client.close();
    }
  }

  // Small binary uploads use Vercel first for restricted networks; large
  // payloads stay on the Worker because Vercel enforces a smaller request cap.
  static Future<http.Response> _postMediaPathResponse(
    String path, {
    required Map<String, String> headers,
    required List<int> bytes,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final bases = bytes.length <= proxyMediaThresholdBytes
        ? <String>[apiBase, if (mediaWorkerBase != apiBase) mediaWorkerBase]
        : <String>[mediaWorkerBase];
    Object? lastError;
    for (final base in bases) {
      try {
        final response = await _client.post(
          Uri.parse('$base$path'),
          headers: headers,
          body: bytes,
        ).timeout(timeout);
        if (response.statusCode < 500) return response;
        lastError = HttpException('Media gateway returned ${response.statusCode}');
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const HttpException('No media gateway is configured');
  }

  static Future<http.Response> _getMediaPathResponse(
    String path, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final bases = <String>[apiBase, if (mediaWorkerBase != apiBase) mediaWorkerBase];
    Object? lastError;
    for (final base in bases) {
      try {
        final response = await _client.get(
          Uri.parse('$base$path'),
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

  static Future<http.Response> _getMediaResponse(
    String attachmentId, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 2),
  }) => _getMediaPathResponse(
    '/api/media/${Uri.encodeComponent(attachmentId)}',
    headers: headers,
    timeout: timeout,
  );

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
      response = await _client.post(
        Uri.parse('$primaryTranscribeBase/api/transcribe'),
        headers: {...requestHeaders, 'Content-Type': contentType},
        body: audioBytes,
      ).timeout(const Duration(minutes: 3));
      if (response.statusCode >= 500 && fallbackTranscribeBase != null) {
        response = await _client.post(
          Uri.parse('$fallbackTranscribeBase/api/transcribe'),
          headers: {...requestHeaders, 'Content-Type': contentType},
          body: audioBytes,
        ).timeout(const Duration(minutes: 3));
      }
    } catch (_) {
      if (fallbackTranscribeBase == null) rethrow;
      response = await _client.post(
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

  static Future<List<int>> readAttachmentBytes(String attachmentId) async {
    final response = await _getMediaResponse(
      attachmentId,
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
      timeout: const Duration(minutes: 3),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر قراءة الملف للتحويل (${response.statusCode}).');
    }
    if (response.bodyBytes.isEmpty || response.bodyBytes.length > maxAttachmentBytes) {
      throw Exception('حجم الملف غير صالح للتحويل.');
    }
    return response.bodyBytes;
  }

  static Future<void> downloadAttachment({
    required String attachmentId,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    if (attachmentId.trim().isEmpty) throw Exception('معرّف الملف غير متوفر.');
    final requestHeaders = {if (token != null) 'Authorization': 'Bearer $token'};
    final bases = <String>[apiBase, if (mediaWorkerBase != apiBase) mediaWorkerBase];
    Object? lastError;
    Uint8List? downloadedBytes;
    final client = http.Client();
    try {
      for (final base in bases) {
        http.StreamedResponse? response;
        try {
          final request = http.Request(
            'GET',
            Uri.parse('$base/api/media/${Uri.encodeComponent(attachmentId)}'),
          )..headers.addAll(requestHeaders);
          response = await client.send(request).timeout(const Duration(minutes: 3));
          if (response.statusCode >= 500) {
            await response.stream.drain<void>();
            lastError = HttpException('Media gateway returned ${response.statusCode}');
            continue;
          }
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('تعذر تنزيل الملف (${response.statusCode}).');
          }
          final total = response.contentLength;
          if (total != null && (total <= 0 || total > maxAttachmentBytes)) {
            throw Exception('حجم الملف غير صالح للتنزيل.');
          }
          final builder = BytesBuilder(copy: false);
          var received = 0;
          onProgress?.call(0);
          await for (final chunk in response.stream.timeout(const Duration(minutes: 3))) {
            received += chunk.length;
            if (received > maxAttachmentBytes || (total != null && received > total)) {
              throw Exception('تجاوز الملف الحد المسموح أو أرسل الخادم حجماً غير صحيح.');
            }
            builder.add(chunk);
            if (total != null && total > 0) {
              onProgress?.call((received / total).clamp(0.0, 1.0));
            }
          }
          if (received == 0 || (total != null && received != total)) {
            throw Exception('انقطع تنزيل الملف قبل اكتماله. أعد المحاولة.');
          }
          downloadedBytes = Uint8List.fromList(builder.takeBytes());
          break;
        } catch (error) {
          lastError = error;
          if (error is Exception && error.toString().contains('تعذر تنزيل الملف')) rethrow;
        }
      }
    } finally {
      client.close();
    }
    final bytes = downloadedBytes;
    if (bytes == null) throw lastError ?? const HttpException('تعذر الاتصال بخادم الملفات.');
    onProgress?.call(1);
    final saved = await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
    if (saved == null) throw Exception('تم إلغاء حفظ الملف.');
  }

  static Future<void> deleteAccount(String confirmUsername) async {
    await request('DELETE', '/api/account', body: {'confirmUsername': confirmUsername});
    await logout();
    // Remove cached conversations and account-scoped local data from this device.
    await storage.deleteAll();
  }

  static Future<void> logout() async {
    // Revoke this installation's push token before clearing the auth session.
    // A network failure must never trap the user in the account.
    String? fcmToken;
    try { fcmToken = await FirebaseMessaging.instance.getToken(); } catch (_) {}
    await revokeBarqFcmTokenSafely(
      authToken: token,
      fcmToken: fcmToken,
      revoke: (value) async {
        await request('DELETE', '/api/devices/token', body: {'fcmToken': value});
      },
    );
    if (token != null) {
      try { await request('POST', '/api/logout'); } catch (_) {}
    }
    await SirajRealtime.instance.stop();
    await BarqNearbyService.instance.stop();
    token = null;
    await SirajPush.clearPreferences();
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

String barqSparkPrivateReplyMessage({required String caption, required String reply}) {
  final excerpt = caption.trim().replaceAll(RegExp(r'\s+'), ' ');
  final context = excerpt.isEmpty ? 'لحظة من SPARK' : excerpt;
  return '↩️ رد على SPARK\n$context\n\n${reply.trim()}';
}

Map<String, String>? parseBarqSparkPrivateReply(String body) {
  const prefix = '↩️ رد على SPARK\n';
  if (!body.startsWith(prefix)) return null;
  final content = body.substring(prefix.length);
  final divider = content.indexOf('\n\n');
  if (divider < 0) return null;
  return {
    'caption': content.substring(0, divider),
    'reply': content.substring(divider + 2),
  };
}

BoxDecoration barqChatWallpaperDecoration(BuildContext context, Color? wallpaper) {
  final base = wallpaper ?? const Color(0xFF061A36);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      stops: const [0, .48, 1],
      colors: [
        Color.lerp(base, const Color(0xFF0755A8), .24)!,
        base,
        Color.lerp(base, const Color(0xFF020A1C), .48)!,
      ],
    ),
  );
}

void insertBarqChatEmoji(TextEditingController controller) {
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : controller.text.length;
  final end = selection.isValid ? selection.end : controller.text.length;
  final updated = controller.text.replaceRange(start, end, ' 😊');
  controller.value = TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: start + 3),
  );
}

Future<Color?> showBarqWallpaperPicker(BuildContext context, Color? selected) {
  const choices = <Color>[
    Color(0xFF071A2D), Color(0xFF101827), Color(0xFF1B1630),
    Color(0xFF172A27), Color(0xFF242424), Color(0xFF0C2940),
  ];
  return showModalBottomSheet<Color>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('خلفية المحادثة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text('ألوان داكنة بتدرجات هادئة تناسب هوية برق.',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 16),
          Wrap(spacing: 13, runSpacing: 13, children: [
            for (final color in choices)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(sheetContext, color),
                child: Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(color, Colors.white, .13)!, color, Color.lerp(color, Colors.black, .28)!],
                    ),
                    border: Border.all(color: selected == color ? Theme.of(context).colorScheme.primary : Colors.white24, width: selected == color ? 3 : 1),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: .30), blurRadius: 12)],
                  ),
                  child: selected == color ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                ),
              ),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(sheetContext, Colors.transparent),
              child: const CircleAvatar(radius: 27, child: Icon(Icons.restart_alt_rounded)),
            ),
          ]),
        ]),
      ),
    ),
  );
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

  static Future<void> clearConversation(String friendId, String currentUserId) async {
    bool belongsToConversation(Map<String, dynamic> item) {
      final sender = field(item, ['sender_id']);
      final receiver = field(item, ['receiver_id']);
      return (sender == currentUserId && receiver == friendId) ||
          (sender == friendId && receiver == currentUserId);
    }
    await _mutate(_outboxKey, (items) =>
        items.where((item) => !belongsToConversation(item)).toList());
    await _mutate(_inboxKey, (items) =>
        items.where((item) => !belongsToConversation(item)).toList());
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
    final sdkInt = androidInfo.version.sdkInt;
    final requestedPermissions = barqNearbyPermissionNamesForAndroidSdk(
      sdkInt,
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
    if (barqNearbyRequiresLocationService(sdkInt)) {
      final locationServiceStatus = await Permission.location.serviceStatus;
      if (!locationServiceStatus.isEnabled) {
        throw Exception('شغّل خدمة الموقع في إعدادات الهاتف؛ مكتبة Nearby قد تحتاج تفعيلها لاكتشاف الأجهزة، ولا يتم جمع موقعك.');
      }
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

class BarqReplyPreview extends StatelessWidget {
  final String sender;
  final String preview;
  final VoidCallback? onClose;
  const BarqReplyPreview({
    super.key,
    required this.sender,
    required this.preview,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 3),
      padding: const EdgeInsets.fromLTRB(11, 7, 5, 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          right: BorderSide(color: scheme.primary, width: 3),
        ),
      ),
      child: Row(children: [
        Icon(Icons.reply_rounded, size: 17, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
          ],
        )),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
          tooltip: 'إلغاء الرد',
        ),
      ]),
    );
  }
}

Widget messageReactionBar({
  required BuildContext context,
  required Map<String, dynamic> message,
  required String currentUserId,
  required Future<void> Function(String emoji, bool remove) onReact,
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
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .16) : Theme.of(context).colorScheme.surfaceContainerHighest,
              label: Text('${entry.key} ${entry.value.length}', style: const TextStyle(fontSize: 11)),
              onPressed: () async {
                final alreadyReacted = entry.value.any(
                  (item) => field(item, ['user_id']) == currentUserId,
                );
                try {
                  await onReact(entry.key, alreadyReacted);
                } catch (error) {
                  if (context.mounted) showMsg(context, cleanError(error));
                }
              },
            ),
          ),
      ],
    ),
  );
}

Widget _barqMessageActionIcon(
  BuildContext context,
  IconData icon, {
  bool destructive = false,
}) {
  final theme = Theme.of(context);
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Icon(
      icon,
      size: 21,
      color: destructive ? theme.colorScheme.error : theme.colorScheme.onSurface,
    ),
  );
}

Future<void> showMessageActions(
  BuildContext context, {
  required Map<String, dynamic> message,
  required String currentUserId,
  required bool canDelete,
  required Future<void> Function() onDelete,
  bool canDeleteForMe = false,
  Future<void> Function()? onDeleteForMe,
  Future<void> Function(Map<String, dynamic> message)? onReply,
  Future<void> Function(String body)? onEdit,
  Future<void> Function(String emoji, bool remove)? onReact,
  Future<void> Function()? onPin,
  Future<void> Function()? onSaveMemory,
  Future<void> Function()? onForward,
  bool isPinned = false,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      Widget item({
        required String value,
        required IconData icon,
        required String label,
        bool destructive = false,
      }) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          minLeadingWidth: 48,
          leading: _barqMessageActionIcon(
            sheetContext,
            icon,
            destructive: destructive,
          ),
          title: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: destructive ? theme.colorScheme.error : theme.colorScheme.onSurface,
            ),
          ),
          onTap: () => Navigator.pop(sheetContext, value),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.bolt_rounded, color: theme.colorScheme.onSurface, size: 23),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'خيارات الرسالة',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      'برق',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onReact != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🔥'])
                        InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => Navigator.pop(sheetContext, 'emoji:$emoji'),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Text(emoji, style: const TextStyle(fontSize: 25)),
                          ),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => Navigator.pop(sheetContext, 'react'),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(Icons.add_rounded, color: theme.colorScheme.onSurfaceVariant, size: 25),
                        ),
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
              if (onReply != null)
                item(value: 'reply', icon: Icons.reply_rounded, label: 'الرد على الرسالة'),
              item(value: 'copy', icon: Icons.copy_all_outlined, label: 'نسخ الرسالة'),
              if (onForward != null)
                item(value: 'forward', icon: Icons.forward_rounded, label: 'تحويل الرسالة'),
              if (onEdit != null)
                item(value: 'edit', icon: Icons.edit_outlined, label: 'تعديل الرسالة'),
              if (onPin != null)
                item(
                  value: 'pin',
                  icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  label: isPinned ? 'إلغاء تثبيت الرسالة' : 'تثبيت الرسالة',
                ),
              if (onSaveMemory != null)
                item(value: 'save_memory', icon: Icons.bookmark_border_rounded, label: 'حفظ في الذكريات الخاصة'),
              if (canDeleteForMe && onDeleteForMe != null)
                item(value: 'delete_me', icon: Icons.visibility_off_outlined, label: 'حذف لدي فقط'),
              if (canDelete)
                item(
                  value: 'delete',
                  icon: Icons.delete_outline_rounded,
                  label: 'حذف لدى الجميع',
                  destructive: true,
                ),
            ],
          ),
        ),
      );
    },
  );
  if (action != null && action.startsWith('emoji:') && onReact != null) {
    final emoji = action.substring(6);
    final alreadyReacted = normalizeMessageReactions(message['reactions']).any((reaction) =>
      field(reaction, ['user_id']) == currentUserId && field(reaction, ['emoji']) == emoji);
    await onReact(emoji, alreadyReacted);
  } else if (action == 'react' && onReact != null && context.mounted) {
    final emoji = await showMessageReactionPicker(context);
    if (emoji != null) {
      final alreadyReacted = normalizeMessageReactions(message['reactions']).any((reaction) =>
        field(reaction, ['user_id']) == currentUserId && field(reaction, ['emoji']) == emoji);
      await onReact(emoji, alreadyReacted);
    }
  } else if (action == 'pin' && onPin != null) {
    await onPin();
  } else if (action == 'save_memory' && onSaveMemory != null) {
    await onSaveMemory();
  } else if (action == 'forward' && onForward != null) {
    await onForward();
  } else if (action == 'reply' && onReply != null) {
    await onReply(message);
  } else if (action == 'edit' && onEdit != null && context.mounted) {
    final attachmentForEdit = _attachmentData(message);
    final initial = attachmentForEdit == null
        ? field(message, ['body', 'content', 'message'])
        : field(attachmentForEdit, ['caption']);
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
  } else if (action == 'delete_me' && canDeleteForMe && onDeleteForMe != null && context.mounted) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الرسالة لدي فقط؟'),
        content: const Text('ستختفي الرسالة من حسابك فقط، وستبقى ظاهرة للطرف الآخر.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await onDeleteForMe();
        if (context.mounted) showMsg(context, 'تم حذف الرسالة من حسابك فقط');
      } catch (error) {
        if (context.mounted) showMsg(context, cleanError(error));
      }
    }
  } else if (action == 'delete' && canDelete && context.mounted) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('حذف الرسالة؟'),
        content: const Text('سيتم حذف الرسالة لدى الطرفين ولن تظهر في المحادثة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف لدى الجميع', style: TextStyle(color: Colors.redAccent)),
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

Future<void> forwardBarqMessage(BuildContext context, Map<String, dynamic> message) async {
  final body = field(message, ['body', 'content', 'message']).trim();
  final attachment = _attachmentData(message);
  if (body.isEmpty && attachment == null) {
    showMsg(context, 'لا يوجد محتوى قابل للتحويل في هذه الرسالة.');
    return;
  }
  try {
    final results = await Future.wait([Api.friends(), Api.groups()]);
    final contacts = results[0];
    final groups = results[1];
    if (!context.mounted) return;
    final target = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تحويل الرسالة إلى'),
        content: SizedBox(
          width: 360,
          height: 360,
          child: ListView(children: [
            if (contacts.isEmpty && groups.isEmpty)
              const ListTile(title: Text('لا توجد جهات اتصال أو مجموعات')),
            for (final person in contacts)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(field(person, ['display_name', 'displayName', 'username'], 'مستخدم برق')),
                subtitle: Text('@${field(person, ['username'])}'),
                onTap: () => Navigator.pop(dialogContext, {'type': 'person', 'id': field(person, ['id', 'user_id'])}),
              ),
            for (final group in groups)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                title: Text(field(group, ['name'], 'مجموعة')),
                onTap: () => Navigator.pop(dialogContext, {'type': 'group', 'id': field(group, ['id'])}),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء'))],
      ),
    );
    if (target == null || target['id'] == null || !context.mounted) return;
    if (body.isNotEmpty) {
      final forwarded = '↪ رسالة محوّلة\\n$body';
      if (target['type'] == 'group') {
        await Api.sendGroupMessage(target['id']!, forwarded);
      } else {
        await Api.sendMessage(target['id']!, forwarded);
      }
    }
    if (attachment != null) {
      final bytes = await Api.readAttachmentBytes(field(attachment, ['attachmentId']));
      await Api.uploadAttachment(
        bytes: bytes,
        fileName: field(attachment, ['fileName'], 'barq-forwarded-file'),
        contentType: field(attachment, ['contentType'], 'application/octet-stream'),
        recipientId: target['type'] == 'person' ? target['id'] : null,
        groupId: target['type'] == 'group' ? target['id'] : null,
      );
    }
    if (context.mounted) showMsg(context, 'تم تحويل الرسالة ومرفقاتها.');
  } catch (error) {
    if (context.mounted) showMsg(context, cleanError(error));
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
                    ? const Center(child: CircularProgressIndicator())
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

Future<List<Map<String, dynamic>>> loadBarqCachedMessages(String key) async {
  try {
    final raw = await storage.read(key: key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveBarqCachedMessages(
  String key,
  List<Map<String, dynamic>> messages,
) async {
  try {
    final snapshot = messages.length > 150
        ? messages.sublist(messages.length - 150)
        : messages;
    await storage.write(key: key, value: jsonEncode(snapshot));
  } catch (_) {
    // A cache write must never block message delivery or rendering.
  }
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
  final palette = BarqIdentityPalette.forIdentity(BarqIdentity.selected.value);
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
    backgroundColor: palette.surface,
    child: imageUrl.isEmpty
        ? Text(name.characters.first, style: TextStyle(color: palette.primary, fontSize: radius * 0.85))
        : ClipOval(
            child: Image.network(
              imageUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              headers: {'Authorization': 'Bearer ${Api.token}'},
              errorBuilder: (_, __, ___) => Center(
                child: Text(name.characters.first,
                    style: TextStyle(color: palette.primary, fontSize: radius * 0.85)),
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
        Text('تعذر تحميل ذكرياتك', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 18)),
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
        await SirajPush.loadCachedPreferences();
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
                await SirajPush.loadCachedPreferences();
                await SirajPush.register();
                if (!mounted) return;
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
        body: Center(child: CircularProgressIndicator()),
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
/// Stable private handle for compatibility with API gateways that require a username.
/// The phone remains the primary login identifier; the handle does not reveal the number.
String barqPrivateRegistrationUsername(String internationalPhone) {
  final normalized = normalizeBarqInternationalPhone(internationalPhone);
  final digest = crypto.sha256.convert(utf8.encode(normalized)).toString();
  return 'barq${digest.substring(0, 16)}';
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
  bool registering = false;
  bool busy = false;
  bool obscurePassword = true;
  String selectedCountryCode = '+967';
  static const List<(String, String)> countryCodes = barqCountryCodes;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    name.dispose(); username.dispose();
    phone.dispose(); password.dispose();
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
                                  trailing: Text(country.$2, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
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
          Text(selectedCountryCode, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
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
            )
          : await Api.login(username.text.trim(), password.text);
      if (registering) {
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
    fillColor: Theme.of(context).colorScheme.surface,
    labelStyle: const TextStyle(color: Colors.white70),
    prefixStyle: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: .09)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
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
    final identityPrimary = Theme.of(context).colorScheme.primary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topRight, end: Alignment.bottomLeft,
                colors: [Theme.of(context).colorScheme.surface, Theme.of(context).scaffoldBackgroundColor, Theme.of(context).scaffoldBackgroundColor],
              )),
            )),
            Positioned(top: -110, right: -70, child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: .10),
                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.secondary.withValues(alpha: .12), blurRadius: 90, spreadRadius: 20)]),
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
                            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .24), blurRadius: 28, spreadRadius: 2)],
                          ),
                          child: const Icon(Icons.bolt_rounded, color: Colors.black, size: 54),
                        )),
                        const SizedBox(height: 14),
                        Center(child: Text('بَرق', style: TextStyle(
                          color: identityPrimary, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 1,
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
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
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
                                    backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 15)),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
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

bool barqCanHandlePendingNotification({
  required bool initialRefreshComplete,
  required bool alreadyHandling,
  required bool hasSession,
}) => initialRefreshComplete && !alreadyHandling && hasSession;

bool barqHomeCanPop({required int selectedTab, required String conversationQuery}) =>
    selectedTab == 0 && conversationQuery.trim().isEmpty;

bool barqShouldPauseBackgroundWork(AppLifecycleState state) =>
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached;

class HomePage extends StatefulWidget {
  final Map<String, dynamic> user;
  const HomePage({super.key, required this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int selectedTab = 0;
  int selectedConversationSection = 0;
  String conversationQuery = '';
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
  bool initialRefreshComplete = false;
  Map<String, dynamic> privacySettings = {'searchable': true, 'readReceipts': true};
  Map<String, dynamic> notificationPrefs = {'messages': true, 'groups': true, 'statuses': true};
  Timer? offlineSyncTimer;
  bool _handlingNotificationTap = false;
  bool _refreshingAll = false;
  DateTime? _lastResumeRefreshAt;
  StreamSubscription<Uri>? _groupInviteLinkSubscription;
  final Set<String> _handledGroupInviteCodes = <String>{};
  StreamSubscription<Map<String, dynamic>>? _pushRefreshSubscription;
  bool _refreshAgain = false;

  String get myId => field(me, ['id', 'user_id']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    barqPendingNotificationTap.addListener(_handlePendingNotificationTap);
    _pushRefreshSubscription = SirajRealtime.instance.events.listen((event) {
      if (event['type'] == 'message' || event['type'] == 'group_message' || event['type'] == 'status_update') {
        unawaited(refreshAll());
      }
    });
    _initializeGroupInviteLinks();
    _syncRealtimeConnection();
    _loadCachedFriends().whenComplete(() { if (mounted) refreshAll(); });
    _startOfflineSyncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    barqPendingNotificationTap.removeListener(_handlePendingNotificationTap);
    _pushRefreshSubscription?.cancel();
    _groupInviteLinkSubscription?.cancel();
    offlineSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeGroupInviteLinks() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) unawaited(_handleGroupInviteLink(initial));
    } catch (_) {}
    _groupInviteLinkSubscription = links.uriLinkStream.listen((uri) {
      unawaited(_handleGroupInviteLink(uri));
    }, onError: (_) {});
  }

  Future<void> _handleGroupInviteLink(Uri uri) async {
    if (uri.scheme != 'barq' || uri.host != 'group' || uri.path != '/join') return;
    final code = (uri.queryParameters['code'] ?? '').trim();
    if (code.isEmpty || !_handledGroupInviteCodes.add(code) || !mounted) return;
    try {
      final joined = await Api.joinGroupInvite(code);
      await refreshAll();
      if (!mounted) return;
      setState(() => selectedTab = 3);
      final groupId = field(joined, ['groupId']);
      Map<String, dynamic>? target;
      for (final item in groups) {
        if (field(item, ['id', 'group_id']) == groupId) { target = item; break; }
      }
      showMsg(context, 'انضممت إلى مجموعة ${field(joined, ['groupName'], 'برق')} بنجاح.');
      if (target != null) {
        await Navigator.push<void>(context, MaterialPageRoute(
          builder: (_) => GroupChatPage(
            group: target!,
            currentUserId: myId,
            onAddMember: () => addMemberDialog(target!),
            onShareInvite: () => shareGroupInvite(target!),
            onGroupChanged: refreshAll,
          ),
        ));
      }
    } catch (error) {
      if (mounted) showMsg(context, 'تعذر الانضمام عبر الرابط: ${cleanError(error)}');
    }
  }

  Future<void> shareGroupInvite(Map<String, dynamic> group) async {
    try {
      final invite = await Api.createGroupInvite(field(group, ['id']));
      final link = field(invite, ['inviteUrl']);
      if (link.isEmpty) throw Exception('لم يتم إنشاء رابط الدعوة.');
      await SharePlus.instance.share(ShareParams(
        text: 'انضم إلى مجموعة "${field(group, ['name'], 'برق')}" على برق عبر الرابط التالي (صالح لمدة 7 أيام):\n$link',
        subject: 'دعوة للانضمام إلى مجموعة برق',
      ));
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    }
  }

  void _startOfflineSyncTimer() {
    offlineSyncTimer?.cancel();
    offlineSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      BarqOfflineQueue.syncOutbox();
    });
  }

  void _stopOfflineSyncTimer() {
    offlineSyncTimer?.cancel();
    offlineSyncTimer = null;
  }

  void _syncRealtimeConnection() {
    final token = Api.token;
    if (!barqRealtimeCanConnect(
      authToken: token,
      appResumed: true,
      socketUrl: SirajRealtime.socketUrl,
    )) {
      return;
    }
    unawaited(SirajRealtime.instance.start(token!));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startOfflineSyncTimer();
      unawaited(SirajPush.register());
      _syncRealtimeConnection();
      BarqOfflineQueue.syncOutbox();
      if (phoneContactsPermissionGranted) matchPhoneContacts(silent: true);
      final lastRefresh = _lastResumeRefreshAt;
      if (!_refreshingAll && (lastRefresh == null ||
          DateTime.now().difference(lastRefresh) > const Duration(seconds: 12))) {
        _lastResumeRefreshAt = DateTime.now();
        unawaited(refreshAll());
      }
    } else if (barqShouldPauseBackgroundWork(state)) {
      _stopOfflineSyncTimer();
      unawaited(SirajRealtime.instance.stop());
    }
  }

  Future<void> _handlePendingNotificationTap() async {
    if (!mounted ||
        !barqCanHandlePendingNotification(
          initialRefreshComplete: initialRefreshComplete,
          alreadyHandling: _handlingNotificationTap,
          hasSession: Api.token != null,
        )) {
      return;
    }
    final route = barqPendingNotificationTap.value;
    if (route == null) return;
    _handlingNotificationTap = true;
    barqPendingNotificationTap.value = null;
    try {
      switch (route['type']) {
        case 'direct_message':
          final senderId = route['senderId'];
          Map<String, dynamic>? friend;
          for (final item in friends) {
            final person = item['user'] is Map
                ? Map<String, dynamic>.from(item['user'])
                : item;
            if (field(person, ['id', 'user_id', 'friend_id']) == senderId) {
              friend = item;
              break;
            }
          }
          if (friend != null && mounted) {
            await Navigator.push<void>(context, MaterialPageRoute(
              builder: (_) => ChatPage(friend: friend!, currentUserId: myId),
            ));
          } else if (mounted) {
            setState(() => selectedTab = 0);
            showMsg(context, 'لا يمكن فتح هذه المحادثة حالياً؛ حدّث قائمة الأشخاص أولاً.');
          }
          break;
        case 'group_message':
          final groupId = route['groupId'];
          Map<String, dynamic>? group;
          for (final item in groups) {
            if (field(item, ['id', 'group_id']) == groupId) {
              group = item;
              break;
            }
          }
          if (mounted) setState(() => selectedTab = 3);
          if (group != null && mounted) {
            final targetGroup = group;
            await Navigator.push<void>(context, MaterialPageRoute(
              builder: (_) => GroupChatPage(
                group: targetGroup,
                currentUserId: myId,
                onAddMember: () => addMemberDialog(targetGroup),
                onShareInvite: () => shareGroupInvite(targetGroup),
                onGroupChanged: refreshAll,
              ),
            ));
          }
          break;
        case 'status_update':
          if (mounted) setState(() => selectedTab = 1);
          final statusId = route['statusId'];
          if (statusId != null && statusId.isNotEmpty) {
            Map<String, dynamic>? status;
            for (final item in statuses) {
              if (field(item, ['id']) == statusId) {
                status = item;
                break;
              }
            }
            if (status != null && mounted) _openSparkStatus(status);
          }
          break;
      }
    } catch (_) {
      if (mounted) showMsg(context, 'تعذر فتح وجهة الإشعار. يمكنك الوصول إليها من برق.');
    } finally {
      _handlingNotificationTap = false;
      if (mounted && barqPendingNotificationTap.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handlePendingNotificationTap();
        });
      }
    }
  }

  Future<void> _loadCachedFriends() async {
    try {
      final raw = await storage.read(key: 'barq_cached_friends');
      final cachedGroups = await storage.read(key: 'barq_cached_groups');
      final cachedStatuses = await storage.read(key: 'barq_cached_statuses');
      if (mounted) {
        setState(() {
          if (raw != null) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              friends = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
            }
          }
          if (cachedGroups != null) {
            final decoded = jsonDecode(cachedGroups);
            if (decoded is List) {
              groups = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
            }
          }
          if (cachedStatuses != null) {
            final decoded = jsonDecode(cachedStatuses);
            if (decoded is List) {
              statuses = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
            }
          }
        });
      }
    } catch (_) {
      // Cached data is optional; continue with the signed-in user and refresh online.
    } finally {
      // The authenticated user is already available from StartupPage. Show the
      // app shell immediately and hydrate the remaining tabs in the background.
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> refreshAll() async {
    if (_refreshingAll) {
      _refreshAgain = true;
      return;
    }
    _refreshingAll = true;
    _refreshAgain = false;
    try {
      // Independent home resources load concurrently; a slow endpoint no longer
      // serializes friends, groups, statuses and the rest of the home screen.
      await Future.wait<void>([
        () async {
          try {
            final value = await Api.friends();
            friends = value;
            unawaited(storage.write(key: 'barq_cached_friends', value: jsonEncode(value)));
          } catch (_) {}
        }(),
        () async {
          try {
            final value = await Api.me();
            me = value;
            unawaited(storage.write(key: 'barq_cached_user', value: jsonEncode(value)));
          } catch (_) {}
        }(),
        () async {
          try {
            final value = await Api.statuses();
            statuses = value;
            unawaited(storage.write(key: 'barq_cached_statuses', value: jsonEncode(value)));
          } catch (_) {}
        }(),
        () async {
          try { privacySettings = await Api.privacy(); } catch (_) {}
        }(),
        () async {
          try {
            notificationPrefs = await Api.notificationSettings();
            SirajPush.updatePreferences(notificationPrefs);
          } catch (_) {}
        }(),
        () async {
          try {
            final value = await Api.groups();
            groups = value;
            unawaited(storage.write(key: 'barq_cached_groups', value: jsonEncode(value)));
          } catch (_) {}
        }(),
        () async {
          try {
            memories = await Api.privateMemories();
            memoriesLoadFailed = false;
          } catch (_) {
            memoriesLoadFailed = true;
          }
        }(),
      ]);
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          initialRefreshComplete = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handlePendingNotificationTap();
        });
      }
      _refreshingAll = false;
      if (_refreshAgain && mounted) unawaited(refreshAll());
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
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom - 160)
                  .clamp(180.0, 520.0),
            ),
            child: SizedBox(
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
                    if (dialogContext.mounted) setDialog(() => busy = false);
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
                      if (dialogContext.mounted) setDialog(() => busy = false);
                    },
                    child: const Text('بحث'),
                  ),
                ),
                if (busy) const CircularProgressIndicator(),
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
          ),
          actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _chatsPage(),
      _statusesPage(),
      _friendsPage(),
      _accountPage(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: barqHomeCanPop(
          selectedTab: selectedTab,
          conversationQuery: conversationQuery,
        ),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || !mounted) return;
          setState(() {
            if (selectedTab != 0) {
              selectedTab = 0;
            } else {
              conversationQuery = '';
            }
          });
        },
        child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: .32),
                  ),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'برق',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    'تواصل بنبض الضوء',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .62),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(index: selectedTab, children: pages),
        floatingActionButton: selectedTab == 1 || selectedTab == 2
            ? FloatingActionButton(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: selectedTab == 1 ? publishStatusDialog : searchUsers,
                child: Icon(selectedTab == 1 ? Icons.add : Icons.person_add),
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
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'المحادثات',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'SPARK',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'جهات الاتصال',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'حسابي',
            ),
          ],
        ),
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
                  showMsg(context, 'تم نشر SPARK لمدة 24 ساعة.');
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
    final picked = await showBarqMediaPicker(
      pageContext, allowMultiple: true, title: 'اختيار وسائط SPARK',
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
              if (uploading) const LinearProgressIndicator(),
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
    // The viewer list is private: only the owner can request or see it.
    if (!mounted || myId.isEmpty) return;
    try {
      final viewers = await Api.sparkViewers(statusId);
      if (!mounted) return;
      final palette = Theme.of(context).colorScheme;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .68,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                  color: palette.onSurface.withValues(alpha: .24),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.visibility_rounded, color: palette.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مشاهدو SPARK',
                        style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text('قائمة خاصة لا يراها إلا صاحب SPARK',
                        style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: palette.onSurface.withValues(alpha: .62),
                        )),
                    ],
                  )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text('${viewers.length}',
                      style: TextStyle(color: palette.primary, fontWeight: FontWeight.w900)),
                  ),
                ]),
              ),
              Divider(height: 1, color: palette.outlineVariant.withValues(alpha: .5)),
              Expanded(
                child: viewers.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off_outlined, size: 42,
                            color: palette.onSurface.withValues(alpha: .38)),
                          const SizedBox(height: 10),
                          Text('لا توجد مشاهدات حتى الآن',
                            style: TextStyle(color: palette.onSurface.withValues(alpha: .68))),
                        ],
                      ))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: viewers.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1, indent: 58,
                          color: palette.outlineVariant.withValues(alpha: .35),
                        ),
                        itemBuilder: (_, index) {
                          final viewer = viewers[index];
                          final name = field(viewer, ['displayName', 'display_name', 'username'], 'مستخدم برق');
                          final viewedAt = field(viewer, ['viewedAt', 'viewed_at']);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            leading: CircleAvatar(
                              backgroundColor: palette.primary.withValues(alpha: .13),
                              child: Text(name.trim().isEmpty ? 'ب' : name.trim().substring(0, 1),
                                style: TextStyle(color: palette.primary, fontWeight: FontWeight.w800)),
                            ),
                            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(viewedAt.isEmpty ? 'شاهد SPARK' : viewedAt,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Icon(Icons.check_circle_rounded, size: 18,
                              color: palette.primary.withValues(alpha: .7)),
                          );
                        },
                      ),
              ),
            ]),
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
          authorId: field(status, ['userId', 'user_id']),
          currentUserId: myId,
          media: media,
          author: field(status, ['displayName', 'display_name', 'username'], 'مستخدم برق'),
          caption: field(status, ['content']),
          backgroundKey: field(status, ['backgroundKey', 'background_key'], 'midnight'),
          textColorKey: field(status, ['textColorKey', 'text_color_key'], 'white'),
          viewCount: int.tryParse((status['viewCount'] ?? 0).toString()) ?? 0,
          showViewCount: field(status, ['userId', 'user_id']) == myId,
          onShowViewers: () => _showSparkViewers(statusId),
          fontKey: field(status, ['fontKey', 'font_key'], 'modern'),
        ),
      ),
    );
  }


  Widget _statusesPage() {
    final palette = Theme.of(context).colorScheme;
    final ownStatuses = statuses.where((item) =>
      field(item, ['userId', 'user_id']) == myId).toList()
      ..sort((a, b) => field(b, ['createdAt', 'created_at']).compareTo(
        field(a, ['createdAt', 'created_at'])));
    final latestByUser = <String, Map<String, dynamic>>{};
    for (final status in statuses.where((item) =>
        field(item, ['userId', 'user_id']) != myId)) {
      final userId = field(status, ['userId', 'user_id']);
      final previous = latestByUser[userId];
      if (previous == null || field(status, ['createdAt', 'created_at']).compareTo(
          field(previous, ['createdAt', 'created_at'])) > 0) {
        latestByUser[userId] = status;
      }
    }
    final recentStatuses = latestByUser.values.toList()
      ..sort((a, b) => field(b, ['createdAt', 'created_at']).compareTo(
        field(a, ['createdAt', 'created_at'])));

    Widget avatar(Map<String, dynamic> status, {bool own = false}) {
      final photo = field(status, ['photoUrl', 'photo_url']);
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: own
                ? [palette.outlineVariant, palette.outlineVariant]
                : [palette.primary, gold, palette.secondary],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
          child: CircleAvatar(
            radius: 27,
            backgroundColor: palette.surfaceContainerHighest,
            backgroundImage: photo.isEmpty ? null : NetworkImage(
              '$apiBase$photo?v=${Uri.encodeComponent(field(status, ['photoUpdatedAt', 'photo_updated_at']))}',
              headers: {'Authorization': 'Bearer ${Api.token}'},
            ),
            child: photo.isEmpty
                ? Icon(Icons.person_rounded, color: palette.onSurfaceVariant, size: 27)
                : null,
          ),
        ),
      );
    }

    Widget statusRow(Map<String, dynamic> status) {
      final name = field(status, ['displayName', 'display_name', 'username'], 'مستخدم برق');
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: avatar(status),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(_messageTime(field(status, ['createdAt', 'created_at'])),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11)),
        onTap: () => _openSparkStatus(status),
      );
    }

    return RefreshIndicator(
      color: palette.primary,
      onRefresh: refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SPARK', style: TextStyle(
                  color: palette.primary, fontSize: 22, fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                )),
                Text('مساحة اللحظات والتحديثات', style: TextStyle(
                  color: palette.onSurfaceVariant, fontSize: 11,
                )),
              ],
            )),
            PopupMenuButton<String>(
              tooltip: 'نشر في SPARK',
              icon: Icon(Icons.camera_alt_outlined, color: palette.primary, size: 24),
              onSelected: (value) {
                if (value == 'text') publishStatusDialog();
                if (value == 'media') publishSparkMediaDialog();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'text', child: Text('نص في SPARK')),
                PopupMenuItem(value: 'media', child: Text('صورة أو فيديو')),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            leading: Stack(clipBehavior: Clip.none, children: [
              if (ownStatuses.isEmpty)
                CircleAvatar(
                  radius: 31,
                  backgroundColor: palette.surfaceContainerHighest,
                  child: Icon(Icons.person_rounded, color: palette.onSurfaceVariant, size: 30),
                )
              else
                avatar(ownStatuses.first, own: true),
              Positioned(
                bottom: -1, right: -2,
                child: Container(
                  width: 23, height: 23,
                  decoration: BoxDecoration(
                    color: palette.primary, shape: BoxShape.circle,
                    border: Border.all(color: palette.surface, width: 2),
                  ),
                  child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                ),
              ),
            ]),
            title: const Text('SPARK الخاص بي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text(
              ownStatuses.isEmpty ? 'اضغط لإضافة تحديث' : 'اضغط لعرض تحديثاتك',
              style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11),
            ),
            trailing: ownStatuses.isEmpty
                ? Icon(Icons.add_circle_outline_rounded, color: palette.primary)
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'مشاهدو SPARK',
                      onPressed: () => _showSparkViewers(field(ownStatuses.first, ['id'])),
                      icon: Icon(Icons.visibility_outlined, color: palette.primary),
                    ),
                    Text(field(ownStatuses.first, ['viewCount'], '0'),
                      style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11)),
                  ]),
            onTap: ownStatuses.isEmpty
                ? publishSparkMediaDialog
                : () => _openSparkStatus(ownStatuses.first),
          ),
          Divider(height: 1, color: palette.outlineVariant.withValues(alpha: .45)),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text('التحديثات الأخيرة',
              style: TextStyle(color: palette.primary, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          if (recentStatuses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(children: [
                Icon(Icons.auto_awesome_outlined, size: 40, color: palette.onSurfaceVariant),
                const SizedBox(height: 10),
                Text('لا توجد تحديثات جديدة',
                  style: TextStyle(color: palette.onSurface, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text('ستظهر هنا تحديثات SPARK من جهات اتصالك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11)),
              ]),
            )
          else
            for (final status in recentStatuses) statusRow(status),
        ],
      ),
    );
  }

  Widget _chatsPage() {
    final palette = Theme.of(context).colorScheme;
    final query = conversationQuery.trim().toLowerCase();
    final visibleFriends = friends.where((person) => query.isEmpty ||
      _personName(person).toLowerCase().contains(query) ||
      _personUsername(person).toLowerCase().contains(query) ||
      field(person, ['phone']).toLowerCase().contains(query)).toList();
    final visibleChats = visibleFriends.where((person) => person['chatHidden'] != true).toList();
    final visibleGroups = groups.where((group) => query.isEmpty ||
      field(group, ['name']).toLowerCase().contains(query) ||
      field(group, ['description']).toLowerCase().contains(query)).toList();

    Widget sectionChip({required int index, required IconData icon, required String label, required String count}) {
      final selected = selectedConversationSection == index;
      return Expanded(child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: Material(
          color: selected ? palette.primary.withValues(alpha: .15) : palette.surfaceContainerLow,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => setState(() => selectedConversationSection = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: selected ? palette.primary.withValues(alpha: .65) : palette.outline.withValues(alpha: .14)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 19, color: selected ? palette.primary : palette.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: selected ? palette.primary : palette.onSurface)),
                Text(count, style: TextStyle(fontSize: 9, color: palette.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      ));
    }

    Widget personRow(Map<String, dynamic> person) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ChatPage(friend: person, currentUserId: myId),
            )).then((_) { if (mounted) refreshAll(); }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(2.2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.primary.withValues(alpha: .55), width: 1.4),
                  ),
                  child: personAvatar(person),
                ),
                const SizedBox(width: 11),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_personName(person), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.onSurface, fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('@${_personUsername(person)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11)),
                  ],
                )),
                Icon(Icons.chat_bubble_rounded, color: palette.primary, size: 19),
                const SizedBox(width: 5),
              ]),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: palette.primary,
      onRefresh: refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المحادثات', style: TextStyle(
                color: palette.onSurface, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text('تواصل بنبض الضوء', style: TextStyle(
                color: palette.onSurfaceVariant, fontSize: 11)),
            ])),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.bolt_rounded, color: palette.primary, size: 23),
            ),
          ]),
          const SizedBox(height: 15),
          TextField(
            onChanged: (value) => setState(() => conversationQuery = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ابحث في المحادثات وجهات الاتصال والمجموعات...',
              prefixIcon: Icon(Icons.search_rounded, color: palette.primary),
              suffixIcon: conversationQuery.isEmpty ? null : IconButton(
                tooltip: 'مسح البحث', icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => conversationQuery = ''),
              ),
              filled: true,
              fillColor: palette.surfaceContainerHighest.withValues(alpha: .72),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            sectionChip(index: 0, icon: Icons.chat_bubble_outline_rounded,
              label: 'الدردشات', count: '${visibleChats.length}'),
            sectionChip(index: 1, icon: Icons.groups_rounded,
              label: 'المجموعات', count: '${groups.length}'),
            sectionChip(index: 2, icon: Icons.call_outlined,
              label: 'المكالمات', count: 'السجل'),
            sectionChip(index: 3, icon: Icons.contacts_outlined,
              label: 'الأشخاص', count: '${friends.length}'),
          ]),
          const SizedBox(height: 16),
          if (selectedConversationSection == 0 || selectedConversationSection == 3) ...[
            Row(children: [
              Text(selectedConversationSection == 0 ? 'كل المحادثات' : 'جهات الاتصال',
                style: TextStyle(color: palette.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (selectedConversationSection == 3)
                IconButton(
                  tooltip: 'البحث عن أشخاص',
                  onPressed: searchUsers,
                  icon: Icon(Icons.person_search_rounded, color: palette.primary),
                ),
            ]),
            if ((selectedConversationSection == 0 ? visibleChats : visibleFriends).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 16),
                child: Column(children: [
                  Icon(Icons.forum_outlined, size: 42, color: palette.primary.withValues(alpha: .7)),
                  const SizedBox(height: 10),
                  Text(query.isEmpty ? 'لا توجد محادثات بعد' : 'لا توجد نتائج مطابقة',
                    style: TextStyle(color: palette.onSurface, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(query.isEmpty ? 'ابدأ محادثة جديدة مع أحد أصدقائك.' : 'جرّب البحث باسم أو اسم مستخدم آخر.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11)),
                ]),
              )
            else
              for (final person in (selectedConversationSection == 0 ? visibleChats : visibleFriends))
                personRow(person),
          ] else if (selectedConversationSection == 1) ...[
            Row(children: [
              Expanded(child: Text('مجموعاتك', style: TextStyle(
                color: palette.onSurface, fontSize: 14, fontWeight: FontWeight.w900))),
              IconButton(
                tooltip: 'إنشاء مجموعة',
                onPressed: createGroupDialog,
                icon: Icon(Icons.group_add_rounded, color: palette.primary),
              ),
            ]),
            if (visibleGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  Icon(Icons.groups_rounded, size: 42, color: palette.primary),
                  const SizedBox(height: 9),
                  Text(query.isEmpty ? 'أنشئ مجموعتك الأولى' : 'لا توجد مجموعات مطابقة',
                    style: TextStyle(color: palette.onSurface, fontWeight: FontWeight.w800)),
                  Text('اجمع أصدقاءك في محادثة واحدة',
                    style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11)),
                  TextButton.icon(onPressed: createGroupDialog,
                    icon: const Icon(Icons.add_rounded), label: const Text('إنشاء مجموعة')),
                ]),
              )
            else
              for (final group in visibleGroups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Material(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(17),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      leading: CircleAvatar(
                        backgroundColor: palette.primary.withValues(alpha: .14),
                        child: Icon(Icons.groups_rounded, color: palette.primary),
                      ),
                      title: Text(field(group, ['name'], 'مجموعة'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      subtitle: Text('${field(group, ['description'], 'مجموعة برق')} • ${field(group, ['member_count'], '1')} أعضاء',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: palette.onSurfaceVariant)),
                      trailing: Icon(Icons.chevron_left_rounded, color: palette.primary),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => GroupChatPage(
                          group: group,
                          currentUserId: myId,
                          onAddMember: () => addMemberDialog(group),
                          onShareInvite: () => shareGroupInvite(group),
                          onGroupChanged: refreshAll,
                        ),
                      )),
                    ),
                  ),
                ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: palette.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.outline.withValues(alpha: .16)),
              ),
              child: Column(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: palette.primary.withValues(alpha: .14),
                  child: Icon(Icons.call_outlined, size: 28, color: palette.primary),
                ),
                const SizedBox(height: 12),
                Text('المكالمات', style: TextStyle(
                  color: palette.onSurface, fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                Text('سيظهر هنا سجل المكالمات الواردة والصادرة والفائتة عند ربط خدمة الاتصال.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.onSurfaceVariant, fontSize: 11, height: 1.5)),
              ]),
            ),
          ],
        ],
      ),
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

  Future<void> _inviteFriend() async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: barqInviteMessage,
        subject: 'دعوة لتجربة برق',
      ));
    } catch (error) {
      if (mounted) showMsg(context, 'تعذر فتح المشاركة: ${cleanError(error)}');
    }
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
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _inviteFriend,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('دعوة صديق لتنزيل برق'),
          ),
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
        scrollable: true,
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
    final existingMembers = await Api.groupMembers(field(group, ['id']));
    if (!mounted) return;
    final existingIds = existingMembers.map((item) => field(item, ['id', 'user_id'])).toSet();
    final contactCandidates = friends.map((item) {
      final nested = item['user'] is Map ? Map<String, dynamic>.from(item['user']) : item;
      return <String, dynamic>{...item, ...nested};
    }).where((item) {
      final id = field(item, ['id', 'user_id', 'friend_id']);
      return id.isNotEmpty && !existingIds.contains(id);
    }).toList();
    List<Map<String, dynamic>> found = List<Map<String, dynamic>>.from(contactCandidates);
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('إضافة عضو للمجموعة'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom - 150)
                  .clamp(180.0, 500.0),
            ),
            child: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: Text('من جهات اتصالك', style: TextStyle(
                  color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: busy ? null : () => setDialog(() => found = List<Map<String, dynamic>>.from(contactCandidates)),
                  icon: const Icon(Icons.contacts_outlined, size: 17),
                  label: const Text('جهات الاتصال'),
                ),
              ]),
              TextField(controller: controller, decoration: inputDecoration('البحث باسم المستخدم أو الهاتف', Icons.search)),
              Align(alignment: Alignment.centerLeft, child: TextButton(
                onPressed: busy ? null : () async {
                  if (controller.text.trim().length < 2) return;
                  setDialog(() => busy = true);
                  try { found = await Api.search(controller.text.trim()); }
                  catch (e) { if (mounted) showMsg(this.context, cleanError(e)); }
                  if (dialogContext.mounted) setDialog(() => busy = false);
                }, child: const Text('بحث'))),
              if (busy) const CircularProgressIndicator(),
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
          ),
          actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
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
            errorBuilder: (_, __, ___) => CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      }
    }
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Icon(
        field(memory, ['sourceType']) == 'message' ? Icons.chat_bubble_outline : Icons.auto_awesome,
        color: Theme.of(context).colorScheme.primary,
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
                  Text('احتفظ بلحظاتك المهمة هنا', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 18)),
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
                      Align(alignment: Alignment.centerRight, child: Text('الصور المحفوظة في هذه الذكرى', style: TextStyle(color: Theme.of(context).colorScheme.primary))),
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
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                        final result = await showBarqMediaPicker(
                          dialogContext,
                          allowMultiple: true,
                          title: 'اختيار صور للذكرى',
                          withData: false,
                          allowFiles: false,
                          requestType: RequestType.image,
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
                          if (contentType.isEmpty || file.path == null ||
                              file.size <= 0 || file.size > 4 * 1024 * 1024) {
                            error = 'كل صورة يجب أن تكون JPG أو PNG أو WebP وألا يتجاوز حجمها 4 ميجابايت.';
                            break;
                          }
                          selected.add({
                            'path': file.path,
                            'size': file.size,
                            'name': file.name,
                            'contentType': contentType,
                          });
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
                                  child: Image.file(
                                    File(photos[index]['path'] as String),
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
                                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                      const LinearProgressIndicator(),
                    ],
                    Align(alignment: Alignment.centerRight, child: Text('لا يراها سواك', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12))),
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

  Future<void> pickProfilePhoto() async {
    try {
      final result = await showBarqMediaPicker(
        context,
        allowMultiple: false,
        title: 'اختيار صورة الملف الشخصي',
        withData: false,
        allowFiles: false,
        requestType: RequestType.image,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = await readBarqPickedFileBytes(file);
      if (!mounted) return;
      if (bytes.isEmpty) {
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
      final photoPalette = Theme.of(context).colorScheme;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: photoPalette.surface,
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
                  style: TextStyle(color: photoPalette.onSurface.withValues(alpha: .72))),
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
      if (!mounted) return;
      if (accepted != true) return;
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
    final phoneController = TextEditingController(text: field(me, ['phone']));
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('تعديل الملف الشخصي'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              child: Column(
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
                readOnly: true,
                keyboardType: TextInputType.phone,
                decoration: inputDecoration('رقم الهاتف (ثابت بعد إنشاء الحساب)', Icons.phone_outlined)
                    .copyWith(
                      helperText: 'لا يمكن تغيير رقم الهاتف من الملف الشخصي.',
                      helperStyle: const TextStyle(color: Colors.white60),
                    ),
              ),
              const SizedBox(height: 6),
              const Text('اسم المستخدم ورقم الهاتف لا يتغيران من هذه الشاشة.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
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
                setDialog(() => saving = true);
                try {
                  final updated = await Api.updateProfile(
                    displayName: name,
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
              title: const Text('لحظات SPARK الجديدة'), value: statusesEnabled,
              onChanged: saving ? null : (v) => setDialog(() => statusesEnabled = v)),
            const SizedBox(height: 8),
            const Text('عند استخدام التطبيق تظهر تنبيهات مختصرة دون كشف نص الرسائل؛ وتُحترم تفضيلات الرسائل والمجموعات وSPARK.', style: TextStyle(color: Colors.white60, fontSize: 12)),
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
                  SirajPush.updatePreferences(saved);
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
    final username = field(me, ['username'], 'barq_user');
    final phone = field(me, ['phone'], 'غير مضاف');
    final palette = Theme.of(context).colorScheme;
    Widget sectionLabel(String value) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 8),
      child: Text(value, style: TextStyle(
        color: palette.primary, fontSize: 13, fontWeight: FontWeight.w700,
      )),
    );
    Widget item({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) => Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        leading: Icon(icon, color: palette.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: onTap,
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [palette.surface, Theme.of(context).scaffoldBackgroundColor],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.primary.withValues(alpha: .38)),
          ),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              CircleAvatar(
                radius: 43,
                backgroundColor: palette.surface,
                child: ClipOval(
                  child: field(me, ['photoUrl']).isNotEmpty
                      ? Image.network(
                          '$apiBase${field(me, ['photoUrl'])}?v=${Uri.encodeComponent(field(me, ['photoUpdatedAt']))}',
                          width: 86,
                          height: 86,
                          fit: BoxFit.cover,
                          headers: {if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'},
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(displayName.isNotEmpty ? displayName.characters.first : 'ب',
                                style: TextStyle(color: palette.primary, fontSize: 30)),
                          ),
                        )
                      : Center(
                          child: Text(displayName.isNotEmpty ? displayName.characters.first : 'ب',
                              style: TextStyle(color: palette.primary, fontSize: 30)),
                        ),
                ),
              ),
              Positioned(
                bottom: -3, right: -4,
                child: Material(
                  color: palette.primary, shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: pickProfilePhoto,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(displayName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            Text('@$username', style: TextStyle(color: palette.primary)),
            const SizedBox(height: 5),
            Text(phone, style: TextStyle(color: palette.onSurface.withValues(alpha: .68))),
          ]),
        ),
        sectionLabel('حسابك'),
        item(
          icon: Icons.edit_outlined,
          title: 'تعديل الملف الشخصي',
          subtitle: 'الصورة والاسم؛ رقم الهاتف ثابت بعد إنشاء الحساب',
          onTap: editProfileDialog,
        ),
        item(
          icon: Icons.auto_awesome_outlined,
          title: 'الذكريات الخاصة',
          subtitle: 'مساحتك الخاصة للصور والرسائل المحفوظة',
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('الذكريات الخاصة')),
              body: _memoriesPage(),
              floatingActionButton: FloatingActionButton(
                onPressed: _showPrivateMemoryDialog,
                child: const Icon(Icons.add),
              ),
            ),
          )),
        ),
        sectionLabel('إعدادات برق'),
        item(
          icon: Icons.palette_outlined,
          title: 'هوية برق وBARQ Touch',
          subtitle: 'البرق الأزرق، الفراشة، الظل البنفسجي، الجوهرة السماوية',
          onTap: () => _showBarqIdentityPicker(context),
        ),
        item(
          icon: Icons.lock_outline,
          title: 'الخصوصية والأمان',
          subtitle: 'الظهور في البحث وإشعارات قراءة الرسائل',
          onTap: privacySettingsDialog,
        ),
        item(
          icon: Icons.notifications_outlined,
          title: 'الإشعارات',
          subtitle: 'الرسائل الخاصة والمجموعات وSPARK',
          onTap: notificationSettingsDialog,
        ),
        item(
          icon: Icons.bluetooth_connected_rounded,
          title: 'الاتصال بالأجهزة القريبة',
          subtitle: 'إرسال الرسائل النصية للأصدقاء القريبين دون إنترنت عند توفر الاتصال',
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => NearbyDevicesPage(user: me, friends: friends),
          )),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 7),
          child: SwitchListTile(
            secondary: Icon(Icons.translate_rounded, color: palette.primary),
            title: const Text('الترجمة عربي / إنجليزي'),
            subtitle: const Text('ترجمة الرسائل على الجهاز عند تفعيلها'),
            value: BarqFeatures.autoTranslate,
            activeThumbColor: palette.primary,
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
        sectionLabel('عن التطبيق'),
        item(
          icon: Icons.info_outline,
          title: 'حول برق',
          subtitle: 'التواصل بنبض الضوء',
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'برق — BARQ',
            applicationVersion: 'نسخة اختبار',
            applicationLegalese: 'التواصل بنبض الضوء',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.error,
            side: BorderSide(color: palette.error.withValues(alpha: .65)),
          ),
          onPressed: () async {
            final confirmController = TextEditingController();
            final confirmedUsername = await showDialog<String>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('حذف حساب برق نهائياً؟'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('سيتم حذف حسابك ورسائلك ووسائطك وبياناتك المرتبطة به. لا يمكن التراجع عن هذا الإجراء.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'اكتب اسم المستخدم للتأكيد',
                      hintText: username,
                    ),
                  ),
                ]),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: palette.error),
                    onPressed: () => Navigator.pop(dialogContext, confirmController.text.trim()),
                    child: const Text('تأكيد الحذف'),
                  ),
                ],
              ),
            );
            confirmController.dispose();
            if (confirmedUsername == null || confirmedUsername.trim().isEmpty || !mounted) return;
            try {
              await Api.deleteAccount(confirmedUsername.trim());
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (_) => false,
              );
            } catch (error) {
              if (mounted) showMsg(context, cleanError(error));
            }
          },
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('حذف الحساب نهائياً'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Api.logout();
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }

  Future<void> _showBarqIdentityPicker(BuildContext context) async {
    var draftIdentity = BarqIdentity.selected.value;
    var saving = false;
    BarqIdentity? downloadingIdentity;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final draftPalette = BarqIdentityPalette.forIdentity(draftIdentity);
          return AlertDialog(
            title: const Text('اختر هوية برق'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.62,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: draftPalette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: draftPalette.primary.withValues(alpha: .65)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [draftPalette.primary, draftPalette.secondary]),
                          boxShadow: [BoxShadow(color: draftPalette.glow.withValues(alpha: .25), blurRadius: 12)],
                        ),
                        child: draftIdentity == BarqIdentity.butterfly
                          ? const Text('🦋', style: TextStyle(fontSize: 23))
                          : Icon(draftPalette.motif, color: draftPalette.onPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(BarqIdentity.label(draftIdentity),
                              style: TextStyle(color: draftPalette.text, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(draftPalette.tagline,
                              style: TextStyle(color: draftPalette.mutedText, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.visibility_outlined, color: draftPalette.primary),
                    ],
                  ),
                ),
                ...BarqIdentity.values.map((identity) {
                  final palette = BarqIdentityPalette.forIdentity(identity);
                  final isDraft = draftIdentity == identity;
                  final isAvailable = identity.isAvailable;
                  final isDownloading = downloadingIdentity == identity;
                  final isCurrent = BarqIdentity.selected.value == identity;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: saving || isDownloading ? null : () async {
                        if (!identity.isAvailable) {
                          if (Api.token == null) {
                            showMsg(dialogContext, 'سجّل الدخول أولاً لتنزيل الهوية.');
                            return;
                          }
                          setDialogState(() => downloadingIdentity = identity);
                          try {
                            await BarqIdentity.download(identity, apiBase: apiBase, token: Api.token!);
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              downloadingIdentity = null;
                              draftIdentity = identity;
                            });
                            showMsg(dialogContext, 'اكتمل تنزيل حزمة ${BarqIdentity.label(identity)}.');
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => downloadingIdentity = null);
                            showMsg(dialogContext, 'تعذر تنزيل الهوية: ${cleanError(e)}');
                          }
                        } else {
                          setDialogState(() => draftIdentity = identity);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDraft ? palette.primary : palette.border,
                            width: isDraft ? 2 : 1,
                          ),
                          color: palette.surface,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(colors: [palette.primary, palette.secondary]),
                              ),
                              child: identity == BarqIdentity.butterfly
                                ? const Text('🦋', style: TextStyle(fontSize: 23))
                                : Icon(palette.motif, color: palette.onPrimary, size: 23),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(BarqIdentity.label(identity),
                                    style: TextStyle(color: palette.text, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                    isDownloading ? 'جارٍ تنزيل الحزمة...' : (!isAvailable ? 'اضغط لتنزيل الحزمة ثم تفعيلها' : palette.tagline),
                                    style: TextStyle(color: palette.mutedText, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (isDownloading)
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            else if (!isAvailable)
                              Icon(Icons.download_for_offline_outlined, color: palette.mutedText, size: 19),
                            if (isCurrent && !isDraft)
                              Icon(Icons.check_circle_outline, color: palette.mutedText, size: 19),
                            if (isDraft)
                              Icon(Icons.radio_button_checked, color: palette.primary),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    await BarqIdentity.set(draftIdentity);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    if (dialogContext.mounted) {
                      setDialogState(() => saving = false);
                      showMsg(dialogContext, 'تعذر حفظ الهوية: ${cleanError(e)}');
                    }
                  }
                },
                child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('معاينة وتطبيق الهوية'),
              ),
            ],
          );
        },
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
    case 'mp4': case 'm4v': return 'video/mp4';
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
                          CircularProgressIndicator(),
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
  double _wavePhase = 0;
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
      _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (mounted && _stopwatch != null) {
          setState(() { _elapsed = _stopwatch!.elapsed; _wavePhase += .42; });
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.redAccent.withValues(alpha: .24)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fiber_manual_record_rounded, color: Colors.redAccent, size: 9),
              const SizedBox(width: 5),
              _BarqWaveform(phase: _wavePhase, color: Colors.redAccent, count: 18),
              const SizedBox(width: 6),
              Text(formatBarqMediaDuration(_elapsed),
                style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
              IconButton(
                tooltip: 'إلغاء التسجيل', visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                onPressed: _busy ? null : _cancelRecording,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 19),
              ),
              IconButton(
                tooltip: 'إرسال التسجيل الصوتي', visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                onPressed: _busy ? null : _toggleRecording,
                icon: _busy
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.redAccent, size: 19),
              ),
            ]),
          )
        else
          IconButton(
            tooltip: 'تسجيل رسالة صوتية',
            onPressed: _busy || widget.disabled ? null : _toggleRecording,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.mic_none_rounded, color: Theme.of(context).colorScheme.primary),
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
          style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
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
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9)),
                      child: Icon(Icons.link, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(uri.host, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
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
  final local = message['local_attachment'];
  if (local is Map) return Map<String, dynamic>.from(local);
  final raw = field(message, ['body', 'content', 'message']);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> && decoded['type'] == 'attachment') return decoded;
  } catch (_) {}
  return null;
}

Widget _barqAttachmentTile(Map<String, dynamic> attachment,
    Future<void> Function(void Function(double progress) onProgress) onDownload,
    {Future<void> Function()? onRetry}) {
  if (attachment['localBytes'] is Uint8List || attachment['localPreparing'] == true) {
    final bytes = attachment['localBytes'] is Uint8List
        ? attachment['localBytes'] as Uint8List : null;
    final preparing = attachment['localPreparing'] == true;
    final type = field(attachment, ['contentType']).toLowerCase();
    final failed = attachment['localUploadFailed'] == true;
    final raw = attachment['localUploadProgress'];
    final progress = raw is num ? raw.toDouble().clamp(0.0, 1.0) : 0.0;
    final isImage = type.startsWith('image/');
    final isVideo = type.startsWith('video/');
    final isAudio = type.startsWith('audio/');
    return Container(
      constraints: BoxConstraints(maxWidth: isImage || isVideo ? 250 : 260),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isImage || isVideo)
          Stack(alignment: Alignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: isImage
                  ? (bytes != null
                      ? Image.memory(bytes, width: 244, height: 176, fit: BoxFit.cover)
                      : attachment['localPath'] is String && (attachment['localPath'] as String).isNotEmpty
                          ? Image.file(File(attachment['localPath'] as String), width: 244, height: 176, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 244, height: 176, color: Colors.black45,
                                child: const Icon(Icons.image_outlined, color: Colors.white70, size: 42)))
                          : Container(width: 244, height: 176, color: Colors.black45,
                              child: const Icon(Icons.image_outlined, color: Colors.white70, size: 42)))
                  : attachment['localPath'] is String && (attachment['localPath'] as String).isNotEmpty
                      ? SizedBox(
                          width: 244, height: 150,
                          child: _BarqPickedVideoThumbnail(file: PlatformFile(
                            name: field(attachment, ['fileName'], 'barq-video'),
                            path: attachment['localPath'] as String,
                            size: bytes?.length ?? (attachment['size'] is int ? attachment['size'] as int : 0),
                          )),
                        )
                      : Container(width: 244, height: 150, color: Colors.black45,
                          child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 58)),
            ),
            Container(
              width: 58, height: 58,
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle,
                border: Border.all(color: Colors.white70)),
              child: Stack(alignment: Alignment.center, children: [
                if (!failed) SizedBox(width: 50, height: 50,
                  child: CircularProgressIndicator(value: progress > 0 ? progress : null,
                    strokeWidth: 2.5, color: Colors.white)),
                Icon(failed ? Icons.refresh_rounded : Icons.bolt_rounded,
                  color: Colors.white, size: 30),
              ]),
            ),
          ])
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 52, height: 52,
              child: Stack(alignment: Alignment.center, children: [
                if (!failed) CircularProgressIndicator(value: progress > 0 ? progress : null,
                  strokeWidth: 2.5, color: Colors.white),
                Icon(failed ? Icons.refresh_rounded : isAudio ? Icons.graphic_eq_rounded : Icons.bolt_rounded,
                  color: Colors.white, size: 27),
              ])),
            const SizedBox(width: 9),
            Flexible(child: Text(field(attachment, ['fileName'], 'مرفق'),
              style: const TextStyle(color: Colors.white), maxLines: 2,
              overflow: TextOverflow.ellipsis)),
          ]),
        if (isAudio) ...[
          const SizedBox(height: 4),
          const _BarqWaveform(phase: 0, color: Colors.white70, count: 25),
        ],
        if (field(attachment, ['caption']).isNotEmpty) ...[
          const SizedBox(height: 5),
          Align(alignment: AlignmentDirectional.centerStart,
            child: Text(field(attachment, ['caption']),
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3))),
        ],
        const SizedBox(height: 5),
        Row(children: [
          Expanded(child: Text(failed ? 'تعذر الإرسال — أعد المحاولة'
              : preparing ? 'جارٍ تجهيز الوسائط...'
              : progress > 0 ? 'جارٍ الإرسال ${(progress * 100).round()}%'
              : 'جارٍ الإرسال...', style: const TextStyle(color: Colors.white70, fontSize: 11))),
          if (failed && onRetry != null)
            IconButton(tooltip: 'إعادة المحاولة', visualDensity: VisualDensity.compact,
              onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, color: Colors.white)),
        ]),
      ]),
    );
  }
  return _attachmentTile(attachment, onDownload);
}

Future<bool> showBarqAttachmentPreview(
  BuildContext context, {
  required String fileName,
  required String contentType,
  required Uint8List bytes,
  TextEditingController? captionController,
}) async {
  final type = contentType.toLowerCase();
  final isImage = type.startsWith('image/');
  final isVideo = type.startsWith('video/');
  final isAudio = type.startsWith('audio/');
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(Icons.bolt_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('معاينة قبل الإرسال',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(dialogContext, false),
                    icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 10),
                if (isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(bytes, height: 220, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 120,
                        child: Center(child: Icon(Icons.broken_image_outlined, size: 42)))),
                  )
                else
                  Container(
                    height: 132,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(14)),
                    child: Center(child: Icon(
                      isVideo ? Icons.play_circle_outline_rounded
                        : isAudio ? Icons.graphic_eq_rounded
                        : Icons.insert_drive_file_outlined,
                      size: 54, color: scheme.primary)),
                  ),
                const SizedBox(height: 12),
                Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                if (isImage || isVideo) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: captionController,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: 'أضف تعليقاً...',
                      counterText: '',
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text('${(bytes.length / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('إرسال'))),
                ]),
              ],
            ),
          ),
        ),
      );
    },
  );
  return accepted == true;
}

class _BarqWaveform extends StatelessWidget {
  final double phase;
  final Color color;
  final int count;
  const _BarqWaveform({required this.phase, required this.color, this.count = 23});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(count, (index) {
        final envelope = .28 + .72 * math.sin((index + 1) * .47).abs();
        final pulse = .35 + .65 * math.sin(phase + index * .58).abs();
        final height = 5 + 22 * envelope * pulse;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          width: 2.6,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .48 + .5 * pulse),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}

Widget _attachmentTile(
  Map<String, dynamic> attachment,
  Future<void> Function(void Function(double progress) onProgress) onDownload,
) => _AttachmentTile(attachment: attachment, onDownload: onDownload);

class _AttachmentTile extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final Future<void> Function(void Function(double progress) onProgress) onDownload;

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
  bool _downloadLoading = false;
  double _downloadProgress = 0;
  String? _downloadError;
  String? _audioError;

  Future<void> _download() async {
    if (_downloadLoading) return;
    setState(() {
      _downloadLoading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });
    try {
      await widget.onDownload((progress) {
        if (mounted) setState(() => _downloadProgress = progress.clamp(0.0, 1.0));
      });
      if (mounted) showMsg(context, 'اكتمل تنزيل الملف.');
    } catch (error) {
      if (mounted) {
        setState(() => _downloadError = cleanError(error));
        showMsg(context, _downloadError!);
      }
    } finally {
      if (mounted) setState(() => _downloadLoading = false);
    }
  }

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
      builder: (_) => _BarqMediaViewer(
        imageBytes: bytes,
        title: field(widget.attachment, ['fileName'], 'صورة'),
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
      builder: (_) => _BarqMediaViewer(
        attachment: widget.attachment,
        title: field(widget.attachment, ['fileName'], 'فيديو'),
      ),
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
    final caption = field(widget.attachment, ['caption']);
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
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(snapshot.data!, width: 244, height: 176, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 244, height: 176, child: Icon(Icons.broken_image_outlined))),
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
          return SizedBox(width: _isImage ? 244 : 76, height: _isImage ? 176 : 76,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        },
      );
    } else if (_isAudio) {
      final audioAccent = Theme.of(context).colorScheme.primary;
      leading = Tooltip(
        message: _audioPlaying ? 'إيقاف مؤقت' : 'تشغيل التسجيل الصوتي',
        child: InkWell(
          onTap: _audioLoading ? null : _toggleAudio,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: audioAccent.withValues(alpha: .16),
                    shape: BoxShape.circle,
                    border: Border.all(color: audioAccent.withValues(alpha: .62), width: 1.3),
                  ),
                  child: Center(
                    child: _audioLoading
                        ? SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: audioAccent))
                        : Icon(
                            _audioPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 27,
                            color: audioAccent,
                          ),
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: audioAccent, width: 1),
                    ),
                    child: Icon(Icons.bolt_rounded, size: 12, color: audioAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (_isVideo) {
      leading = _BarqRemoteVideoThumbnail(
        attachment: widget.attachment,
        onTap: _openVideo,
      );
    } else {
      leading = Icon(icon, size: 28);
    }

    return Container(
      constraints: BoxConstraints(maxWidth: _isImage ? 250 : 260),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isImage) ...[
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                leading,
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: Material(
                    color: Colors.black.withValues(alpha: .58),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _downloadLoading ? null : _download,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _downloadLoading
                            ? SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: _downloadProgress > 0 ? _downloadProgress : null,
                                  color: Colors.white,
                                ))
                            : const Icon(Icons.download_rounded, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ] else
            Row(mainAxisSize: MainAxisSize.min, children: [
              leading,
              const SizedBox(width: 9),
              Flexible(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              IconButton(onPressed: _downloadLoading ? null : _download, icon: _downloadLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), tooltip: 'تنزيل الملف'),
            ]),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(caption, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
          ],
          if (_downloadLoading) ...[
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null)),
              const SizedBox(width: 8),
              Text(_downloadProgress > 0 ? '${(_downloadProgress * 100).round()}%' : 'جارٍ التنزيل',
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
            ]),
          ],
          if (_downloadError != null && !_downloadLoading)
            TextButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('إعادة تنزيل الملف'),
            ),
          if (_isAudio) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _BarqWaveform(
                phase: _audioPosition.inMilliseconds / 135,
                color: Theme.of(context).colorScheme.primary,
                count: 23,
              ),
            ),
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
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: .24),
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

class _BarqRemoteVideoThumbnail extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final VoidCallback onTap;
  const _BarqRemoteVideoThumbnail({required this.attachment, required this.onTap});

  @override
  State<_BarqRemoteVideoThumbnail> createState() => _BarqRemoteVideoThumbnailState();
}

class _BarqRemoteVideoThumbnailState extends State<_BarqRemoteVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_loading) return;
    if (mounted) setState(() { _loading = true; _failed = false; });
    final id = field(widget.attachment, ['attachmentId']);
    if (id.isEmpty) {
      if (mounted) setState(() { _failed = true; _loading = false; });
      return;
    }
    final headers = {if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'};
    final bases = <String>[apiBase, if (mediaWorkerBase != apiBase) mediaWorkerBase];
    for (final base in bases) {
      VideoPlayerController? controller;
      try {
        controller = VideoPlayerController.networkUrl(
          Uri.parse('$base/api/media/${Uri.encodeComponent(id)}'),
          httpHeaders: headers,
        );
        await controller.initialize().timeout(const Duration(seconds: 35));
        await controller.setVolume(0);
        await controller.pause();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() { _controller = controller; _loading = false; });
        return;
      } catch (_) {
        await controller?.dispose();
      }
    }
    if (mounted) setState(() { _failed = true; _loading = false; });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (controller != null)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                )
              else
                ColoredBox(
                  color: Colors.white.withValues(alpha: .06),
                  child: Center(
                    child: _failed
                        ? IconButton(
                            tooltip: 'إعادة تحميل معاينة الفيديو',
                            onPressed: _initialize,
                            icon: const Icon(Icons.refresh_rounded, size: 30),
                          )
                        : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              const Center(
                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarqMediaViewer extends StatefulWidget {
  final Map<String, dynamic>? attachment;
  final Uint8List? imageBytes;
  final File? videoFile;
  final String title;

  const _BarqMediaViewer({
    this.attachment,
    this.imageBytes,
    this.videoFile,
    required this.title,
  }) : assert(attachment != null || imageBytes != null || videoFile != null);

  @override
  State<_BarqMediaViewer> createState() => _BarqMediaViewerState();
}

class _BarqMediaViewerState extends State<_BarqMediaViewer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _lastIsPlaying = false;
  String? _error;

  void _onVideoChanged() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _lastIsPlaying && mounted) {
      _lastIsPlaying = playing;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.attachment != null || widget.videoFile != null) {
      _loading = true;
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    if (widget.videoFile != null) {
      VideoPlayerController? localController;
      try {
        localController = VideoPlayerController.file(widget.videoFile!);
        await localController.initialize().timeout(const Duration(seconds: 30));
        if (!mounted) {
          await localController.dispose();
          return;
        }
        await localController.setLooping(false);
        _controller = localController;
        _lastIsPlaying = localController.value.isPlaying;
        localController.addListener(_onVideoChanged);
        setState(() {
          _loading = false;
          _error = null;
        });
      } catch (error) {
        await localController?.dispose();
        if (mounted) {
          setState(() {
            _loading = false;
            _error = cleanError(error);
          });
        }
      }
      return;
    }
    final attachment = widget.attachment;
    final id = attachment == null ? '' : field(attachment, ['attachmentId']);
    if (id.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'معرّف الفيديو غير متوفر.';
        });
      }
      return;
    }
    final headers = {if (Api.token != null) 'Authorization': 'Bearer ${Api.token}'};
    final bases = <String>[apiBase, if (mediaWorkerBase != apiBase) mediaWorkerBase];
    Object? lastError;
    for (final base in bases) {
      VideoPlayerController? candidate;
      try {
        candidate = VideoPlayerController.networkUrl(
          Uri.parse('$base/api/media/${Uri.encodeComponent(id)}'),
          httpHeaders: headers,
        );
        await candidate.initialize().timeout(const Duration(minutes: 2));
        if (!mounted) {
          await candidate.dispose();
          return;
        }
        await candidate.setLooping(false);
        _controller = candidate;
        _lastIsPlaying = candidate.value.isPlaying;
        candidate.addListener(_onVideoChanged);
        setState(() {
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
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isImage = widget.imageBytes != null;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق العارض',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
            if (isImage)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * .78,
                  maxWidth: MediaQuery.of(context).size.width,
                ),
                child: InteractiveViewer(
                  minScale: .7,
                  maxScale: 5,
                  child: Image.memory(
                    widget.imageBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 56,
                    ),
                  ),
                ),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
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
                        colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
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
          SelectableText(token, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3)),
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
          Text('الأجهزة المتصلة (${connected.length})', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          if (connected.isEmpty) const ListTile(title: Text('لا توجد أجهزة متصلة بعد.')),
          ...connected.map((entry) => ListTile(leading: const Icon(Icons.link), title: Text(_friendName(entry.value)), subtitle: const Text('متصل وجاهز للرسائل النصية'))),
          const SizedBox(height: 12),
          Text('الأصدقاء القريبون (${discovered.length})', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
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
  final List<BarqConversationTool> conversationTools;

  const PublicProfilePage({
    super.key,
    required this.person,
    required this.currentUserId,
    this.canMessage = false,
    this.conversationTools = const [],
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
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.75), width: 2),
                  boxShadow: [
                    BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18), blurRadius: 24),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: imageUrl.isEmpty
                      ? Text(name.characters.first, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 48))
                      : ClipOval(
                          child: Image.network(
                            imageUrl,
                            width: 124,
                            height: 124,
                            fit: BoxFit.cover,
                            headers: {'Authorization': 'Bearer ${Api.token}'},
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(name.characters.first,
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 48)),
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
            if (conversationTools.isNotEmpty) ...[
              const SizedBox(height: 18),
              Card(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ListTile(
                      leading: Icon(Icons.tune_rounded),
                      title: Text('إعدادات المحادثة'),
                      subtitle: Text('الأدوات والخيارات الخاصة بهذه المحادثة'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    for (final tool in conversationTools)
                      ListTile(
                        leading: Icon(tool.icon),
                        title: Text(tool.title),
                        subtitle: Text(tool.subtitle,
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        onTap: () {
                          Navigator.pop(context);
                          tool.onTap();
                        },
                      ),
                  ],
                ),
              ),
            ],
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
                  backgroundColor: Theme.of(context).colorScheme.primary,
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

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final Map<String, String> translatedMessages = {};
  final Set<String> translatingMessageIds = {};
  final Map<String, DateTime> translationRetryAfter = {};
  final Map<String, String> voiceTranscripts = {};
  final Set<String> transcribingMessageIds = {};
  bool loading = true;
  bool sending = false;
  double? mediaUploadProgress;
  bool refreshing = false;
  bool ephemeralMode = false;
  bool blockedByMe = false;
  bool hasOlderMessages = false;
  bool loadingOlderMessages = false;
  final ScrollController messagesScrollController = ScrollController();
  bool _autoOlderArmed = false;
  Color? chatWallpaperColor;
  bool chatToolsExpanded = false;
  Map<String, dynamic>? olderMessageCursor;
  Map<String, dynamic>? replyToMessage;
  double _replySwipeDistance = 0;
  Timer? refreshTimer;
  Timer? _ephemeralExpiryTimer;
  StreamSubscription<Map<String, dynamic>>? realtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? nearbySubscription;

  Map<String, dynamic> get person =>
      widget.friend['user'] is Map
          ? Map<String, dynamic>.from(widget.friend['user'])
          : widget.friend;

  String get friendId => field(person, ['id', 'user_id', 'friend_id']);
  String get _messageCacheKey => 'barq_private_messages_${widget.currentUserId}_$friendId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    messagesScrollController.addListener(_maybeLoadOlderMessages);
    loadMessages();
    _loadBlockState();
    _loadChatWallpaper();
    nearbySubscription = BarqNearbyService.instance.events.listen((event) {
      if (event['type'] == 'message_received' && event['senderId'] == friendId) {
        loadMessages(silent: true);
      }
    });
    realtimeSubscription = SirajRealtime.instance.events.listen((event) {
      if (barqRealtimeMessageMatchesConversation(event, friendId)) {
        loadMessages(silent: true);
      }
    });
    // مزامنة الرسائل عبر REST/Vercel كل 3 ثوانٍ أثناء ظهور التطبيق فقط.
    _startRefreshTimer();
  }

  Future<void> _loadBlockState() async {
    try {
      final blocked = await Api.blockedUsers();
      if (!mounted) return;
      setState(() => blockedByMe = blocked.any(
        (item) => field(item, ['userId', 'user_id']) == friendId,
      ));
    } catch (_) {}
  }

  Future<void> _toggleBlockState() async {
    final shouldBlock = !blockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(shouldBlock ? 'حظر المستخدم؟' : 'إلغاء الحظر؟'),
        content: Text(shouldBlock
          ? 'لن تتمكن أنت وهذا المستخدم من تبادل الرسائل الخاصة أثناء تفعيل الحظر.'
          : 'سيُسمح مجدداً بالتواصل الخاص بينكما.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(shouldBlock ? 'حظر' : 'إلغاء الحظر')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (shouldBlock) {
        await Api.blockUser(friendId);
        if (!mounted) return;
        setState(() => blockedByMe = true);
        showMsg(context, 'تم حظر المستخدم.');
        Navigator.pop(context);
      } else {
        await Api.unblockUser(friendId);
        if (!mounted) return;
        setState(() => blockedByMe = false);
        showMsg(context, 'تم إلغاء الحظر.');
        await loadMessages(silent: true);
      }
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  Future<void> _clearConversationHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مسح سجل المحادثة؟'),
        content: const Text('سيُمسح سجل الرسائل من حسابك فقط. ستبقى جهة الاتصال والمحادثة في قائمتك، ولن تتأثر نسخة الطرف الآخر.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مسح السجل')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopRefreshTimer();
    try {
      await Api.clearPrivateConversation(friendId);
      await BarqOfflineQueue.clearConversation(friendId, widget.currentUserId);
      await storage.delete(key: _messageCacheKey);
      if (!mounted) return;
      setState(() {
        messages = [];
        olderMessageCursor = null;
        hasOlderMessages = false;
        replyToMessage = null;
      });
      showMsg(context, 'تم مسح سجل المحادثة من حسابك فقط.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) _startRefreshTimer();
    }
  }

  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المحادثة؟'),
        content: const Text('ستختفي المحادثة ورسائلها من قائمتك وحسابك فقط. ستبقى جهة الاتصال، ولن تُحذف الرسائل من حساب الطرف الآخر. عند وصول رسالة جديدة ستظهر المحادثة مجدداً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف المحادثة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopRefreshTimer();
    try {
      await Api.deletePrivateConversation(friendId);
      await BarqOfflineQueue.clearConversation(friendId, widget.currentUserId);
      await storage.delete(key: _messageCacheKey);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) _startRefreshTimer();
    }
  }

  void _startRefreshTimer() {
    refreshTimer?.cancel();
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !sending && !refreshing) loadMessages(silent: true);
    });
  }

  void _stopRefreshTimer() {
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      if (!refreshing) loadMessages(silent: true);
    } else if (barqShouldPauseBackgroundWork(state)) {
      _stopRefreshTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    _ephemeralExpiryTimer?.cancel();
    realtimeSubscription?.cancel();
    nearbySubscription?.cancel();
    messagesScrollController.dispose();
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
      if (!silent && messages.isEmpty) {
        final cached = await loadBarqCachedMessages(_messageCacheKey);
        if (cached.isNotEmpty && mounted) {
          setState(() {
            messages = filterExpiredEphemeralMessages(cached);
            loading = false;
          });
          _scheduleEphemeralExpiry();
        }
      }
      // Flush pending sends without holding up the first visible server page.
      unawaited(BarqOfflineQueue.syncOutbox());
      final pageFuture = Api.messagesPage(friendId);
      final temporaryFuture = Api.ephemeralMessages(friendId)
          .catchError((_) => <Map<String, dynamic>>[]);
      final page = await pageFuture;
      final data = Api._list(page['messages']);
      await BarqOfflineQueue.reconcile(data);
      final localPending = await BarqOfflineQueue.conversation(friendId, widget.currentUserId);
      // Fetch ephemeral and regular messages concurrently to reduce chat-open latency.
      final temporary = await temporaryFuture;
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
        unawaited(saveBarqCachedMessages(_messageCacheKey, messages));
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

  void _maybeLoadOlderMessages() {
    if (!messagesScrollController.hasClients) return;
    final position = messagesScrollController.position;
    if (position.pixels > 120) {
      _autoOlderArmed = true;
      return;
    }
    if (_autoOlderArmed &&
        position.userScrollDirection == ScrollDirection.forward &&
        hasOlderMessages && !loadingOlderMessages) {
      _autoOlderArmed = false;
      unawaited(loadOlderMessages());
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
    if (blockedByMe) {
      showMsg(context, 'ألغِ حظر المستخدم أولاً لإرسال الرسائل.');
      return;
    }
    final text = controller.text.trim();
    if (text.isEmpty) return;
    if (!isBarqMessageTextAllowed(text)) {
      showMsg(context, 'الرسالة طويلة جدًا؛ الحد الأقصى 5000 حرف.');
      return;
    }
    if (ephemeralMode && replyToMessage != null) {
      showMsg(context, 'الرسائل المؤقتة لا تدعم الرد على رسالة أخرى. ألغِ الرد أولاً.');
      return;
    }
    // حرر حقل الكتابة فور الضغط، ولا تنتظر الشبكة.
    final replySnapshot = replyToMessage == null ? null : Map<String, dynamic>.from(replyToMessage!);
    controller.clear();
    if (mounted) setState(() => replyToMessage = null);
    final messageId = ephemeralMode ? null : newBarqMessageId();
    final localMessage = messageId == null ? null : <String, dynamic>{
      'id': messageId,
      'sender_id': widget.currentUserId,
      'receiver_id': friendId,
      'body': text,
      if (replySnapshot != null) 'reply_to_id': field(replySnapshot, ['id', 'message_id']),
      if (replySnapshot != null) 'reply_to_body': field(replySnapshot, ['body', 'content', 'message']),
      if (replySnapshot != null) 'reply_to_sender_id': field(replySnapshot, ['sender_id']),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_sending': true,
    };
    if (localMessage != null && mounted) {
      setState(() => messages = mergeMessages(messages, [localMessage]));
    }
    setState(() => sending = true);
    try {
      if (ephemeralMode) {
        await Api.sendEphemeralMessage(friendId, text);
      } else {
        try {
          await Api.sendMessage(friendId, text, clientMessageId: messageId,
            replyToId: replySnapshot == null ? null : field(replySnapshot, ['id', 'message_id']));
        } catch (e) {
          if (!e.toString().contains('NETWORK_DIAGNOSTIC')) rethrow;
          final localMessage = {
            'id': messageId,
            'sender_id': widget.currentUserId,
            'receiver_id': friendId,
            'body': text,
            if (replySnapshot != null) 'reply_to_id': field(replySnapshot, ['id', 'message_id']),
            if (replySnapshot != null) 'reply_to_body': field(replySnapshot, ['body', 'content', 'message']),
            if (replySnapshot != null) 'reply_to_sender_id': field(replySnapshot, ['sender_id']),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          };
          await BarqOfflineQueue.enqueueOutgoing(localMessage);
          var deliveredNearby = false;
          try {
            if (replySnapshot == null && messageId != null) {
              deliveredNearby = await BarqNearbyService.instance.sendTextMessage(
                receiverId: friendId, messageId: messageId, body: text, senderId: widget.currentUserId,
              );
            }
          } catch (_) {}
          if (mounted) {
            setState(() => messages = mergeMessages(messages, [{...localMessage, 'is_sending': false, 'is_offline_pending': true}]));
            showMsg(context, deliveredNearby
                ? 'أُرسلت الرسالة عبر الاتصال القريب، وستُزامن مع الخادم عند عودة الإنترنت.'
                : replySnapshot != null
                    ? 'تم حفظ الرد محليًا وسيُرسل مع الاقتباس عند عودة الإنترنت.'
                    : 'حُفظت الرسالة محليًا. افتح الأجهزة القريبة لتسليمها الآن، وستُزامن تلقائيًا عند عودة الإنترنت.');
          }
          controller.clear();
          if (mounted) setState(() => replyToMessage = null);
          return;
        }
      }
      if (localMessage != null && mounted) {
        setState(() => messages = messages.map((item) => item['id'] == messageId
          ? {...item, 'is_sending': false} : item).toList());
      }
      await loadMessages(silent: true);
    } catch (e) {
      if (messageId != null && mounted) {
        setState(() => messages.removeWhere((item) => item['id'] == messageId));
      }
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Map<String, dynamic> _newPendingAttachment(Uint8List bytes, String fileName, String contentType, {Duration? duration, String? localPath}) => {
    'id': newBarqMessageId(), 'sender_id': widget.currentUserId, 'receiver_id': friendId,
    'body': '', 'created_at': DateTime.now().toUtc().toIso8601String(), 'is_sending': true,
    'local_attachment': {'type':'attachment','fileName':fileName,'contentType':contentType,
      'size':bytes.length,'localBytes':bytes,'localUploadProgress':0.0,
      if (duration != null) 'duration': duration.inMilliseconds,
      if (localPath != null && localPath.isNotEmpty) 'localPath': localPath},
  };

  Future<void> _uploadPendingAttachment(Map<String, dynamic> message) async {
    final attachment = message['local_attachment'];
    if (attachment is! Map<String, dynamic> || attachment['localBytes'] is! Uint8List) return;
    final id = field(message, ['id']);
    if (mounted) setState(() { attachment['localUploadFailed'] = false; attachment['localUploadProgress'] = 0.0; });
    try {
      await Api.uploadAttachment(
        bytes: attachment['localBytes'] as Uint8List,
        fileName: field(attachment, ['fileName'], 'barq-file'),
        contentType: field(attachment, ['contentType'], 'application/octet-stream'),
        recipientId: friendId,
        caption: field(attachment, ['caption']),
        onProgress: (value) { if (mounted) setState(() => attachment['localUploadProgress'] = value); },
      );
      if (mounted) setState(() => messages.removeWhere((item) => field(item, ['id']) == id));
      await loadMessages(silent: true);
    } catch (error) {
      if (mounted) {
        setState(() { attachment['localUploadFailed'] = true; message['is_sending'] = false; });
        showMsg(context, cleanError(error));
      }
    }
  }

  Future<void> _sendVoiceRecording(List<int> bytes, Duration duration) async {
    if (blockedByMe) { showMsg(context, 'ألغِ حظر المستخدم أولاً لإرسال الرسائل.'); return; }
    final local = _newPendingAttachment(Uint8List.fromList(bytes),
      'barq_voice_${DateTime.now().millisecondsSinceEpoch}.m4a', 'audio/mp4',
      duration: duration);
    if (mounted) setState(() => messages = mergeMessages(messages, [local]));
    unawaited(_uploadPendingAttachment(local));
  }

  Future<void> pickAndSendMedia() async {
    if (blockedByMe) { showMsg(context, 'ألغِ حظر المستخدم أولاً لإرسال الرسائل.'); return; }
    try {
      final result = await showBarqMediaPicker(
        context, allowMultiple: false, title: 'اختيار صورة أو فيديو',
        withData: false, allowFiles: false, requestType: RequestType.common,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final contentType = file.extension == null ? 'application/octet-stream' : _mimeForExtension(file.extension!);
      if (!mounted) return;
      final caption = controller.text.trim();
      final local = <String, dynamic>{
        'id': newBarqMessageId(), 'sender_id': widget.currentUserId, 'receiver_id': friendId,
        'body': '', 'created_at': DateTime.now().toUtc().toIso8601String(), 'is_sending': true,
        'local_attachment': <String, dynamic>{
          'type': 'attachment', 'fileName': file.name, 'contentType': contentType,
          'size': file.size, 'localPath': file.path, 'localUploadProgress': 0.0,
          'localPreparing': true, 'caption': caption,
        },
      };
      controller.clear();
      setState(() => messages = mergeMessages(messages, [local]));
      Uint8List bytes;
      try {
        bytes = Uint8List.fromList(await readBarqPickedFileBytes(file));
      } catch (_) {
        if (mounted) setState(() => messages.removeWhere((item) => field(item, ['id']) == field(local, ['id'])));
        rethrow;
      }
      if (!mounted) return;
      final attachment = local['local_attachment'] as Map<String, dynamic>;
      setState(() {
        attachment['localBytes'] = bytes;
        attachment['size'] = bytes.length;
        attachment['localPreparing'] = false;
      });
      unawaited(_uploadPendingAttachment(local));
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    }
  }

  Future<void> pickAndSendFile() async {
    if (blockedByMe) { showMsg(context, 'ألغِ حظر المستخدم أولاً لإرسال الرسائل.'); return; }
    try {
      final result = await showBarqMediaPicker(context, allowMultiple: false,
        title: 'إرسال وسائط أو ملف', withData: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final contentType = file.extension == null ? 'application/octet-stream' : _mimeForExtension(file.extension!);
      if (!mounted) return;
      final caption = controller.text.trim();
      final local = <String, dynamic>{
        'id': newBarqMessageId(), 'sender_id': widget.currentUserId, 'receiver_id': friendId,
        'body': '', 'created_at': DateTime.now().toUtc().toIso8601String(), 'is_sending': true,
        'local_attachment': <String, dynamic>{
          'type': 'attachment', 'fileName': file.name, 'contentType': contentType,
          'size': file.size, 'localPath': file.path, 'localUploadProgress': 0.0,
          'localPreparing': true, 'caption': caption,
        },
      };
      controller.clear();
      setState(() => messages = mergeMessages(messages, [local]));
      Uint8List bytes;
      try {
        bytes = Uint8List.fromList(await readBarqPickedFileBytes(file));
      } catch (_) {
        if (mounted) setState(() => messages.removeWhere((item) => field(item, ['id']) == field(local, ['id'])));
        rethrow;
      }
      if (!mounted) return;
      final attachment = local['local_attachment'] as Map<String, dynamic>;
      setState(() {
        attachment['localBytes'] = bytes;
        attachment['size'] = bytes.length;
        attachment['localPreparing'] = false;
      });
      unawaited(_uploadPendingAttachment(local));
    } catch (error) { if (mounted) showMsg(context, cleanError(error)); }
  }

  Future<void> _loadChatWallpaper() async {
    try {
      final saved = await storage.read(key: 'barq_chat_wallpaper_$friendId');
      final value = saved == null ? null : int.tryParse(saved);
      if (value != null && mounted) setState(() => chatWallpaperColor = Color(value));
    } catch (_) {}
  }

  Future<void> _chooseChatWallpaper() async {
    final selected = await showBarqWallpaperPicker(context, chatWallpaperColor);
    if (selected != null && mounted) {
      setState(() => chatWallpaperColor = selected == Colors.transparent ? null : selected);
      final key = 'barq_chat_wallpaper_$friendId';
      if (selected == Colors.transparent) {
        await storage.delete(key: key);
      } else {
        await storage.write(key: key, value: selected.toARGB32().toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = field(person, ['displayName', 'display_name', 'name', 'username'], 'محادثة');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: chatWallpaperColor ?? Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PublicProfilePage(
                person: widget.friend,
                currentUserId: widget.currentUserId,
                canMessage: true,
                conversationTools: [
                  BarqConversationTool(icon: Icons.wallpaper_outlined, title: 'خلفية المحادثة', subtitle: 'تخصيص مظهر هذه المحادثة', onTap: _chooseChatWallpaper),
                  BarqConversationTool(icon: Icons.delete_outline_rounded, title: 'حذف المحادثة', subtitle: 'حذفها من حسابك فقط مع إبقاء جهة الاتصال', onTap: _deleteConversation),
                  BarqConversationTool(icon: blockedByMe ? Icons.lock_open_rounded : Icons.block_rounded, title: blockedByMe ? 'إلغاء حظر المستخدم' : 'حظر المستخدم', subtitle: blockedByMe ? 'السماح بالتواصل الخاص مجدداً' : 'منع الرسائل الخاصة بينكما', onTap: _toggleBlockState),
                  BarqConversationTool(icon: Icons.push_pin_outlined, title: 'الرسائل المثبتة (${messages.where((message) => message['is_pinned'] == true).length})', subtitle: 'عرض المثبتة ضمن الرسائل المحمّلة', onTap: () => showBarqMessageCollectionDialog(context, title: 'الرسائل المثبتة', messages: messages, attachmentsOnly: false)),
                  BarqConversationTool(icon: Icons.perm_media_outlined, title: 'الوسائط والملفات (${messages.where((message) => _attachmentData(message) != null).length})', subtitle: 'عرض المرفقات ضمن الرسائل المحمّلة', onTap: () => showBarqMessageCollectionDialog(context, title: 'الوسائط والملفات', messages: messages, attachmentsOnly: true)),
                ],
              ),
            )),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              personAvatar(widget.friend, radius: 17),
              const SizedBox(width: 9),
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),

            ]),
          ),
          actions: [
            IconButton(
              tooltip: chatToolsExpanded ? 'إخفاء أدوات المحادثة' : 'إظهار أدوات المحادثة',
              onPressed: () => setState(() => chatToolsExpanded = !chatToolsExpanded),
              icon: Icon(chatToolsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded),
            ),
          ],
          bottom: chatToolsExpanded
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: SizedBox(
                    height: 52,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: Row(children: [
                        ActionChip(
                          avatar: const Icon(Icons.search_rounded, size: 17),
                          label: const Text('بحث'),
                          onPressed: () => showConversationSearch(context, (query, before) =>
                            Api.searchPrivateMessages(friendId, query, before: before)),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
                          label: const Text('ملخص'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => BarqConversationSummaryDialog(
                              loadSummary: () => Api.summarizePrivateConversation(friendId),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.push_pin_outlined, size: 17),
                          label: const Text('المثبتة'),
                          onPressed: () => showBarqMessageCollectionDialog(
                            context,
                            title: 'الرسائل المثبتة',
                            messages: messages,
                            attachmentsOnly: false,
                          ),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.perm_media_outlined, size: 17),
                          label: const Text('الوسائط'),
                          onPressed: () => showBarqMessageCollectionDialog(
                            context,
                            title: 'الوسائط والملفات',
                            messages: messages,
                            attachmentsOnly: true,
                          ),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.wallpaper_outlined, size: 17),
                          label: const Text('الخلفية'),
                          onPressed: _chooseChatWallpaper,
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.cleaning_services_outlined, size: 17),
                          label: const Text('مسح السجل'),
                          onPressed: _clearConversationHistory,
                        ),
                      ]),
                    ),
                  ),
                )
              : null,
        ),
        body: Container(
          decoration: barqChatWallpaperDecoration(context, chatWallpaperColor),
          child: Column(
          children: [
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                      ? const Center(child: Text('لا توجد رسائل بعد. ابدأ المحادثة.', style: TextStyle(color: Colors.white60)))
                      : ListView.builder(
                           controller: messagesScrollController,
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
                            final sparkReply = parseBarqSparkPrivateReply(field(m, ['body', 'content', 'message']));
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 280),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomLeft,
                                    colors: mine
                                        ? [
                                            const Color(0xFF0757B8).withValues(alpha: .96),
                                            const Color(0xFF063B82).withValues(alpha: .96),
                                          ]
                                        : [
                                            const Color(0xFF18253D).withValues(alpha: .97),
                                            const Color(0xFF111D32).withValues(alpha: .97),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(mine ? 18 : 5),
                                    bottomRight: Radius.circular(mine ? 5 : 18),
                                  ),
                                  border: Border.all(
                                    color: mine
                                        ? Theme.of(context).colorScheme.primary.withValues(alpha: .24)
                                        : Theme.of(context).colorScheme.outline.withValues(alpha: .12),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: mine
                                          ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
                                          : Colors.black.withValues(alpha: .08),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (m['is_pinned'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 5),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.push_pin_rounded,
                                            size: 12, color: Theme.of(context).colorScheme.secondary),
                                          const SizedBox(width: 4),
                                          Text('رسالة مثبتة', style: TextStyle(
                                            color: Theme.of(context).colorScheme.secondary,
                                            fontSize: 10, fontWeight: FontWeight.w700)),
                                        ]),
                                      ),
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
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 5),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const Icon(Icons.timer_outlined, size: 13),
                                          const SizedBox(width: 4),
                                          Text('رسالة مؤقتة', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10)),
                                        ]),
                                      ),
                                    if (field(m, ['reply_to_id']).isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(bottom: 7),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8),
                                          border: Border(right: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3))),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(field(m, ['reply_to_sender_id']) == widget.currentUserId ? 'رد على رسالتك' : 'رد على رسالة',
                                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                                          Text(messageReplyPreview(m), maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                        ]),
                                      ),
                                    if (_attachmentData(m) case final attachment?) ...[
                                      GestureDetector(
                                        onHorizontalDragStart: (_) => _replySwipeDistance = 0,
                                        onHorizontalDragUpdate: (details) => _replySwipeDistance += details.delta.dx,
                                        onHorizontalDragEnd: (details) {
                                          final swiped = _replySwipeDistance.abs() > 48 ||
                                              (details.primaryVelocity ?? 0).abs() > 260;
                                          _replySwipeDistance = 0;
                                          if (swiped && m['is_ephemeral'] != true) {
                                            setState(() => replyToMessage = Map<String, dynamic>.from(m));
                                          }
                                        },
                                        onDoubleTap: () async {
                                          if (m['is_ephemeral'] == true || m['is_offline_pending'] == true) return;
                                          try {
                                            await Api.reactPrivateMessage(field(m, ['id', 'message_id']), '❤️');
                                            if (mounted) await loadMessages(silent: true);
                                          } catch (error) {
                                            if (mounted) showMsg(context, cleanError(error));
                                          }
                                        },
                                        onLongPress: () => showMessageActions(
                                          context,
                                          message: m,
                                          currentUserId: widget.currentUserId,
                                          canDelete: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                          canDeleteForMe: m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                          onDeleteForMe: () async {
                                            await Api.hidePrivateMessageForMe(field(m, ['id', 'message_id']));
                                            if (mounted) await loadMessages();
                                          },
                                          onDelete: () async {
                                            await Api.deletePrivateMessage(field(m, ['id', 'message_id']));
                                            if (mounted) await loadMessages();
                                          },
                                          onReply: (message) async {
                                            setState(() => replyToMessage = Map<String, dynamic>.from(message));
                                          },
                                          onForward: _attachmentData(m) != null
                                              ? () => forwardBarqMessage(context, m) : null,
                                          onEdit: mine && _attachmentData(m) != null &&
                                                  m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                              ? (caption) async {
                                                  final updated = {..._attachmentData(m)!, 'caption': caption};
                                                  await Api.editPrivateMessage(
                                                    field(m, ['id', 'message_id']), jsonEncode(updated));
                                                  if (mounted) await loadMessages();
                                                }
                                              : null,
                                          onReact: (emoji, remove) async {
                                            await Api.reactPrivateMessage(field(m, ['id', 'message_id']), emoji, remove: remove);
                                            if (mounted) await loadMessages(silent: true);
                                          },
                                          onPin: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                              ? () async {
                                                  await Api.pinPrivateMessage(field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
                                                  if (mounted) await loadMessages(silent: true);
                                                } : null,
                                          isPinned: m['is_pinned'] == true,
                                        ),
                                        child: _barqAttachmentTile(attachment, (onProgress) => Api.downloadAttachment(
                                          attachmentId: field(attachment, ['attachmentId']),
                                          fileName: field(attachment, ['fileName'], 'attachment'),
                                          onProgress: onProgress,
                                        ), onRetry: attachment['localBytes'] is Uint8List ? () => _uploadPendingAttachment(m) : null),
                                      ),
                                      if (field(attachment, ['contentType']).startsWith('audio/') && field(attachment, ['attachmentId']).isNotEmpty)
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
                                        onHorizontalDragStart: (_) => _replySwipeDistance = 0,
                                        onHorizontalDragUpdate: (details) => _replySwipeDistance += details.delta.dx,
                                        onHorizontalDragEnd: (details) {
                                          final shouldReply = _replySwipeDistance.abs() > 48 ||
                                              (details.primaryVelocity ?? 0).abs() > 260;
                                          _replySwipeDistance = 0;
                                          if (shouldReply && m['is_ephemeral'] != true) {
                                            setState(() => replyToMessage = Map<String, dynamic>.from(m));
                                          }
                                        },
                                        onDoubleTap: () async {
                                          if (m['is_ephemeral'] == true || m['is_offline_pending'] == true) return;
                                          try {
                                            await Api.reactPrivateMessage(field(m, ['id', 'message_id']), '❤️');
                                            if (mounted) await loadMessages(silent: true);
                                          } catch (error) {
                                            if (mounted) showMsg(context, cleanError(error));
                                          }
                                        },
                                        onLongPress: () => showMessageActions(
                                          context,
                                          message: m,
                                          currentUserId: widget.currentUserId,
                                          canDelete: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                          canDeleteForMe: m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                          onDeleteForMe: () async {
                                            await Api.hidePrivateMessageForMe(field(m, ['id', 'message_id']));
                                            if (mounted) await loadMessages();
                                          },
                                          onDelete: () async {
                                            await Api.deletePrivateMessage(field(m, ['id', 'message_id']));
                                            if (mounted) await loadMessages();
                                          },
                                          onReply: (message) async {
                                            setState(() => replyToMessage = Map<String, dynamic>.from(message));
                                          },
                                          onForward: field(m, ['body', 'content', 'message']).trim().isNotEmpty || _attachmentData(m) != null
                                              ? () => forwardBarqMessage(context, m) : null,
                                          onEdit: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true && _attachmentData(m) == null
                                              ? (body) async {
                                                  await Api.editPrivateMessage(field(m, ['id', 'message_id']), body);
                                                  if (mounted) await loadMessages();
                                                }
                                              : null,
                                          onReact: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                              ? (emoji, remove) async {
                                                  await Api.reactPrivateMessage(field(m, ['id', 'message_id']), emoji, remove: remove);
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
                                        child: sparkReply == null
                                            ? BarqMessageBody(text: field(m, ['body', 'content', 'message']))
                                            : Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: gold.withValues(alpha: .10),
                                                  borderRadius: BorderRadius.circular(11),
                                                  border: Border.all(color: gold.withValues(alpha: .32)),
                                                ),
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  const Row(children: [
                                                    Icon(Icons.auto_awesome_rounded, size: 14, color: gold),
                                                    SizedBox(width: 6),
                                                    Text('رد على SPARK', style: TextStyle(
                                                      color: gold, fontSize: 11, fontWeight: FontWeight.w800,
                                                    )),
                                                  ]),
                                                  const SizedBox(height: 6),
                                                  Text(sparkReply['caption'] ?? '', maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                                  const Divider(height: 14, color: Colors.white24),
                                                  Text(sparkReply['reply'] ?? '',
                                                    style: const TextStyle(fontSize: 13, height: 1.4)),
                                                ]),
                                              ),
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
                                        if (mine && m['is_offline_pending'] != true) ...[
                                          const SizedBox(width: 5),
                                          if (m['is_sending'] == true) ...[
                                            const SizedBox(width: 10, height: 10,
                                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70)),
                                            const SizedBox(width: 3),
                                            const Text('جارٍ الإرسال', style: TextStyle(fontSize: 9, color: Colors.white60)),
                                          ] else ...[
                                            Icon(
                                              field(m, ['read_at', 'readAt']).isNotEmpty ? Icons.done_all_rounded : Icons.done_rounded,
                                              size: 13,
                                              color: field(m, ['read_at', 'readAt']).isNotEmpty
                                                  ? Theme.of(context).colorScheme.primary
                                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: .62),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              field(m, ['read_at', 'readAt']).isNotEmpty ? 'تمت المشاهدة' : 'تم الإرسال',
                                              style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .62)),
                                            ),
                                          ],
                                        ],
                                        if (field(m, ['edited_at', 'editedAt']).isNotEmpty)
                                          Text('تم التعديل', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .54))),
                                      ],
                                    ),
                                    if (m['is_pinned'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const Icon(Icons.push_pin, size: 12),
                                          const SizedBox(width: 3),
                                          Text('مثبتة', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10)),
                                        ]),
                                      ),
                                    if (m['is_ephemeral'] != true && m['is_offline_pending'] != true)
                                      messageReactionBar(
                                        context: context,
                                        message: m,
                                        currentUserId: widget.currentUserId,
                                        onReact: (emoji, remove) async {
                                          await Api.reactPrivateMessage(
                                            field(m, ['id', 'message_id']), emoji, remove: remove,
                                          );
                                          if (mounted) await loadMessages(silent: true);
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            if (mediaUploadProgress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                child: Row(children: [
                  Expanded(child: LinearProgressIndicator(
                    value: mediaUploadProgress! <= 0 ? null : mediaUploadProgress!.clamp(0.0, 1.0),
                  )),
                  const SizedBox(width: 10),
                  Text(mediaUploadProgress! <= 0
                      ? 'جارٍ رفع المرفق'
                      : 'رفع المرفق ${(mediaUploadProgress! * 100).round()}%',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
              ),
            if (replyToMessage != null)
              BarqReplyPreview(
                sender: field(replyToMessage!, ['display_name', 'username', 'sender_name'], 'رسالة مقتبسة'),
                preview: messageReplyPreview(replyToMessage!),
                onClose: sending ? null : () => setState(() => replyToMessage = null),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 5, 9, 9),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071326).withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .38)),
                    boxShadow: [
                      BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .10), blurRadius: 18),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: sending ? null : () => setState(() {
                          ephemeralMode = !ephemeralMode;
                          replyToMessage = null;
                        }),
                        icon: Icon(Icons.timer_outlined,
                          color: ephemeralMode ? Theme.of(context).colorScheme.primary : Colors.white70),
                        tooltip: ephemeralMode ? 'إيقاف الرسائل المؤقتة' : 'إرسال رسالة تختفي بعد قراءتها',
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'إضافة رمز تعبيري',
                        onPressed: sending ? null : () => insertBarqChatEmoji(controller),
                        icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: ephemeralMode ? 'رسالة مؤقتة...' : 'اكتب رسالة أو تعليق الوسائط...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                          ),
                          onSubmitted: (_) => send(),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'إرفاق صورة أو ملف',
                        onPressed: sending ? null : pickAndSendFile,
                        icon: const Icon(Icons.attach_file_rounded, color: Colors.white70),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'اختيار صورة أو فيديو',
                        onPressed: sending ? null : pickAndSendMedia,
                        icon: const Icon(Icons.photo_library_outlined, color: Colors.white70),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          if (value.text.trim().isEmpty && !sending && !ephemeralMode) {
                            return BarqVoiceRecordButton(disabled: sending, onSend: _sendVoiceRecording);
                          }
                          return SizedBox(
                            width: 42,
                            height: 42,
                            child: IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              ),
                              onPressed: send,
                              icon: const Icon(Icons.send_rounded),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        )),
      ),
    );
  }

}


class SparkMediaViewer extends StatefulWidget {
  final String statusId;
  final String authorId;
  final String currentUserId;
  final List<Map<String, dynamic>> media;
  final String author;
  final String caption;
  final String backgroundKey;
  final String textColorKey;
  final String fontKey;
  final int viewCount;
  final bool showViewCount;
  final Future<void> Function()? onShowViewers;
  const SparkMediaViewer({
    super.key, required this.statusId, required this.authorId, required this.currentUserId, required this.media, required this.author, required this.caption,
    this.backgroundKey = 'midnight', this.textColorKey = 'white', this.fontKey = 'modern',
    this.viewCount = 0, this.showViewCount = false, this.onShowViewers,
  });

  @override
  State<SparkMediaViewer> createState() => _SparkMediaViewerState();
}

class _SparkMediaViewerState extends State<SparkMediaViewer> {
  final TextEditingController _replyController = TextEditingController();
  bool _sendingReply = false;
  int _currentMediaIndex = 0;
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
  }

  Future<void> _react(String emoji) async {
    final canReply = widget.authorId.isNotEmpty && widget.authorId != widget.currentUserId;
    if (!canReply) return;
    try {
      await Api.reactSparkStatus(widget.statusId, emoji);
      if (mounted) showMsg(context, 'تم إرسال تفاعلك.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    }
  }

  Future<void> _sendReply() async {
    if (widget.authorId.isEmpty || widget.authorId == widget.currentUserId) return;
    final value = _replyController.text.trim();
    if (value.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    try {
      if (widget.authorId.isEmpty || widget.authorId == widget.currentUserId) {
        throw Exception('تعذر تحديد صاحب SPARK لإرسال الرد إلى محادثته.');
      }
      await Api.sendMessage(widget.authorId, barqSparkPrivateReplyMessage(
        caption: widget.caption,
        reply: value,
      ));
      _replyController.clear();
      if (mounted) showMsg(context, 'وصل ردك إلى المحادثة الخاصة مع صاحب SPARK.');
    } catch (e) {
      if (mounted) showMsg(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _toggleAudioReplyRecording() async {
    if (widget.authorId.isEmpty || widget.authorId == widget.currentUserId) return;
    if (_uploadingAudioReply) return;
    if (_recordingAudioReply) {
      await _finishAudioReplyRecording();
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
      if (widget.authorId.isEmpty || widget.authorId == widget.currentUserId) {
        throw Exception('لا يمكن إرسال رد صوتي إلى هذه اللحظة.');
      }
      // The attachment upload creates the private-chat message itself.
      // Sending a separate text message here caused duplicate/orphan replies.
      await Api.uploadAttachment(
        bytes: bytes,
        fileName: 'barq_spark_reply_${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
        recipientId: widget.authorId,
        caption: barqSparkPrivateReplyMessage(
          caption: widget.caption,
          reply: '🎙️ رد صوتي على SPARK',
        ),
      );
      if (mounted) showMsg(context, 'وصل ردك الصوتي إلى المحادثة الخاصة مع صاحب SPARK.');
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
    final canReply = widget.authorId.isNotEmpty && widget.authorId != widget.currentUserId;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          if (widget.media.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 5),
              child: Row(children: List.generate(widget.media.length, (index) =>
                Expanded(child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: index < _currentMediaIndex ? 1 : index == _currentMediaIndex ? .45 : 0,
                    child: DecoratedBox(decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(4),
                    )),
                  ),
                ))),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(children: [
              IconButton(
                tooltip: 'إغلاق SPARK',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              CircleAvatar(
                radius: 17,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .22),
                child: Text(widget.author.trim().isEmpty ? 'ب' : widget.author.trim().substring(0, 1),
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(widget.author,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
              if (widget.showViewCount &&
                  widget.authorId.isNotEmpty &&
                  widget.authorId == widget.currentUserId &&
                  widget.onShowViewers != null)
                TextButton.icon(
                  onPressed: widget.onShowViewers,
                  icon: const Icon(Icons.visibility_outlined, size: 18, color: Colors.white),
                  label: Text('${widget.viewCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
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
                    onPageChanged: (index) => setState(() => _currentMediaIndex = index),
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
                                  : const Center(child: CircularProgressIndicator()),
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
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: .2)))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (canReply) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in ['❤️', '🔥', '😂', '👍', '😍'])
                      Material(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _sendingReply ? null : () => _react(emoji),
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Text(emoji, style: const TextStyle(fontSize: 21)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                if (_recordingAudioReply)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text('جارٍ التسجيل ${_recordingClock(_recordingSeconds)} / 01:00',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ),
                Container(
                  padding: const EdgeInsetsDirectional.only(start: 7, end: 6, top: 5, bottom: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .58),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: gold.withValues(alpha: .72), width: 1.15),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: .13),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: .13),
                      ),
                      child: Icon(Icons.bolt_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 21),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: 'اكتب ردك على SPARK...',
                          counterText: '',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                    IconButton(
                      tooltip: _recordingAudioReply ? 'إيقاف وإرسال الرد الصوتي' : 'تسجيل رد صوتي',
                      visualDensity: VisualDensity.compact,
                      onPressed: _uploadingAudioReply ? null : _toggleAudioReplyRecording,
                      icon: _uploadingAudioReply
                          ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_recordingAudioReply ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                              color: _recordingAudioReply ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                              size: 21),
                    ),
                    Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sendingReply ? null : _sendReply,
                        child: SizedBox(
                          width: 42, height: 42,
                          child: Center(
                            child: _sendingReply
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.visibility_rounded, color: gold, size: 17),
                    const SizedBox(width: 7),
                    Text(
                      'اضغط على عدد المشاهدات لمعرفة من شاهد SPARK',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 11),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
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
    if (!_controller.value.isInitialized) return const Center(child: CircularProgressIndicator());
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
  final VoidCallback onShareInvite;
  final Future<void> Function() onGroupChanged;
  const GroupChatPage({
    super.key,
    required this.group,
    required this.currentUserId,
    required this.onAddMember,
    required this.onShareInvite,
    required this.onGroupChanged,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> with WidgetsBindingObserver {
  final controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final Map<String, String> translatedMessages = {};
  final Set<String> translatingMessageIds = {};
  final Map<String, DateTime> translationRetryAfter = {};
  final Map<String, String> voiceTranscripts = {};
  final Set<String> transcribingMessageIds = {};
  bool loading = true;
  bool sending = false;
  double? mediaUploadProgress;
  bool refreshing = false;
  Color? chatWallpaperColor;
  bool chatToolsExpanded = false;
  bool hasOlderMessages = false;
  bool loadingOlderMessages = false;
  final ScrollController messagesScrollController = ScrollController();
  bool _autoOlderArmed = false;
  Map<String, dynamic>? olderMessageCursor;
  Map<String, dynamic>? replyToMessage;
  double _replySwipeDistance = 0;
  Timer? refreshTimer;
  StreamSubscription<Map<String, dynamic>>? realtimeSubscription;
  String get groupId => field(widget.group, ['id']);
  String get _messageCacheKey => 'barq_group_messages_${widget.currentUserId}_$groupId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    messagesScrollController.addListener(_maybeLoadOlderMessages);
    loadMessages();
    _loadGroupWallpaper();
    realtimeSubscription = SirajRealtime.instance.events.listen((event) {
      if (event['type'] == 'group_message' && event['groupId']?.toString() == groupId) {
        loadMessages(silent: true);
      }
    });
    _startRefreshTimer();
  }

  Future<void> _loadGroupWallpaper() async {
    try {
      final saved = await storage.read(key: 'barq_group_wallpaper_$groupId');
      final value = saved == null ? null : int.tryParse(saved);
      if (value != null && mounted) setState(() => chatWallpaperColor = Color(value));
    } catch (_) {}
  }

  Future<void> _chooseGroupWallpaper() async {
    final selected = await showBarqWallpaperPicker(context, chatWallpaperColor);
    if (selected == null || !mounted) return;
    setState(() => chatWallpaperColor = selected == Colors.transparent ? null : selected);
    final key = 'barq_group_wallpaper_$groupId';
    if (selected == Colors.transparent) {
      await storage.delete(key: key);
    } else {
      await storage.write(key: key, value: selected.toARGB32().toString());
    }
  }

  void _startRefreshTimer() {
    refreshTimer?.cancel();
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !sending && !refreshing) loadMessages(silent: true);
    });
  }

  void _stopRefreshTimer() {
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      if (!refreshing) loadMessages(silent: true);
    } else if (barqShouldPauseBackgroundWork(state)) {
      _stopRefreshTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    realtimeSubscription?.cancel();
    messagesScrollController.dispose();
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
      if (!silent && messages.isEmpty) {
        final cached = await loadBarqCachedMessages(_messageCacheKey);
        if (cached.isNotEmpty && mounted) {
          setState(() {
            messages = cached;
            loading = false;
          });
        }
      }
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
        unawaited(saveBarqCachedMessages(_messageCacheKey, messages));
        if (BarqFeatures.autoTranslate) _translateMessages(data);
      }
    } catch (e) {
      final message = cleanError(e).toLowerCase();
      final accessRevoked = message.contains('403') ||
          message.contains('not a member') ||
          message.contains('عضوًا في المجموعة') ||
          message.contains('غير مصرح');
      if (accessRevoked) {
        await storage.delete(key: _messageCacheKey);
      }
      if (mounted) {
        setState(() {
          loading = false;
          if (accessRevoked) messages = [];
        });
        if (!silent) showMsg(context, cleanError(e));
      }
    } finally { refreshing = false; }
  }

  void _maybeLoadOlderMessages() {
    if (!messagesScrollController.hasClients) return;
    final position = messagesScrollController.position;
    if (position.pixels > 120) {
      _autoOlderArmed = true;
      return;
    }
    if (_autoOlderArmed &&
        position.userScrollDirection == ScrollDirection.forward &&
        hasOlderMessages && !loadingOlderMessages) {
      _autoOlderArmed = false;
      unawaited(loadOlderMessages());
    }
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
    if (body.isEmpty) return;
    if (!isBarqMessageTextAllowed(body)) {
      showMsg(context, 'الرسالة طويلة جدًا؛ الحد الأقصى 5000 حرف.');
      return;
    }
    final replySnapshot = replyToMessage == null ? null : Map<String, dynamic>.from(replyToMessage!);
    final localId = newBarqMessageId();
    final localMessage = <String, dynamic>{
      'id': localId,
      'sender_id': widget.currentUserId,
      'body': body,
      if (replySnapshot != null) 'reply_to_id': field(replySnapshot, ['id', 'message_id']),
      if (replySnapshot != null) 'reply_to_body': field(replySnapshot, ['body', 'content', 'message']),
      if (replySnapshot != null) 'reply_to_sender_id': field(replySnapshot, ['sender_id']),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_sending': true,
    };
    controller.clear();
    if (mounted) {
      setState(() {
        replyToMessage = null;
        sending = true;
        messages = mergeMessages(messages, [localMessage]);
      });
    }
    try {
      await Api.sendGroupMessage(groupId, body,
        replyToId: replySnapshot == null ? null : field(replySnapshot, ['id', 'message_id']));
      if (mounted) setState(() => messages.removeWhere((item) => item['id'] == localId));
      await loadMessages(silent: true);
    } catch (e) {
      if (mounted) {
        setState(() => messages.removeWhere((item) => item['id'] == localId));
        showMsg(context, cleanError(e));
      }
    } finally { if (mounted) setState(() => sending = false); }
  }

  Map<String, dynamic> _newPendingAttachment(Uint8List bytes, String fileName, String contentType, {Duration? duration, String? localPath}) => {
    'id': newBarqMessageId(), 'sender_id': widget.currentUserId, 'group_id': groupId,
    'body': '', 'created_at': DateTime.now().toUtc().toIso8601String(), 'is_sending': true,
    'local_attachment': {'type':'attachment','fileName':fileName,'contentType':contentType,
      'size':bytes.length,'localBytes':bytes,'localUploadProgress':0.0,
      if (duration != null) 'duration': duration.inMilliseconds,
      if (localPath != null && localPath.isNotEmpty) 'localPath': localPath},
  };

  Future<void> _uploadPendingAttachment(Map<String, dynamic> message) async {
    final attachment = message['local_attachment'];
    if (attachment is! Map<String, dynamic> || attachment['localBytes'] is! Uint8List) return;
    final id = field(message, ['id']);
    if (mounted) setState(() { attachment['localUploadFailed'] = false; attachment['localUploadProgress'] = 0.0; });
    try {
      await Api.uploadAttachment(
        bytes: attachment['localBytes'] as Uint8List,
        fileName: field(attachment, ['fileName'], 'barq-file'),
        contentType: field(attachment, ['contentType'], 'application/octet-stream'),
        groupId: groupId,
        caption: field(attachment, ['caption']),
        onProgress: (value) { if (mounted) setState(() => attachment['localUploadProgress'] = value); },
      );
      if (mounted) setState(() => messages.removeWhere((item) => field(item, ['id']) == id));
      await loadMessages(silent: true);
    } catch (error) {
      if (mounted) {
        setState(() { attachment['localUploadFailed'] = true; message['is_sending'] = false; });
        showMsg(context, cleanError(error));
      }
    }
  }

  Future<void> _sendVoiceRecording(List<int> bytes, Duration duration) async {
    final local = _newPendingAttachment(Uint8List.fromList(bytes),
      'barq_voice_${DateTime.now().millisecondsSinceEpoch}.m4a', 'audio/mp4',
      duration: duration);
    if (mounted) setState(() => messages = mergeMessages(messages, [local]));
    unawaited(_uploadPendingAttachment(local));
  }

  Future<void> pickAndSendMedia() async {
    try {
      final result = await showBarqMediaPicker(
        context, allowMultiple: false, title: 'اختيار صورة أو فيديو',
        withData: false, allowFiles: false, requestType: RequestType.common,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final contentType = file.extension == null ? 'application/octet-stream' : _mimeForExtension(file.extension!);
      if (!mounted) return;
      final caption = controller.text.trim();
      final local = <String, dynamic>{
        'id': newBarqMessageId(), 'sender_id': widget.currentUserId, 'group_id': groupId,
        'body': '', 'created_at': DateTime.now().toUtc().toIso8601String(), 'is_sending': true,
        'local_attachment': <String, dynamic>{
          'type': 'attachment', 'fileName': file.name, 'contentType': contentType,
          'size': file.size, 'localPath': file.path, 'localUploadProgress': 0.0,
          'localPreparing': true, 'caption': caption,
        },
      };
      controller.clear();
      setState(() => messages = mergeMessages(messages, [local]));
      Uint8List bytes;
      try {
        bytes = Uint8List.fromList(await readBarqPickedFileBytes(file));
      } catch (_) {
        if (mounted) setState(() => messages.removeWhere((item) => field(item, ['id']) == field(local, ['id'])));
        rethrow;
      }
      if (!mounted) return;
      final attachment = local['local_attachment'] as Map<String, dynamic>;
      setState(() {
        attachment['localBytes'] = bytes;
        attachment['size'] = bytes.length;
        attachment['localPreparing'] = false;
      });
      unawaited(_uploadPendingAttachment(local));
    } catch (error) {
      if (mounted) showMsg(context, cleanError(error));
    }
  }

  Future<void> pickAndSendFile() async {
    try {
      final result = await showBarqMediaPicker(context, allowMultiple: false,
        title: 'إرسال وسائط أو ملف للمجموعة', withData: false);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final contentType = file.extension == null ? 'application/octet-stream' : _mimeForExtension(file.extension!);
      if (!mounted) return;
      final caption = controller.text.trim();
      final local = <String, dynamic>{
        'id': newBarqMessageId(), 'sender_id': widget.currentUserId, 'group_id': groupId,
        'body': '', 'created_at': DateTime.now().toUtc().toIso8601String(), 'is_sending': true,
        'local_attachment': <String, dynamic>{
          'type': 'attachment', 'fileName': file.name, 'contentType': contentType,
          'size': file.size, 'localPath': file.path, 'localUploadProgress': 0.0,
          'localPreparing': true, 'caption': caption,
        },
      };
      controller.clear();
      setState(() => messages = mergeMessages(messages, [local]));
      Uint8List bytes;
      try {
        bytes = Uint8List.fromList(await readBarqPickedFileBytes(file));
      } catch (_) {
        if (mounted) setState(() => messages.removeWhere((item) => field(item, ['id']) == field(local, ['id'])));
        rethrow;
      }
      if (!mounted) return;
      final attachment = local['local_attachment'] as Map<String, dynamic>;
      setState(() {
        attachment['localBytes'] = bytes;
        attachment['size'] = bytes.length;
        attachment['localPreparing'] = false;
      });
      unawaited(_uploadPendingAttachment(local));
    } catch (error) { if (mounted) showMsg(context, cleanError(error)); }
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
          titleSpacing: 4,
          title: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: showGroupMembers,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
                child: Stack(clipBehavior: Clip.none, children: [
                  Icon(Icons.groups_rounded, color: Theme.of(context).colorScheme.primary, size: 21),
                  Positioned(
                    bottom: -5, left: -5,
                    child: Container(
                      width: 13, height: 13,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
                      ),
                      child: Icon(Icons.bolt_rounded, size: 9, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 9),
              Flexible(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(field(widget.group, ['name'], 'مجموعة'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('${field(widget.group, ['member_count', 'memberCount'], 'مجموعة')} أعضاء',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .62))),
                ],
              )),
            ]),
          ),
          actions: [
            IconButton(
              tooltip: chatToolsExpanded ? 'إخفاء أدوات المجموعة' : 'إظهار أدوات المجموعة',
              onPressed: () => setState(() => chatToolsExpanded = !chatToolsExpanded),
              icon: Icon(chatToolsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded),
            ),
          ],
          bottom: chatToolsExpanded
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: SizedBox(
                    height: 52,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: Row(children: [
                        ActionChip(
                          avatar: const Icon(Icons.search_rounded, size: 17),
                          label: const Text('بحث'),
                          onPressed: () => showConversationSearch(context, (query, before) =>
                            Api.searchGroupMessages(groupId, query, before: before)),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
                          label: const Text('ملخص'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => BarqConversationSummaryDialog(
                              loadSummary: () => Api.summarizeGroupConversation(groupId),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.push_pin_outlined, size: 17),
                          label: const Text('المثبتة'),
                          onPressed: () => showBarqMessageCollectionDialog(context,
                            title: 'الرسائل المثبتة', messages: messages, attachmentsOnly: false),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.perm_media_outlined, size: 17),
                          label: const Text('الوسائط'),
                          onPressed: () => showBarqMessageCollectionDialog(context,
                            title: 'الوسائط والملفات', messages: messages, attachmentsOnly: true),
                        ),
                        const SizedBox(width: 7),
                        ActionChip(
                          avatar: const Icon(Icons.wallpaper_outlined, size: 17),
                          label: const Text('الخلفية'),
                          onPressed: _chooseGroupWallpaper,
                        ),
                        if (['owner', 'admin'].contains(field(widget.group, ['current_role'], 'member'))) ...[
                          const SizedBox(width: 7),
                          ActionChip(
                            avatar: const Icon(Icons.link_rounded, size: 17),
                            label: const Text('رابط الدعوة'),
                            onPressed: widget.onShareInvite,
                          ),
                          const SizedBox(width: 7),
                          ActionChip(
                            avatar: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                            label: const Text('إضافة أعضاء'),
                            onPressed: widget.onAddMember,
                          ),
                        ],
                      ]),
                    ),
                  ),
                )
              : null,
        ),
        body: Container(
          decoration: barqChatWallpaperDecoration(context, chatWallpaperColor),
          child: Column(children: [
          Expanded(child: loading
            ? const Center(child: CircularProgressIndicator())
            : messages.isEmpty
              ? const Center(child: Text('لا توجد رسائل بعد. ابدأ الحديث مع مجموعتك.', style: TextStyle(color: Colors.white60)))
              : ListView.builder(
                  controller: messagesScrollController,
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
                        constraints: const BoxConstraints(maxWidth: 280),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: mine
                                ? [
                                    const Color(0xFF0757B8).withValues(alpha: .96),
                                    const Color(0xFF063B82).withValues(alpha: .96),
                                  ]
                                : [
                                    const Color(0xFF18253D).withValues(alpha: .97),
                                    const Color(0xFF111D32).withValues(alpha: .97),
                                  ],
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(mine ? 18 : 5),
                            bottomRight: Radius.circular(mine ? 5 : 18),
                          ),
                          border: Border.all(
                            color: mine
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: .24)
                                : Theme.of(context).colorScheme.outline.withValues(alpha: .12),
                          ),
                          boxShadow: [BoxShadow(
                            color: mine
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: .07)
                                : Colors.black.withValues(alpha: .07),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (field(m, ['reply_to_id']).isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 7),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8),
                                border: Border(right: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(field(m, ['reply_to_sender_id']) == widget.currentUserId ? 'رد على رسالتك' : 'رد على رسالة',
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
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
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11)),
                              ),
                            ),
                          if (_attachmentData(m) case final attachment?) ...[
                            GestureDetector(
                              onHorizontalDragStart: (_) => _replySwipeDistance = 0,
                              onHorizontalDragUpdate: (details) => _replySwipeDistance += details.delta.dx,
                              onHorizontalDragEnd: (details) {
                                final swiped = _replySwipeDistance.abs() > 42 ||
                                    (details.primaryVelocity ?? 0).abs() > 180;
                                _replySwipeDistance = 0;
                                if (swiped) setState(() => replyToMessage = Map<String, dynamic>.from(m));
                              },
                              onDoubleTap: () async {
                                if (m['is_ephemeral'] == true || m['is_offline_pending'] == true) return;
                                try {
                                  await Api.reactGroupMessage(groupId, field(m, ['id', 'message_id']), '❤️');
                                  if (mounted) await loadMessages(silent: true);
                                } catch (error) {
                                  if (mounted) showMsg(context, cleanError(error));
                                }
                              },
                              onLongPress: () => showMessageActions(
                                context,
                                message: m,
                                currentUserId: widget.currentUserId,
                                canDelete: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                canDeleteForMe: m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                onDeleteForMe: () async {
                                  await Api.hideGroupMessageForMe(groupId, field(m, ['id', 'message_id']));
                                  if (mounted) await loadMessages();
                                },
                                onDelete: () async {
                                  await Api.deleteGroupMessage(groupId, field(m, ['id', 'message_id']));
                                  if (mounted) await loadMessages();
                                },
                                onReply: (message) async {
                                  setState(() => replyToMessage = Map<String, dynamic>.from(message));
                                },
                                onForward: _attachmentData(m) != null
                                    ? () => forwardBarqMessage(context, m) : null,
                                onEdit: mine && _attachmentData(m) != null
                                    ? (caption) async {
                                        final updated = {..._attachmentData(m)!, 'caption': caption};
                                        await Api.editGroupMessage(groupId, field(m, ['id', 'message_id']), jsonEncode(updated));
                                        if (mounted) await loadMessages();
                                      }
                                    : null,
                                onReact: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                    ? (emoji, remove) async {
                                        await Api.reactGroupMessage(groupId, field(m, ['id', 'message_id']), emoji, remove: remove);
                                        if (mounted) await loadMessages(silent: true);
                                      }
                                    : null,
                                onPin: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                    ? () async {
                                        await Api.pinGroupMessage(groupId, field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
                                        if (mounted) await loadMessages(silent: true);
                                      }
                                    : null,
                                isPinned: m['is_pinned'] == true,
                              ),
                              child: _barqAttachmentTile(attachment, (onProgress) => Api.downloadAttachment(
                                attachmentId: field(attachment, ['attachmentId']),
                                fileName: field(attachment, ['fileName'], 'attachment'),
                                onProgress: onProgress,
                              ), onRetry: attachment['localBytes'] is Uint8List ? () => _uploadPendingAttachment(m) : null),
                            ),
                            if (field(attachment, ['contentType']).startsWith('audio/') && field(attachment, ['attachmentId']).isNotEmpty)
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
                              onHorizontalDragStart: (_) => _replySwipeDistance = 0,
                              onHorizontalDragUpdate: (details) => _replySwipeDistance += details.delta.dx,
                              onHorizontalDragEnd: (details) {
                                final shouldReply = _replySwipeDistance.abs() > 48 ||
                                    (details.primaryVelocity ?? 0).abs() > 260;
                                _replySwipeDistance = 0;
                                if (shouldReply) {
                                  setState(() => replyToMessage = Map<String, dynamic>.from(m));
                                }
                              },
                              onDoubleTap: () async {
                                if (m['is_ephemeral'] == true || m['is_offline_pending'] == true) return;
                                try {
                                  await Api.reactGroupMessage(groupId, field(m, ['id', 'message_id']), '❤️');
                                  if (mounted) await loadMessages(silent: true);
                                } catch (error) {
                                  if (mounted) showMsg(context, cleanError(error));
                                }
                              },
                              onLongPress: () => showMessageActions(
                                context,
                                message: m,
                                currentUserId: widget.currentUserId,
                                canDelete: mine && m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                canDeleteForMe: m['is_ephemeral'] != true && m['is_offline_pending'] != true,
                                onDeleteForMe: () async {
                                  await Api.hideGroupMessageForMe(groupId, field(m, ['id', 'message_id']));
                                  if (mounted) await loadMessages();
                                },
                                onDelete: () async {
                                  await Api.deleteGroupMessage(groupId, field(m, ['id', 'message_id']));
                                  if (mounted) await loadMessages();
                                },
                                onReply: (message) async {
                                  setState(() => replyToMessage = Map<String, dynamic>.from(message));
                                },
                                onForward: field(m, ['body', 'content', 'message']).trim().isNotEmpty || _attachmentData(m) != null
                                    ? () => forwardBarqMessage(context, m) : null,
                                onEdit: mine && _attachmentData(m) == null
                                    ? (body) async {
                                        await Api.editGroupMessage(groupId, field(m, ['id', 'message_id']), body);
                                        if (mounted) await loadMessages();
                                      }
                                    : null,
                                onReact: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                    ? (emoji, remove) async {
                                        await Api.reactGroupMessage(groupId, field(m, ['id', 'message_id']), emoji, remove: remove);
                                        if (mounted) await loadMessages(silent: true);
                                      }
                                    : null,
                                onPin: m['is_ephemeral'] != true && m['is_offline_pending'] != true
                                    ? () async {
                                        await Api.pinGroupMessage(groupId, field(m, ['id', 'message_id']), pinned: m['is_pinned'] != true);
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
                              if (mine) ...[
                                const SizedBox(width: 5),
                                if (m['is_sending'] == true) ...[
                                  const SizedBox(width: 9, height: 9,
                                    child: CircularProgressIndicator(strokeWidth: 1.4, color: Colors.white70)),
                                  const SizedBox(width: 3),
                                  const Text('جارٍ الإرسال', style: TextStyle(color: Colors.white60, fontSize: 9)),
                                ] else ...[
                                  Icon(
                                    (int.tryParse((m['seen_count'] ?? 0).toString()) ?? 0) > 0
                                        ? Icons.done_all_rounded : Icons.done_rounded,
                                    size: 13,
                                    color: (int.tryParse((m['seen_count'] ?? 0).toString()) ?? 0) > 0
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: .62),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    (int.tryParse((m['seen_count'] ?? 0).toString()) ?? 0) > 0
                                        ? 'تمت المشاهدة (${m['seen_count']})' : 'تم الإرسال',
                                    style: const TextStyle(color: Colors.white60, fontSize: 9),
                                  ),
                                ],
                              ],
                              if (field(m, ['edited_at', 'editedAt']).isNotEmpty) ...[
                                const SizedBox(width: 5),
                                const Text('تم التعديل', style: TextStyle(color: Colors.white54, fontSize: 9)),
                              ],
                            ],
                          )),
                          if (m['is_pinned'] == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.push_pin, size: 12),
                                const SizedBox(width: 3),
                                Text('مثبتة', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10)),
                              ]),
                            ),
                          messageReactionBar(
                            context: context,
                            message: m,
                            currentUserId: widget.currentUserId,
                            onReact: (emoji, remove) async {
                              await Api.reactGroupMessage(
                                groupId, field(m, ['id', 'message_id']), emoji, remove: remove,
                              );
                              if (mounted) await loadMessages(silent: true);
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                )),
            if (mediaUploadProgress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                child: Row(children: [
                  Expanded(child: LinearProgressIndicator(
                    value: mediaUploadProgress! <= 0 ? null : mediaUploadProgress!.clamp(0.0, 1.0),
                  )),
                  const SizedBox(width: 10),
                  Text(mediaUploadProgress! <= 0
                      ? 'جارٍ رفع المرفق'
                      : 'رفع المرفق ${(mediaUploadProgress! * 100).round()}%',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
              ),
          if (replyToMessage != null)
            BarqReplyPreview(
              sender: field(replyToMessage!, ['display_name', 'username', 'sender_name'], 'رسالة مقتبسة'),
              preview: messageReplyPreview(replyToMessage!),
              onClose: sending ? null : () => setState(() => replyToMessage = null),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 9, 9),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF071326).withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .38)),
                  boxShadow: [
                    BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .10), blurRadius: 18),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'إضافة رمز تعبيري',
                      onPressed: sending ? null : () => insertBarqChatEmoji(controller),
                      icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالة أو تعليق الوسائط...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                        ),
                        onSubmitted: (_) => send(),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'إرفاق صورة أو ملف',
                      onPressed: sending ? null : pickAndSendFile,
                      icon: const Icon(Icons.attach_file_rounded, color: Colors.white70),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'اختيار صورة أو فيديو',
                      onPressed: sending ? null : pickAndSendMedia,
                      icon: const Icon(Icons.photo_library_outlined, color: Colors.white70),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        if (value.text.trim().isEmpty && !sending) {
                          return BarqVoiceRecordButton(disabled: sending, onSend: _sendVoiceRecording);
                        }
                        return SizedBox(
                          width: 42,
                          height: 42,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            ),
                            onPressed: send,
                            icon: const Icon(Icons.send_rounded),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ])),
      ),
    );
  }
}
