import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'security.dart';

const _blue = Color(0xFF2785FF);
const _gold = Color(0xFFE8B95B);
const _surface = Color(0xFF151E31);
const _background = Color(0xFF0A1020);
const _googleOidcClientId = String.fromEnvironment(
  'BARQ_GOOGLE_OIDC_CLIENT_ID',
);

void main() => runApp(const BarqAdminApp());

class BarqAdminApp extends StatelessWidget {
  const BarqAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'BARQ Admin',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _blue,
            brightness: Brightness.dark,
            surface: _surface,
          ),
          cardTheme: CardThemeData(
            color: _surface,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF202B42),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AdminHomePage(),
      );
}

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage>
    with WidgetsBindingObserver {
  static const _secure = FlutterSecureStorage();
  static final _appAuth = FlutterAppAuth();
  static const _cacheWorkspace = 'barq_admin_workspace_cache';
  static const _cacheTasks = 'barq_admin_tasks_cache';
  static const _cacheApprovals = 'barq_admin_approvals_cache';
  static const _cacheAudit = 'barq_admin_audit_cache';
  static const _outboxKey = 'barq_admin_task_outbox';

  String _apiBase = '';
  String _token = '';
  String _refreshToken = '';
  String _sessionId = '';
  Future<bool>? _refreshFuture;
  String _connectionMessage = 'غير متصل';
  Map<String, dynamic> _workspace = {};
  List<AdminTask> _tasks = [];
  List<AdminApproval> _approvals = [];
  List<Map<String, dynamic>> _auditEvents = [];
  int _tab = 0;
  bool _loading = true;
  bool _online = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  String get _base => _apiBase.replaceFirst(RegExp(r'/+$'), '');
  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiBase = prefs.getString('barq_admin_api_base') ?? '';
    _token = await _secure.read(key: 'barq_admin_owner_token') ?? '';
    _refreshToken = await _secure.read(key: 'barq_admin_refresh_token') ?? '';
    _sessionId = await _secure.read(key: 'barq_admin_session_id') ?? '';
    _readCache(prefs);
    _mergeOutboxDrafts(prefs);
    if (_apiBase.isEmpty || _token.isEmpty) {
      if (mounted)
        setState(() {
          _loading = false;
          _online = false;
          _connectionMessage = _apiBase.isEmpty
              ? 'أدخل عنوان خادم الإدارة'
              : 'سجّل الدخول بحساب المالك عبر Google';
        });
      return;
    }
    if (!isValidAdminApiBase(_apiBase)) {
      if (mounted)
        setState(() {
          _loading = false;
          _online = false;
          _connectionMessage = 'عنوان الخادم غير آمن؛ استخدم HTTPS صحيحًا';
        });
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _connectionMessage = 'جارٍ المزامنة';
      });
    try {
      await _syncOutbox(prefs);
      var workspaceResponse = await http
          .get(Uri.parse(_base + '/v1/workspace'), headers: _headers)
          .timeout(const Duration(seconds: 18));
      if (workspaceResponse.statusCode == 401 && await _refreshSession()) {
        workspaceResponse = await http
            .get(Uri.parse(_base + '/v1/workspace'), headers: _headers)
            .timeout(const Duration(seconds: 18));
      }
      if (workspaceResponse.statusCode == 401) {
        throw Exception('انتهت جلسة المالك؛ سجّل الدخول مجددًا عبر Google');
      }
      if (workspaceResponse.statusCode != 200) {
        throw Exception(
          'تعذر تحميل مساحة العمل (' +
              workspaceResponse.statusCode.toString() +
              ')',
        );
      }
      final workspaceData =
          jsonDecode(workspaceResponse.body) as Map<String, dynamic>;
      final taskData = await _getJson('/v1/tasks');
      final approvalData = await _getJson('/v1/approvals');
      final auditData = await _getJson('/v1/audit');
      _workspace = Map<String, dynamic>.from(
        workspaceData['workspace'] as Map? ?? {},
      );
      _tasks = (taskData['tasks'] as List? ?? [])
          .whereType<Map>()
          .map((item) => AdminTask.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      _mergeOutboxDrafts(prefs);
      _approvals = (approvalData['approvals'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) => AdminApproval.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      _auditEvents = (auditData['events'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      await prefs.setString(_cacheWorkspace, jsonEncode(_workspace));
      await prefs.setString(
        _cacheTasks,
        jsonEncode(_tasks.map((task) => task.toJson()).toList()),
      );
      await prefs.setString(
        _cacheApprovals,
        jsonEncode(approvalData['approvals'] ?? []),
      );
      await prefs.setString(_cacheAudit, jsonEncode(_auditEvents));
      _online = true;
      _connectionMessage = 'متصل ومتزامن';
    } catch (error) {
      _online = false;
      _connectionMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _readCache(SharedPreferences prefs) {
    try {
      final workspace = prefs.getString(_cacheWorkspace);
      if (workspace != null)
        _workspace = Map<String, dynamic>.from(jsonDecode(workspace) as Map);
      final tasks = prefs.getString(_cacheTasks);
      if (tasks != null) {
        _tasks = (jsonDecode(tasks) as List)
            .whereType<Map>()
            .map((item) => AdminTask.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      final audit = prefs.getString(_cacheAudit);
      if (audit != null)
        _auditEvents = (jsonDecode(audit) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      final approvals = prefs.getString(_cacheApprovals);
      if (approvals != null) {
        _approvals = (jsonDecode(approvals) as List)
            .whereType<Map>()
            .map(
              (item) => AdminApproval.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
    } catch (_) {
      // The server remains authoritative if a local cache is damaged.
    }
  }

  void _mergeOutboxDrafts(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_outboxKey);
      if (raw == null) return;
      final pending = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _tasks = mergeOutboxDrafts(_tasks, pending);
    } catch (_) {
      // Ignore malformed local drafts; keep the server/cache snapshot usable.
    }
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    var response = await http
        .get(Uri.parse(_base + path), headers: _headers)
        .timeout(const Duration(seconds: 18));
    if (response.statusCode == 401 && await _refreshSession()) {
      response = await http
          .get(Uri.parse(_base + path), headers: _headers)
          .timeout(const Duration(seconds: 18));
    }
    if (response.statusCode != 200) {
      throw Exception(
        'تعذر تحميل البيانات (' + response.statusCode.toString() + ')',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<bool> _refreshSession() {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final refresh = _performSessionRefresh();
    _refreshFuture = refresh;
    return refresh.whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<bool> _performSessionRefresh() async {
    if (_refreshToken.isEmpty || _sessionId.isEmpty || _apiBase.isEmpty)
      return false;
    try {
      final response = await http
          .post(
            Uri.parse(_base + '/v1/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionId': _sessionId,
              'refreshToken': _refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 18));
      if (response.statusCode == 401 || response.statusCode == 403) {
        await _secure.delete(key: 'barq_admin_owner_token');
        await _secure.delete(key: 'barq_admin_refresh_token');
        await _secure.delete(key: 'barq_admin_session_id');
        _token = '';
        _refreshToken = '';
        _sessionId = '';
        return false;
      }
      if (response.statusCode != 200) return false;
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      final nextAccess = (data['accessToken'] ?? '').toString();
      final nextRefresh = (data['refreshToken'] ?? '').toString();
      if (nextAccess.isEmpty || nextRefresh.isEmpty) return false;
      _token = nextAccess;
      _refreshToken = nextRefresh;
      await _secure.write(key: 'barq_admin_owner_token', value: _token);
      await _secure.write(
        key: 'barq_admin_refresh_token',
        value: _refreshToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loginWithGoogle() async {
    if (!isValidAdminApiBase(_apiBase)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'أدخل عنوان خادم BARQ Admin من إعدادات الاتصال أولًا',
            ),
          ),
        );
      return;
    }
    if (_googleOidcClientId.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لم يُضبط Google OAuth Client ID في نسخة التطبيق بعد',
            ),
          ),
        );
      return;
    }
    try {
      final nonce = createOidcNonce();
      final redirectUri = googleOidcRedirectUri(_googleOidcClientId);
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _googleOidcClientId,
          redirectUri,
          issuer: 'https://accounts.google.com',
          scopes: const ['openid', 'email', 'profile'],
          nonce: nonce,
        ),
      );
      final idToken = result.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('لم يُرجع Google إثبات هوية صالحًا');
      }
      final response = await http
          .post(
            Uri.parse(_base + '/v1/auth/exchange'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
              'nonce': nonce,
              'deviceName': Platform.isIOS
                  ? 'BARQ Admin — iPhone'
                  : 'BARQ Admin — Android',
              'platform': Platform.isIOS ? 'ios' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 25));
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (response.statusCode != 200) {
        throw Exception(
          data['error'] == 'identity_verification_failed'
              ? 'رفض الخادم إثبات Google؛ تحقق من حساب المالك وإعدادات Preview'
              : 'تعذر إنشاء جلسة الإدارة (' +
                  response.statusCode.toString() +
                  ')',
        );
      }
      _token = (data['accessToken'] ?? '').toString();
      _refreshToken = (data['refreshToken'] ?? '').toString();
      _sessionId = (data['sessionId'] ?? '').toString();
      if (_token.isEmpty || _refreshToken.isEmpty || _sessionId.isEmpty) {
        throw Exception('استجابة إنشاء الجلسة غير مكتملة');
      }
      await _secure.write(key: 'barq_admin_owner_token', value: _token);
      await _secure.write(
        key: 'barq_admin_refresh_token',
        value: _refreshToken,
      );
      await _secure.write(key: 'barq_admin_session_id', value: _sessionId);
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  Future<void> _syncOutbox(SharedPreferences prefs) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final raw = prefs.getString(_outboxKey);
      if (raw == null) return;
      final pending = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final remaining = <Map<String, dynamic>>[];
      for (final item in pending) {
        try {
          Future<http.Response> sendPendingTask() => http
              .post(
                Uri.parse(_base + '/v1/tasks'),
                headers: {
                  ..._headers,
                  'X-Idempotency-Key': item['idempotencyKey'].toString(),
                },
                body: jsonEncode({
                  'title': item['title'],
                  'description': item['description'],
                  'priority': item['priority'] ?? 'normal',
                }),
              )
              .timeout(const Duration(seconds: 18));
          var response = await sendPendingTask();
          if (response.statusCode == 401 && await _refreshSession()) {
            response = await sendPendingTask();
          }
          if (response.statusCode < 200 || response.statusCode >= 300) {
            remaining.add(item);
          }
        } catch (_) {
          remaining.add(item);
        }
      }
      await prefs.setString(_outboxKey, jsonEncode(remaining));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _createTask(String title, String description) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final idempotencyKey = DateTime.now().microsecondsSinceEpoch.toString() +
        '-' +
        Random.secure().nextInt(1 << 32).toString();
    final payload = {
      'title': cleanTitle,
      'description': description.trim(),
      'priority': 'normal',
      'idempotencyKey': idempotencyKey,
    };
    if (_online && _apiBase.isNotEmpty && _token.isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse(_base + '/v1/tasks'),
              headers: {..._headers, 'X-Idempotency-Key': idempotencyKey},
              body: jsonEncode({
                'title': cleanTitle,
                'description': description.trim(),
                'priority': 'normal',
              }),
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('تعذر إرسال المهمة');
        }
        await _load();
        return;
      } catch (_) {
        // Save locally and retry synchronization when a connection returns.
      }
    }
    final raw = prefs.getString(_outboxKey);
    final pending = raw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    pending.add(payload);
    await prefs.setString(_outboxKey, jsonEncode(pending));
    if (mounted) {
      setState(() {
        _tasks = [
          AdminTask(
            id: 'local-' + idempotencyKey,
            title: cleanTitle,
            description: description.trim(),
            status: 'draft_offline',
            nextAction: 'سيتم الإرسال عند عودة الاتصال',
          ),
          ..._tasks,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'حُفظت المهمة على هذا الهاتف وستُزامن عند عودة الاتصال',
          ),
        ),
      );
    }
  }

  Future<void> _decideApproval(String id, String status) async {
    try {
      final response = await http
          .patch(
            Uri.parse(_base + '/v1/approvals/' + id),
            headers: _headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) throw Exception('تعذر حفظ القرار');
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إنهاء جلسة الإدارة؟'),
        content: const Text(
          'سيُحذف رمز الجلسة والبيانات المخزنة محليًا من هذا الهاتف. المهام التي لم تُرسل بعد ستُحذف أيضًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إنهاء الجلسة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    if (_sessionId.isNotEmpty &&
        _refreshToken.isNotEmpty &&
        _apiBase.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(_base + '/v1/auth/logout'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'sessionId': _sessionId,
                'refreshToken': _refreshToken,
              }),
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    await _secure.delete(key: 'barq_admin_owner_token');
    await _secure.delete(key: 'barq_admin_refresh_token');
    await _secure.delete(key: 'barq_admin_session_id');
    for (final key in [
      _cacheWorkspace,
      _cacheTasks,
      _cacheApprovals,
      _cacheAudit,
      _outboxKey,
    ]) {
      await prefs.remove(key);
    }
    if (!mounted) return;
    setState(() {
      _apiBase = '';
      _token = '';
      _refreshToken = '';
      _sessionId = '';
      _workspace = {};
      _tasks = [];
      _approvals = [];
      _auditEvents = [];
      _online = false;
      _loading = false;
      _connectionMessage = 'تم إنهاء الجلسة';
      _tab = 0;
    });
  }

  Future<void> _showSettings() async {
    final baseController = TextEditingController(text: _apiBase);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إعداد الاتصال الآمن',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'أدخل عنوان خادم برق الذي يستضيف مسار الإدارة /admin. مثال: https://example.com أو https://example.com/admin. تسجيل الدخول عبر Google فقط.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: baseController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'عنوان خادم BARQ (مسار /admin يُضاف تلقائيًا)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ الاتصال'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final input = baseController.text.trim().replaceFirst(RegExp(r'/+
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('أدخل عنوان HTTPS صحيحًا لخادم الإدارة'),
            ),
          );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'barq_admin_api_base',
          normalizeAdminApiBase(input),
        );
        await _load();
      }
    }
    baseController.dispose();
  }

  Future<String> _requestImageAnalysis(
    Uint8List bytes,
    String mimeType,
    String prompt,
  ) async {
    if (_apiBase.isEmpty || _token.isEmpty || !isValidAdminApiBase(_apiBase)) {
      throw Exception('أكمل إعداد اتصال HTTPS وجلسة المالك أولًا');
    }
    if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw Exception('حجم الصورة يجب ألا يتجاوز 4 ميغابايت');
    }
    final response = await http
        .post(
          Uri.parse(_base + '/v1/brain/vision'),
          headers: _headers,
          body: jsonEncode({
            'prompt': prompt.trim().isEmpty
                ? 'حلل هذه الصورة واشرح ما يظهر فيها.'
                : prompt.trim(),
            'image': 'data:' + mimeType + ';base64,' + base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 90));
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'استجابة الخادم غير مفهومة؛ تحقق من اتصال Preview ثم أعد المحاولة',
      );
    }
    if (response.statusCode != 200) {
      final message = data is Map && data['error'] == 'admin_ai_unavailable'
          ? 'خدمة الذكاء الاصطناعي غير مهيأة على الخادم بعد'
          : data is Map && data['error'] == 'vision_model_license_required'
              ? 'يلزم تفعيل اتفاقية ترخيص نموذج الرؤية في حساب Cloudflare قبل استخدام تحليل الصور'
              : data is Map && data['error'] == 'image_too_large'
                  ? 'الصورة أكبر من الحد المسموح'
                  : data is Map && data['error'] == 'invalid_image_or_prompt'
                      ? 'صيغة الصورة غير مدعومة أو لا يطابق محتواها نوعها؛ استخدم JPEG أو PNG أو WebP'
                      : data is Map && data['error'] == 'vision_analysis_failed'
                          ? 'تعذر على نموذج الرؤية تحليل الصورة؛ جرّب صورة أوضح أو أعد المحاولة'
                          : 'تعذر تحليل الصورة (' +
                              response.statusCode.toString() +
                              ')';
      throw Exception(message);
    }
    final answer = data is Map ? (data['answer'] ?? '').toString().trim() : '';
    if (answer.isEmpty) throw Exception('لم يُرجع المساعد نتيجة');
    return answer;
  }

  Future<Uint8List> _requestImageGeneration(String prompt) async {
    if (_apiBase.isEmpty || _token.isEmpty || !isValidAdminApiBase(_apiBase)) {
      throw Exception('أكمل إعداد اتصال HTTPS وجلسة المالك أولًا');
    }
    final response = await http
        .post(
          Uri.parse(_base + '/v1/brain/generate-image'),
          headers: _headers,
          body: jsonEncode({'prompt': prompt.trim()}),
        )
        .timeout(const Duration(seconds: 180));
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'استجابة الخادم غير مفهومة؛ تحقق من اتصال Preview ثم أعد المحاولة',
      );
    }
    if (response.statusCode != 200) {
      final message = data is Map && data['error'] == 'admin_ai_unavailable'
          ? 'خدمة الذكاء الاصطناعي غير مهيأة على الخادم بعد'
          : data is Map && data['error'] == 'invalid_image_prompt'
              ? 'اكتب وصفًا للصورة لا يتجاوز 1600 حرف'
              : data is Map &&
                      data['error'] == 'image_generation_model_terms_required'
                  ? 'يلزم قبول شروط نموذج إنشاء الصور في حساب Cloudflare قبل استخدامه'
                  : data is Map && data['error'] == 'image_generation_failed'
                      ? 'تعذر إنشاء الصورة؛ تحقق من تفعيل Workers AI ثم أعد المحاولة'
                      : 'تعذر إنشاء الصورة (' +
                          response.statusCode.toString() +
                          ')';
      throw Exception(message);
    }
    final imageUri = data is Map ? (data['image'] ?? '').toString() : '';
    const prefix = 'data:image/jpeg;base64,';
    if (!imageUri.startsWith(prefix))
      throw Exception('لم يُرجع المساعد ملف صورة صالحًا');
    final bytes = base64Decode(imageUri.substring(prefix.length));
    if (bytes.length < 4 ||
        bytes.length > 8 * 1024 * 1024 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[2] != 0xff) {
      throw Exception('ملف الصورة الناتج غير صالح أو يتجاوز الحجم المسموح');
    }
    return bytes;
  }

  Future<void> _showBrainChat() async {
    if (_token.isEmpty || !_online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اتصل بخادم BARQ Admin أولًا لبدء محادثة محفوظة'),
        ),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    String? conversationId =
        prefs.getString('barq_admin_brain_conversation_id');
    final controller = TextEditingController();
    final messages = <Map<String, String>>[];
    var sending = false;

    if (conversationId != null && conversationId.isNotEmpty) {
      try {
        final history = await _getJson(
          '/v1/brain/conversations/$conversationId/messages',
        );
        for (final item in (history['messages'] as List? ?? const [])) {
          if (item is Map) {
            var content = (item['content'] ?? '').toString();
            final sources = item['sources'];
            if (sources is List && sources.isNotEmpty) {
              final references = sources.whereType<Map>().map((source) {
                final path = (source['sourcePath'] ?? '').toString();
                final revision = (source['sourceRevision'] ?? '').toString();
                return revision.isEmpty
                    ? '• ' + path
                    : '• ' + path + ' @ ' + revision;
              }).join('\\n');
              content += '\\n\\nالمصادر التي استند إليها:\\n' + references;
            }
            messages.add({
              'role': (item['role'] ?? 'assistant').toString(),
              'content': content,
            });
          }
        }
      } catch (_) {
        conversationId = null;
        await prefs.remove('barq_admin_brain_conversation_id');
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> sendMessage() async {
            final prompt = controller.text.trim();
            if (prompt.isEmpty || sending) return;
            controller.clear();
            setDialogState(() {
              messages.add({'role': 'user', 'content': prompt});
              sending = true;
            });
            try {
              Future<http.Response> submit() => http
                  .post(
                    Uri.parse(_base + '/v1/brain/chat'),
                    headers: _headers,
                    body: jsonEncode({
                      'message': prompt,
                      if (conversationId != null)
                        'conversationId': conversationId,
                    }),
                  )
                  .timeout(const Duration(seconds: 90));
              var response = await submit();
              if (response.statusCode == 401 && await _refreshSession()) {
                response = await submit();
              }
              final data = Map<String, dynamic>.from(
                jsonDecode(response.body) as Map,
              );
              final returnedConversationId =
                  (data['conversationId'] ?? '').toString();
              if (returnedConversationId.isNotEmpty) {
                conversationId = returnedConversationId;
                await prefs.setString(
                  'barq_admin_brain_conversation_id',
                  returnedConversationId,
                );
              }
              if (response.statusCode != 200) {
                throw Exception(
                  (data['error'] ?? 'تعذر الحصول على رد المساعد').toString(),
                );
              }
              if (conversationId == null || conversationId!.isEmpty) {
                throw Exception('لم يُرجع الخادم رقم المحادثة');
              }
              var answer = (data['answer'] ?? '').toString();
              final sources = data['sources'];
              if (sources is List && sources.isNotEmpty) {
                final references = sources.whereType<Map>().map((source) {
                  final path = (source['sourcePath'] ?? '').toString();
                  final revision = (source['sourceRevision'] ?? '').toString();
                  return revision.isEmpty
                      ? '• ' + path
                      : '• ' + path + ' @ ' + revision;
                }).join('\n');
                answer += '\n\nالمصادر التي استند إليها:\n' + references;
              }
              setDialogState(() {
                messages.add({'role': 'assistant', 'content': answer});
              });
            } catch (error) {
              setDialogState(() {
                messages.add({
                  'role': 'error',
                  'content': error.toString().replaceFirst('Exception: ', ''),
                });
              });
            } finally {
              setDialogState(() => sending = false);
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 620,
              height: MediaQuery.of(dialogContext).size.height * .82,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0x332785FF),
                          child: Icon(Icons.auto_awesome, color: _blue),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'محادثة BARQ Brain',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                        ),
                        TextButton(
                          onPressed: sending
                              ? null
                              : () async {
                                  conversationId = null;
                                  messages.clear();
                                  await prefs.remove(
                                      'barq_admin_brain_conversation_id');
                                  setDialogState(() {});
                                },
                          child: const Text('محادثة جديدة'),
                        ),
                        IconButton(
                          onPressed: sending
                              ? null
                              : () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: messages.isEmpty
                          ? const Center(
                              child: Text(
                                'ابدأ بسؤالي عن برق أو اطلب مني مراجعة مشكلة أو بناء ميزة. سأستند إلى مصادر المشروع المفهرسة وأوضح ما لم أتحقق منه.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final item = messages[index];
                                final role = item['role'];
                                final isOwner = role == 'user';
                                final isError = role == 'error';
                                return Align(
                                  alignment: isOwner
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 520),
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isError
                                          ? Colors.red.withValues(alpha: .15)
                                          : isOwner
                                              ? _blue.withValues(alpha: .20)
                                              : _surface,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child:
                                        SelectableText(item['content'] ?? ''),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (sending)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('BARQ Brain يراجع سياق المشروع ويكتب الرد...'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك إلى BARQ Brain...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: sending ? null : sendMessage,
                        icon: const Icon(Icons.send),
                        label: const Text('إرسال'),
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
    controller.dispose();
  }

  Future<void> _showImageGeneration() async {
    if (_apiBase.isEmpty || _token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اضبط اتصال الخادم وجلسة المالك أولًا')),
      );
      return;
    }
    final promptController = TextEditingController();
    Uint8List? generatedBytes;
    bool busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .86,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'إنشاء صورة مع BARQ Brain',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اكتب وصفًا واضحًا للصورة. سيُنشئها المساعد ثم يعرضها هنا لتتمكن من مشاركتها أو إرسالها من هاتفك.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: promptController,
                      maxLines: 4,
                      maxLength: 1600,
                      decoration: const InputDecoration(
                        labelText: 'صف الصورة التي تريد إنشاءها',
                        hintText:
                            'مثال: مشهد سينمائي لمدينة مستقبلية يضيئها البرق الأزرق...',
                      ),
                    ),
                    if (generatedBytes != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          generatedBytes!,
                          fit: BoxFit.contain,
                          height: 300,
                          width: double.infinity,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await Share.shareXFiles([
                              XFile.fromData(
                                generatedBytes!,
                                mimeType: 'image/jpeg',
                                name: 'barq-brain-image.jpg',
                              ),
                            ], text: 'صورة أنشأها BARQ Brain');
                          } catch (error) {
                            if (mounted)
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تعذرت مشاركة الصورة: ' + error.toString(),
                                  ),
                                ),
                              );
                          }
                        },
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('مشاركة الصورة أو إرسالها'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final prompt = promptController.text.trim();
                              if (prompt.isEmpty) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('اكتب وصف الصورة أولًا'),
                                  ),
                                );
                                return;
                              }
                              setSheetState(() {
                                busy = true;
                                generatedBytes = null;
                              });
                              try {
                                final image = await _requestImageGeneration(
                                  prompt,
                                );
                                if (sheetContext.mounted)
                                  setSheetState(() {
                                    generatedBytes = image;
                                    busy = false;
                                  });
                              } catch (error) {
                                if (sheetContext.mounted)
                                  setSheetState(() => busy = false);
                                if (mounted)
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.toString().replaceFirst(
                                              'Exception: ',
                                              '',
                                            ),
                                      ),
                                    ),
                                  );
                              }
                            },
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        busy
                            ? 'جارٍ إنشاء الصورة...'
                            : generatedBytes == null
                                ? 'أنشئ الصورة'
                                : 'أنشئ صورة أخرى',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          busy ? null : () => Navigator.pop(sheetContext),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    promptController.dispose();
  }

  Future<void> _showVisionAnalysis() async {
    if (_apiBase.isEmpty || _token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اضبط اتصال الخادم وجلسة المالك أولًا')),
      );
      return;
    }
    final picker = ImagePicker();
    final promptController = TextEditingController(
      text: 'حلل الصورة بالتفصيل، واشرح العناصر المهمة وأي نص ظاهر فيها.',
    );
    Uint8List? selectedBytes;
    String selectedMime = 'image/jpeg';
    String selectedName = '';
    bool busy = false;
    String? result;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .82,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تحليل صورة مع BARQ Brain',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختر صورة من المعرض أو التقط صورة بالكاميرا. الحد الأقصى 4 ميغابايت، ولا تُحفظ الصورة على الخادم.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    if (selectedBytes == null)
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: const Color(0xFF202B42),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 42,
                              color: Colors.white54,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'لم يتم اختيار صورة بعد',
                              style: TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          selectedBytes!,
                          height: 210,
                          fit: BoxFit.contain,
                        ),
                      ),
                    if (selectedName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        selectedName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    final file = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 82,
                                      maxWidth: 1920,
                                      maxHeight: 1920,
                                    );
                                    if (file == null) return;
                                    final bytes = await file.readAsBytes();
                                    final ext =
                                        file.name.toLowerCase().split('.').last;
                                    final mime = ext == 'png'
                                        ? 'image/png'
                                        : ext == 'webp'
                                            ? 'image/webp'
                                            : (ext == 'jpg' || ext == 'jpeg')
                                                ? 'image/jpeg'
                                                : '';
                                    if (mime.isEmpty) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'صيغة الصورة غير مدعومة؛ استخدم JPEG أو PNG أو WebP',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (bytes.length > 4 * 1024 * 1024) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'اختر صورة لا تتجاوز 4 ميغابايت',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setSheetState(() {
                                      selectedBytes = bytes;
                                      selectedMime = mime;
                                      selectedName = file.name;
                                    });
                                  },
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('المعرض'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    final file = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 82,
                                      maxWidth: 1920,
                                      maxHeight: 1920,
                                    );
                                    if (file == null) return;
                                    final bytes = await file.readAsBytes();
                                    final ext =
                                        file.name.toLowerCase().split('.').last;
                                    final mime = ext == 'png'
                                        ? 'image/png'
                                        : ext == 'webp'
                                            ? 'image/webp'
                                            : (ext == 'jpg' || ext == 'jpeg')
                                                ? 'image/jpeg'
                                                : '';
                                    if (mime.isEmpty) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'صيغة الصورة غير مدعومة؛ استخدم JPEG أو PNG أو WebP',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (bytes.length > 4 * 1024 * 1024) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'اختر صورة لا تتجاوز 4 ميغابايت',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setSheetState(() {
                                      selectedBytes = bytes;
                                      selectedMime = mime;
                                      selectedName = file.name;
                                    });
                                  },
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('الكاميرا'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: promptController,
                      maxLines: 3,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'ماذا تريد أن تعرف عن الصورة؟',
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: busy || selectedBytes == null
                          ? null
                          : () async {
                              setSheetState(() => busy = true);
                              try {
                                result = await _requestImageAnalysis(
                                  selectedBytes!,
                                  selectedMime,
                                  promptController.text,
                                );
                                if (sheetContext.mounted)
                                  Navigator.pop(sheetContext);
                                if (mounted && result != null) {
                                  await showDialog<void>(
                                    context: this.context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('نتيجة تحليل الصورة'),
                                      content: SingleChildScrollView(
                                        child: SelectableText(result!),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('إغلاق'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              } catch (error) {
                                setSheetState(() => busy = false);
                                if (mounted)
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.toString().replaceFirst(
                                              'Exception: ',
                                              '',
                                            ),
                                      ),
                                    ),
                                  );
                              }
                            },
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        busy ? 'جارٍ تحليل الصورة...' : 'حلّل الصورة',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    promptController.dispose();
  }

  Future<void> _showCreateTask({bool assistant = false}) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              assistant ? 'مهمة جديدة إلى BARQ Brain' : 'إضافة مهمة',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: assistant
                    ? 'ما الذي تريد من المساعد إنجازه؟'
                    : 'عنوان المهمة',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'التفاصيل والسياق'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ المهمة'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final title = titleController.text.trim();
      final details = descriptionController.text.trim();
      await _createTask(
        assistant && !title.startsWith('BARQ Brain')
            ? 'BARQ Brain: ' + title
            : title,
        details,
      );
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BARQ Admin',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
            ),
            Text(
              _connectionMessage,
              style: TextStyle(
                fontSize: 11,
                color: _online ? const Color(0xFF6DD6A4) : Colors.white60,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إعدادات الاتصال',
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'الأجهزة',
            onPressed: _token.isEmpty ? null : _showDevices,
            icon: const Icon(Icons.devices_outlined),
          ),
          IconButton(
            tooltip: 'إنهاء الجلسة',
            onPressed: _token.isEmpty ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _tasks.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _tab,
                children: [
                  _dashboard(),
                  _tasksView(),
                  _approvalsView(),
                  _auditView(),
                ],
              ),
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateTask(),
              icon: const Icon(Icons.add),
              label: const Text('مهمة جديدة'),
            )
          : _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showCreateTask(assistant: true),
                  icon: const Icon(Icons.bolt),
                  label: const Text('اسأل BARQ Brain'),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'المهام'),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            label: 'الموافقات',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'السجل',
          ),
        ],
      ),
    );
  }

  Widget _dashboard() {
    final pending = _approvals.where((item) => item.status == 'pending').length;
    final active = _tasks
        .where(
          (task) => [
            'queued',
            'running',
            'paused',
            'needs_approval',
          ].contains(task.status),
        )
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (_token.isEmpty) _signInCard(),
        _workspaceCard(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                'المهام النشطة',
                active.toString(),
                Icons.bolt,
                _blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                'بانتظار موافقتك',
                pending.toString(),
                Icons.shield_outlined,
                _gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'BARQ Brain',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(0x332785FF),
                      child: Icon(Icons.auto_awesome, color: _blue),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مساعد المشروع والإطلاق',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(Icons.cloud_done_outlined, color: _gold),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'أرسل له مهمة لبناء برق معك، أو اطلب تحليلًا وخطة. يجري ربط معرفته بمصادر المشروع وإصداراتها؛ لا يدّعي معرفة ملف لم تتم فهرسته أو التحقق منه. التنفيذ المستمر يحتاج تهيئة خادم Preview.',
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1A2785FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _blue.withValues(alpha: .25)),
                  ),
                  child: const Text(
                    'إذن المالك الحالي: المرحلة الثانية مصرح بها. يعمل BARQ Brain على فهم BARQ وفهرسة المتطلبات والقرارات والبنية والكود وواجهات API والاختبارات وسجل المشكلات، مع إظهار مصادر المعرفة وما لم تتم تغطيته بعد. BARQ هو المنتج، وSPARK ميزة القصص فقط، وBARQ Admin تطبيق الإدارة المستقل. لا دمج أو نشر أو تغيير إنتاج دون موافقة محددة. اعتمد المالك Google OIDC مع PKCE لتسجيل الدخول؛ يجب أن يتحقق الخادم من الهوية والجلسة قبل السماح بالوصول.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _showBrainChat,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('تحدث مع BARQ Brain'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showCreateTask(assistant: true),
                  icon: const Icon(Icons.add),
                  label: const Text('إرسال مهمة للمساعد'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showVisionAnalysis,
                  icon: const Icon(Icons.image_search_outlined),
                  label: const Text('أرسل صورة لتحليلها'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showImageGeneration,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('اطلب من المساعد إنشاء صورة'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'آخر المهام',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => setState(() => _tab = 1),
              child: const Text('عرض الكل'),
            ),
          ],
        ),
        if (_tasks.isEmpty)
          _emptyState('لا توجد مهام بعد', 'ابدأ بإرسال أول مهمة إلى BARQ Brain')
        else
          ..._tasks.take(3).map(_taskTile),
      ],
    );
  }

  Widget _signInCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined, color: _gold, size: 34),
              const SizedBox(height: 10),
              const Text(
                'تسجيل دخول مالك BARQ Admin',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 7),
              const Text(
                'استخدم حساب Google المعتمد للمالك. سيُفتح تسجيل الدخول الآمن عبر المتصفح مع PKCE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _apiBase.isEmpty ? _showSettings : _loginWithGoogle,
                icon: const Icon(Icons.login),
                label: Text(
                  _apiBase.isEmpty
                      ? 'إعداد عنوان الخادم'
                      : 'المتابعة باستخدام Google',
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _showDevices() async {
    try {
      final data = await _getJson('/v1/devices');
      final devices = (data['devices'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('أجهزة المالك والجلسات'),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? const Text('لا توجد أجهزة مسجلة')
                : ListView(
                    shrinkWrap: true,
                    children: devices
                        .map(
                          (device) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.phone_android),
                            title: Text(
                              (device['device_name'] ?? 'جهاز').toString(),
                            ),
                            subtitle: Text(
                              (device['platform'] ?? '').toString() +
                                  ' • آخر نشاط: ' +
                                  (device['last_seen_at'] ?? '-').toString() +
                                  ((device['revoked_at'] == null)
                                      ? ''
                                      : ' • ملغى'),
                            ),
                            trailing: device['revoked_at'] == null
                                ? IconButton(
                                    tooltip: 'إبطال هذا الجهاز',
                                    icon: const Icon(
                                      Icons.block,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () async {
                                      final id =
                                          (device['id'] ?? '').toString();
                                      final response = await http
                                          .delete(
                                            Uri.parse(
                                              _base + '/v1/devices/' + id,
                                            ),
                                            headers: _headers,
                                          )
                                          .timeout(const Duration(seconds: 15));
                                      if (response.statusCode == 200 &&
                                          dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                        await _load();
                                      }
                                    },
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.white38,
                                  ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final response = await http
                    .post(
                      Uri.parse(_base + '/v1/devices/revoke-all'),
                      headers: _headers,
                    )
                    .timeout(const Duration(seconds: 15));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (response.statusCode == 200) await _logout();
              },
              child: const Text('إبطال جميع الأجهزة'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل الأجهزة: ' + error.toString())),
        );
    }
  }

  Widget _workspaceCard() {
    final project = (_workspace['current_project'] ?? 'BARQ').toString();
    final phase =
        (_workspace['current_phase'] ?? 'لم تُحدد المرحلة').toString();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF174C91), Color(0xFF15243E), Color(0xFF151E31)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: _gold, size: 28),
              const SizedBox(width: 8),
              const Text(
                'مساحة عمل المالك',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Icon(
                _online ? Icons.cloud_done : Icons.cloud_off,
                color: _online ? const Color(0xFF6DD6A4) : Colors.white60,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            project,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'آخر موضع محفوظ: ' + phase,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          const Text(
            'حالة المزامنة',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            _online
                ? 'متصل — الخادم هو المرجع الأساسي'
                : 'عرض آخر نسخة محفوظة على هذا الهاتف',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget _tasksView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'سجل المهام ونقاط التقدم',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'المهام التي وصلت إلى الخادم يمكن استعادتها من أي جهاز بعد تسجيل الدخول.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          if (_tasks.isEmpty)
            _emptyState(
              'قائمة المهام فارغة',
              'أضف مهمة جديدة أو أرسل طلبًا إلى BARQ Brain',
            )
          else
            ..._tasks.map(_taskTile),
        ],
      );

  Widget _taskTile(AdminTask task) {
    final local = task.status == 'draft_offline';
    final statusColor = local
        ? _gold
        : switch (task.status) {
            'completed' => const Color(0xFF6DD6A4),
            'failed' => const Color(0xFFFF8585),
            'needs_approval' => _gold,
            'running' => _blue,
            _ => Colors.white60,
          };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    local ? 'محلي' : task.status,
                    style: TextStyle(color: statusColor, fontSize: 11),
                  ),
                ),
              ],
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            if (task.nextAction.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                'التالي: ' + task.nextAction,
                style: const TextStyle(color: _gold, fontSize: 12),
              ),
            ],
            if (!local && task.checkpointVersion > 0) ...[
              const SizedBox(height: 5),
              Text(
                'نقطة التقدم ' + task.checkpointVersion.toString(),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _approvalsView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'موافقات المالك',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'لا ينشر المساعد ولا ينفق ولا يغيّر الإنتاج دون قرار واضح منك.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          if (_approvals.isEmpty)
            _emptyState(
              'لا توجد طلبات موافقة',
              'ستظهر هنا الإجراءات الحساسة قبل تنفيذها',
            )
          else
            ..._approvals.map(
              (approval) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              approval.actionType,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            approval.status,
                            style: TextStyle(
                              color: approval.status == 'pending'
                                  ? _gold
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text((approval.preview['summary'] ?? '').toString()),
                      const SizedBox(height: 5),
                      Text(
                        'الهدف: ' +
                            (approval.preview['target'] ?? '').toString(),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                      Text(
                        'البيئة: ' +
                            (approval.preview['environment'] ?? '').toString(),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                      if (approval.status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _decideApproval(approval.id, 'rejected'),
                                child: const Text('رفض'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    _decideApproval(approval.id, 'approved'),
                                child: const Text('موافقة'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _auditView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'سجل النشاط والتدقيق',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'سجل للقراءة فقط للأحداث المسجلة على مساحة إدارة BARQ.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          if (_auditEvents.isEmpty)
            _emptyState(
              'لا توجد أحداث مسجلة',
              'ستظهر هنا تغييرات مساحة العمل والمهام والموافقات',
            )
          else
            ..._auditEvents.map((event) {
              final created = (event['created_at'] ?? '').toString();
              final details = event['details'] is Map
                  ? Map<String, dynamic>.from(event['details'] as Map)
                  : <String, dynamic>{};
              return Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (event['event_type'] ?? 'event').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _gold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'الهدف: ${event['target_type'] ?? '-'} / ${event['target_id'] ?? '-'}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details.entries
                              .map((entry) => '${entry.key}: ${entry.value}')
                              .join(' • '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                      if (created.isNotEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            created,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      );

  Widget _emptyState(String title, String subtitle) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, color: Colors.white38, size: 36),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
), '');
      if (!isValidAdminApiBase(input)) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('أدخل عنوان HTTPS صحيحًا لخادم الإدارة'),
            ),
          );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('barq_admin_api_base', base);
        await _load();
      }
    }
    baseController.dispose();
  }

  Future<String> _requestImageAnalysis(
    Uint8List bytes,
    String mimeType,
    String prompt,
  ) async {
    if (_apiBase.isEmpty || _token.isEmpty || !isValidAdminApiBase(_apiBase)) {
      throw Exception('أكمل إعداد اتصال HTTPS وجلسة المالك أولًا');
    }
    if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw Exception('حجم الصورة يجب ألا يتجاوز 4 ميغابايت');
    }
    final response = await http
        .post(
          Uri.parse(_base + '/v1/brain/vision'),
          headers: _headers,
          body: jsonEncode({
            'prompt': prompt.trim().isEmpty
                ? 'حلل هذه الصورة واشرح ما يظهر فيها.'
                : prompt.trim(),
            'image': 'data:' + mimeType + ';base64,' + base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 90));
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'استجابة الخادم غير مفهومة؛ تحقق من اتصال Preview ثم أعد المحاولة',
      );
    }
    if (response.statusCode != 200) {
      final message = data is Map && data['error'] == 'admin_ai_unavailable'
          ? 'خدمة الذكاء الاصطناعي غير مهيأة على الخادم بعد'
          : data is Map && data['error'] == 'vision_model_license_required'
              ? 'يلزم تفعيل اتفاقية ترخيص نموذج الرؤية في حساب Cloudflare قبل استخدام تحليل الصور'
              : data is Map && data['error'] == 'image_too_large'
                  ? 'الصورة أكبر من الحد المسموح'
                  : data is Map && data['error'] == 'invalid_image_or_prompt'
                      ? 'صيغة الصورة غير مدعومة أو لا يطابق محتواها نوعها؛ استخدم JPEG أو PNG أو WebP'
                      : data is Map && data['error'] == 'vision_analysis_failed'
                          ? 'تعذر على نموذج الرؤية تحليل الصورة؛ جرّب صورة أوضح أو أعد المحاولة'
                          : 'تعذر تحليل الصورة (' +
                              response.statusCode.toString() +
                              ')';
      throw Exception(message);
    }
    final answer = data is Map ? (data['answer'] ?? '').toString().trim() : '';
    if (answer.isEmpty) throw Exception('لم يُرجع المساعد نتيجة');
    return answer;
  }

  Future<Uint8List> _requestImageGeneration(String prompt) async {
    if (_apiBase.isEmpty || _token.isEmpty || !isValidAdminApiBase(_apiBase)) {
      throw Exception('أكمل إعداد اتصال HTTPS وجلسة المالك أولًا');
    }
    final response = await http
        .post(
          Uri.parse(_base + '/v1/brain/generate-image'),
          headers: _headers,
          body: jsonEncode({'prompt': prompt.trim()}),
        )
        .timeout(const Duration(seconds: 180));
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'استجابة الخادم غير مفهومة؛ تحقق من اتصال Preview ثم أعد المحاولة',
      );
    }
    if (response.statusCode != 200) {
      final message = data is Map && data['error'] == 'admin_ai_unavailable'
          ? 'خدمة الذكاء الاصطناعي غير مهيأة على الخادم بعد'
          : data is Map && data['error'] == 'invalid_image_prompt'
              ? 'اكتب وصفًا للصورة لا يتجاوز 1600 حرف'
              : data is Map &&
                      data['error'] == 'image_generation_model_terms_required'
                  ? 'يلزم قبول شروط نموذج إنشاء الصور في حساب Cloudflare قبل استخدامه'
                  : data is Map && data['error'] == 'image_generation_failed'
                      ? 'تعذر إنشاء الصورة؛ تحقق من تفعيل Workers AI ثم أعد المحاولة'
                      : 'تعذر إنشاء الصورة (' +
                          response.statusCode.toString() +
                          ')';
      throw Exception(message);
    }
    final imageUri = data is Map ? (data['image'] ?? '').toString() : '';
    const prefix = 'data:image/jpeg;base64,';
    if (!imageUri.startsWith(prefix))
      throw Exception('لم يُرجع المساعد ملف صورة صالحًا');
    final bytes = base64Decode(imageUri.substring(prefix.length));
    if (bytes.length < 4 ||
        bytes.length > 8 * 1024 * 1024 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[2] != 0xff) {
      throw Exception('ملف الصورة الناتج غير صالح أو يتجاوز الحجم المسموح');
    }
    return bytes;
  }

  Future<void> _showBrainChat() async {
    if (_token.isEmpty || !_online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اتصل بخادم BARQ Admin أولًا لبدء محادثة محفوظة'),
        ),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    String? conversationId =
        prefs.getString('barq_admin_brain_conversation_id');
    final controller = TextEditingController();
    final messages = <Map<String, String>>[];
    var sending = false;

    if (conversationId != null && conversationId.isNotEmpty) {
      try {
        final history = await _getJson(
          '/v1/brain/conversations/$conversationId/messages',
        );
        for (final item in (history['messages'] as List? ?? const [])) {
          if (item is Map) {
            var content = (item['content'] ?? '').toString();
            final sources = item['sources'];
            if (sources is List && sources.isNotEmpty) {
              final references = sources.whereType<Map>().map((source) {
                final path = (source['sourcePath'] ?? '').toString();
                final revision = (source['sourceRevision'] ?? '').toString();
                return revision.isEmpty
                    ? '• ' + path
                    : '• ' + path + ' @ ' + revision;
              }).join('\\n');
              content += '\\n\\nالمصادر التي استند إليها:\\n' + references;
            }
            messages.add({
              'role': (item['role'] ?? 'assistant').toString(),
              'content': content,
            });
          }
        }
      } catch (_) {
        conversationId = null;
        await prefs.remove('barq_admin_brain_conversation_id');
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> sendMessage() async {
            final prompt = controller.text.trim();
            if (prompt.isEmpty || sending) return;
            controller.clear();
            setDialogState(() {
              messages.add({'role': 'user', 'content': prompt});
              sending = true;
            });
            try {
              Future<http.Response> submit() => http
                  .post(
                    Uri.parse(_base + '/v1/brain/chat'),
                    headers: _headers,
                    body: jsonEncode({
                      'message': prompt,
                      if (conversationId != null)
                        'conversationId': conversationId,
                    }),
                  )
                  .timeout(const Duration(seconds: 90));
              var response = await submit();
              if (response.statusCode == 401 && await _refreshSession()) {
                response = await submit();
              }
              final data = Map<String, dynamic>.from(
                jsonDecode(response.body) as Map,
              );
              final returnedConversationId =
                  (data['conversationId'] ?? '').toString();
              if (returnedConversationId.isNotEmpty) {
                conversationId = returnedConversationId;
                await prefs.setString(
                  'barq_admin_brain_conversation_id',
                  returnedConversationId,
                );
              }
              if (response.statusCode != 200) {
                throw Exception(
                  (data['error'] ?? 'تعذر الحصول على رد المساعد').toString(),
                );
              }
              if (conversationId == null || conversationId!.isEmpty) {
                throw Exception('لم يُرجع الخادم رقم المحادثة');
              }
              var answer = (data['answer'] ?? '').toString();
              final sources = data['sources'];
              if (sources is List && sources.isNotEmpty) {
                final references = sources.whereType<Map>().map((source) {
                  final path = (source['sourcePath'] ?? '').toString();
                  final revision = (source['sourceRevision'] ?? '').toString();
                  return revision.isEmpty
                      ? '• ' + path
                      : '• ' + path + ' @ ' + revision;
                }).join('\n');
                answer += '\n\nالمصادر التي استند إليها:\n' + references;
              }
              setDialogState(() {
                messages.add({'role': 'assistant', 'content': answer});
              });
            } catch (error) {
              setDialogState(() {
                messages.add({
                  'role': 'error',
                  'content': error.toString().replaceFirst('Exception: ', ''),
                });
              });
            } finally {
              setDialogState(() => sending = false);
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 620,
              height: MediaQuery.of(dialogContext).size.height * .82,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0x332785FF),
                          child: Icon(Icons.auto_awesome, color: _blue),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'محادثة BARQ Brain',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                        ),
                        TextButton(
                          onPressed: sending
                              ? null
                              : () async {
                                  conversationId = null;
                                  messages.clear();
                                  await prefs.remove(
                                      'barq_admin_brain_conversation_id');
                                  setDialogState(() {});
                                },
                          child: const Text('محادثة جديدة'),
                        ),
                        IconButton(
                          onPressed: sending
                              ? null
                              : () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: messages.isEmpty
                          ? const Center(
                              child: Text(
                                'ابدأ بسؤالي عن برق أو اطلب مني مراجعة مشكلة أو بناء ميزة. سأستند إلى مصادر المشروع المفهرسة وأوضح ما لم أتحقق منه.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final item = messages[index];
                                final role = item['role'];
                                final isOwner = role == 'user';
                                final isError = role == 'error';
                                return Align(
                                  alignment: isOwner
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 520),
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isError
                                          ? Colors.red.withValues(alpha: .15)
                                          : isOwner
                                              ? _blue.withValues(alpha: .20)
                                              : _surface,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child:
                                        SelectableText(item['content'] ?? ''),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (sending)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('BARQ Brain يراجع سياق المشروع ويكتب الرد...'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك إلى BARQ Brain...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: sending ? null : sendMessage,
                        icon: const Icon(Icons.send),
                        label: const Text('إرسال'),
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
    controller.dispose();
  }

  Future<void> _showImageGeneration() async {
    if (_apiBase.isEmpty || _token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اضبط اتصال الخادم وجلسة المالك أولًا')),
      );
      return;
    }
    final promptController = TextEditingController();
    Uint8List? generatedBytes;
    bool busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .86,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'إنشاء صورة مع BARQ Brain',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اكتب وصفًا واضحًا للصورة. سيُنشئها المساعد ثم يعرضها هنا لتتمكن من مشاركتها أو إرسالها من هاتفك.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: promptController,
                      maxLines: 4,
                      maxLength: 1600,
                      decoration: const InputDecoration(
                        labelText: 'صف الصورة التي تريد إنشاءها',
                        hintText:
                            'مثال: مشهد سينمائي لمدينة مستقبلية يضيئها البرق الأزرق...',
                      ),
                    ),
                    if (generatedBytes != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          generatedBytes!,
                          fit: BoxFit.contain,
                          height: 300,
                          width: double.infinity,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await Share.shareXFiles([
                              XFile.fromData(
                                generatedBytes!,
                                mimeType: 'image/jpeg',
                                name: 'barq-brain-image.jpg',
                              ),
                            ], text: 'صورة أنشأها BARQ Brain');
                          } catch (error) {
                            if (mounted)
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تعذرت مشاركة الصورة: ' + error.toString(),
                                  ),
                                ),
                              );
                          }
                        },
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('مشاركة الصورة أو إرسالها'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final prompt = promptController.text.trim();
                              if (prompt.isEmpty) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('اكتب وصف الصورة أولًا'),
                                  ),
                                );
                                return;
                              }
                              setSheetState(() {
                                busy = true;
                                generatedBytes = null;
                              });
                              try {
                                final image = await _requestImageGeneration(
                                  prompt,
                                );
                                if (sheetContext.mounted)
                                  setSheetState(() {
                                    generatedBytes = image;
                                    busy = false;
                                  });
                              } catch (error) {
                                if (sheetContext.mounted)
                                  setSheetState(() => busy = false);
                                if (mounted)
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.toString().replaceFirst(
                                              'Exception: ',
                                              '',
                                            ),
                                      ),
                                    ),
                                  );
                              }
                            },
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        busy
                            ? 'جارٍ إنشاء الصورة...'
                            : generatedBytes == null
                                ? 'أنشئ الصورة'
                                : 'أنشئ صورة أخرى',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          busy ? null : () => Navigator.pop(sheetContext),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    promptController.dispose();
  }

  Future<void> _showVisionAnalysis() async {
    if (_apiBase.isEmpty || _token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اضبط اتصال الخادم وجلسة المالك أولًا')),
      );
      return;
    }
    final picker = ImagePicker();
    final promptController = TextEditingController(
      text: 'حلل الصورة بالتفصيل، واشرح العناصر المهمة وأي نص ظاهر فيها.',
    );
    Uint8List? selectedBytes;
    String selectedMime = 'image/jpeg';
    String selectedName = '';
    bool busy = false;
    String? result;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .82,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تحليل صورة مع BARQ Brain',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختر صورة من المعرض أو التقط صورة بالكاميرا. الحد الأقصى 4 ميغابايت، ولا تُحفظ الصورة على الخادم.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    if (selectedBytes == null)
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: const Color(0xFF202B42),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 42,
                              color: Colors.white54,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'لم يتم اختيار صورة بعد',
                              style: TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          selectedBytes!,
                          height: 210,
                          fit: BoxFit.contain,
                        ),
                      ),
                    if (selectedName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        selectedName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    final file = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 82,
                                      maxWidth: 1920,
                                      maxHeight: 1920,
                                    );
                                    if (file == null) return;
                                    final bytes = await file.readAsBytes();
                                    final ext =
                                        file.name.toLowerCase().split('.').last;
                                    final mime = ext == 'png'
                                        ? 'image/png'
                                        : ext == 'webp'
                                            ? 'image/webp'
                                            : (ext == 'jpg' || ext == 'jpeg')
                                                ? 'image/jpeg'
                                                : '';
                                    if (mime.isEmpty) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'صيغة الصورة غير مدعومة؛ استخدم JPEG أو PNG أو WebP',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (bytes.length > 4 * 1024 * 1024) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'اختر صورة لا تتجاوز 4 ميغابايت',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setSheetState(() {
                                      selectedBytes = bytes;
                                      selectedMime = mime;
                                      selectedName = file.name;
                                    });
                                  },
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('المعرض'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    final file = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 82,
                                      maxWidth: 1920,
                                      maxHeight: 1920,
                                    );
                                    if (file == null) return;
                                    final bytes = await file.readAsBytes();
                                    final ext =
                                        file.name.toLowerCase().split('.').last;
                                    final mime = ext == 'png'
                                        ? 'image/png'
                                        : ext == 'webp'
                                            ? 'image/webp'
                                            : (ext == 'jpg' || ext == 'jpeg')
                                                ? 'image/jpeg'
                                                : '';
                                    if (mime.isEmpty) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'صيغة الصورة غير مدعومة؛ استخدم JPEG أو PNG أو WebP',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (bytes.length > 4 * 1024 * 1024) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'اختر صورة لا تتجاوز 4 ميغابايت',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setSheetState(() {
                                      selectedBytes = bytes;
                                      selectedMime = mime;
                                      selectedName = file.name;
                                    });
                                  },
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('الكاميرا'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: promptController,
                      maxLines: 3,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'ماذا تريد أن تعرف عن الصورة؟',
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: busy || selectedBytes == null
                          ? null
                          : () async {
                              setSheetState(() => busy = true);
                              try {
                                result = await _requestImageAnalysis(
                                  selectedBytes!,
                                  selectedMime,
                                  promptController.text,
                                );
                                if (sheetContext.mounted)
                                  Navigator.pop(sheetContext);
                                if (mounted && result != null) {
                                  await showDialog<void>(
                                    context: this.context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('نتيجة تحليل الصورة'),
                                      content: SingleChildScrollView(
                                        child: SelectableText(result!),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('إغلاق'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              } catch (error) {
                                setSheetState(() => busy = false);
                                if (mounted)
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.toString().replaceFirst(
                                              'Exception: ',
                                              '',
                                            ),
                                      ),
                                    ),
                                  );
                              }
                            },
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        busy ? 'جارٍ تحليل الصورة...' : 'حلّل الصورة',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    promptController.dispose();
  }

  Future<void> _showCreateTask({bool assistant = false}) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              assistant ? 'مهمة جديدة إلى BARQ Brain' : 'إضافة مهمة',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: assistant
                    ? 'ما الذي تريد من المساعد إنجازه؟'
                    : 'عنوان المهمة',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'التفاصيل والسياق'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ المهمة'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final title = titleController.text.trim();
      final details = descriptionController.text.trim();
      await _createTask(
        assistant && !title.startsWith('BARQ Brain')
            ? 'BARQ Brain: ' + title
            : title,
        details,
      );
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BARQ Admin',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
            ),
            Text(
              _connectionMessage,
              style: TextStyle(
                fontSize: 11,
                color: _online ? const Color(0xFF6DD6A4) : Colors.white60,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إعدادات الاتصال',
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'الأجهزة',
            onPressed: _token.isEmpty ? null : _showDevices,
            icon: const Icon(Icons.devices_outlined),
          ),
          IconButton(
            tooltip: 'إنهاء الجلسة',
            onPressed: _token.isEmpty ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _tasks.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _tab,
                children: [
                  _dashboard(),
                  _tasksView(),
                  _approvalsView(),
                  _auditView(),
                ],
              ),
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateTask(),
              icon: const Icon(Icons.add),
              label: const Text('مهمة جديدة'),
            )
          : _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showCreateTask(assistant: true),
                  icon: const Icon(Icons.bolt),
                  label: const Text('اسأل BARQ Brain'),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'المهام'),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            label: 'الموافقات',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'السجل',
          ),
        ],
      ),
    );
  }

  Widget _dashboard() {
    final pending = _approvals.where((item) => item.status == 'pending').length;
    final active = _tasks
        .where(
          (task) => [
            'queued',
            'running',
            'paused',
            'needs_approval',
          ].contains(task.status),
        )
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (_token.isEmpty) _signInCard(),
        _workspaceCard(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                'المهام النشطة',
                active.toString(),
                Icons.bolt,
                _blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                'بانتظار موافقتك',
                pending.toString(),
                Icons.shield_outlined,
                _gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'BARQ Brain',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(0x332785FF),
                      child: Icon(Icons.auto_awesome, color: _blue),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مساعد المشروع والإطلاق',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(Icons.cloud_done_outlined, color: _gold),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'أرسل له مهمة لبناء برق معك، أو اطلب تحليلًا وخطة. يجري ربط معرفته بمصادر المشروع وإصداراتها؛ لا يدّعي معرفة ملف لم تتم فهرسته أو التحقق منه. التنفيذ المستمر يحتاج تهيئة خادم Preview.',
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1A2785FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _blue.withValues(alpha: .25)),
                  ),
                  child: const Text(
                    'إذن المالك الحالي: المرحلة الثانية مصرح بها. يعمل BARQ Brain على فهم BARQ وفهرسة المتطلبات والقرارات والبنية والكود وواجهات API والاختبارات وسجل المشكلات، مع إظهار مصادر المعرفة وما لم تتم تغطيته بعد. BARQ هو المنتج، وSPARK ميزة القصص فقط، وBARQ Admin تطبيق الإدارة المستقل. لا دمج أو نشر أو تغيير إنتاج دون موافقة محددة. اعتمد المالك Google OIDC مع PKCE لتسجيل الدخول؛ يجب أن يتحقق الخادم من الهوية والجلسة قبل السماح بالوصول.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _showBrainChat,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('تحدث مع BARQ Brain'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showCreateTask(assistant: true),
                  icon: const Icon(Icons.add),
                  label: const Text('إرسال مهمة للمساعد'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showVisionAnalysis,
                  icon: const Icon(Icons.image_search_outlined),
                  label: const Text('أرسل صورة لتحليلها'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showImageGeneration,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('اطلب من المساعد إنشاء صورة'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'آخر المهام',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => setState(() => _tab = 1),
              child: const Text('عرض الكل'),
            ),
          ],
        ),
        if (_tasks.isEmpty)
          _emptyState('لا توجد مهام بعد', 'ابدأ بإرسال أول مهمة إلى BARQ Brain')
        else
          ..._tasks.take(3).map(_taskTile),
      ],
    );
  }

  Widget _signInCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined, color: _gold, size: 34),
              const SizedBox(height: 10),
              const Text(
                'تسجيل دخول مالك BARQ Admin',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 7),
              const Text(
                'استخدم حساب Google المعتمد للمالك. سيُفتح تسجيل الدخول الآمن عبر المتصفح مع PKCE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _apiBase.isEmpty ? _showSettings : _loginWithGoogle,
                icon: const Icon(Icons.login),
                label: Text(
                  _apiBase.isEmpty
                      ? 'إعداد عنوان الخادم'
                      : 'المتابعة باستخدام Google',
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _showDevices() async {
    try {
      final data = await _getJson('/v1/devices');
      final devices = (data['devices'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('أجهزة المالك والجلسات'),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? const Text('لا توجد أجهزة مسجلة')
                : ListView(
                    shrinkWrap: true,
                    children: devices
                        .map(
                          (device) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.phone_android),
                            title: Text(
                              (device['device_name'] ?? 'جهاز').toString(),
                            ),
                            subtitle: Text(
                              (device['platform'] ?? '').toString() +
                                  ' • آخر نشاط: ' +
                                  (device['last_seen_at'] ?? '-').toString() +
                                  ((device['revoked_at'] == null)
                                      ? ''
                                      : ' • ملغى'),
                            ),
                            trailing: device['revoked_at'] == null
                                ? IconButton(
                                    tooltip: 'إبطال هذا الجهاز',
                                    icon: const Icon(
                                      Icons.block,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () async {
                                      final id =
                                          (device['id'] ?? '').toString();
                                      final response = await http
                                          .delete(
                                            Uri.parse(
                                              _base + '/v1/devices/' + id,
                                            ),
                                            headers: _headers,
                                          )
                                          .timeout(const Duration(seconds: 15));
                                      if (response.statusCode == 200 &&
                                          dialogContext.mounted) {
                                        Navigator.pop(dialogContext);
                                        await _load();
                                      }
                                    },
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.white38,
                                  ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final response = await http
                    .post(
                      Uri.parse(_base + '/v1/devices/revoke-all'),
                      headers: _headers,
                    )
                    .timeout(const Duration(seconds: 15));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (response.statusCode == 200) await _logout();
              },
              child: const Text('إبطال جميع الأجهزة'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل الأجهزة: ' + error.toString())),
        );
    }
  }

  Widget _workspaceCard() {
    final project = (_workspace['current_project'] ?? 'BARQ').toString();
    final phase =
        (_workspace['current_phase'] ?? 'لم تُحدد المرحلة').toString();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF174C91), Color(0xFF15243E), Color(0xFF151E31)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: _gold, size: 28),
              const SizedBox(width: 8),
              const Text(
                'مساحة عمل المالك',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Icon(
                _online ? Icons.cloud_done : Icons.cloud_off,
                color: _online ? const Color(0xFF6DD6A4) : Colors.white60,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            project,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'آخر موضع محفوظ: ' + phase,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          const Text(
            'حالة المزامنة',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            _online
                ? 'متصل — الخادم هو المرجع الأساسي'
                : 'عرض آخر نسخة محفوظة على هذا الهاتف',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget _tasksView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'سجل المهام ونقاط التقدم',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'المهام التي وصلت إلى الخادم يمكن استعادتها من أي جهاز بعد تسجيل الدخول.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          if (_tasks.isEmpty)
            _emptyState(
              'قائمة المهام فارغة',
              'أضف مهمة جديدة أو أرسل طلبًا إلى BARQ Brain',
            )
          else
            ..._tasks.map(_taskTile),
        ],
      );

  Widget _taskTile(AdminTask task) {
    final local = task.status == 'draft_offline';
    final statusColor = local
        ? _gold
        : switch (task.status) {
            'completed' => const Color(0xFF6DD6A4),
            'failed' => const Color(0xFFFF8585),
            'needs_approval' => _gold,
            'running' => _blue,
            _ => Colors.white60,
          };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    local ? 'محلي' : task.status,
                    style: TextStyle(color: statusColor, fontSize: 11),
                  ),
                ),
              ],
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            if (task.nextAction.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                'التالي: ' + task.nextAction,
                style: const TextStyle(color: _gold, fontSize: 12),
              ),
            ],
            if (!local && task.checkpointVersion > 0) ...[
              const SizedBox(height: 5),
              Text(
                'نقطة التقدم ' + task.checkpointVersion.toString(),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _approvalsView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'موافقات المالك',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'لا ينشر المساعد ولا ينفق ولا يغيّر الإنتاج دون قرار واضح منك.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          if (_approvals.isEmpty)
            _emptyState(
              'لا توجد طلبات موافقة',
              'ستظهر هنا الإجراءات الحساسة قبل تنفيذها',
            )
          else
            ..._approvals.map(
              (approval) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              approval.actionType,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            approval.status,
                            style: TextStyle(
                              color: approval.status == 'pending'
                                  ? _gold
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text((approval.preview['summary'] ?? '').toString()),
                      const SizedBox(height: 5),
                      Text(
                        'الهدف: ' +
                            (approval.preview['target'] ?? '').toString(),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                      Text(
                        'البيئة: ' +
                            (approval.preview['environment'] ?? '').toString(),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                      if (approval.status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _decideApproval(approval.id, 'rejected'),
                                child: const Text('رفض'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    _decideApproval(approval.id, 'approved'),
                                child: const Text('موافقة'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _auditView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'سجل النشاط والتدقيق',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'سجل للقراءة فقط للأحداث المسجلة على مساحة إدارة BARQ.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 14),
          if (_auditEvents.isEmpty)
            _emptyState(
              'لا توجد أحداث مسجلة',
              'ستظهر هنا تغييرات مساحة العمل والمهام والموافقات',
            )
          else
            ..._auditEvents.map((event) {
              final created = (event['created_at'] ?? '').toString();
              final details = event['details'] is Map
                  ? Map<String, dynamic>.from(event['details'] as Map)
                  : <String, dynamic>{};
              return Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (event['event_type'] ?? 'event').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _gold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'الهدف: ${event['target_type'] ?? '-'} / ${event['target_id'] ?? '-'}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details.entries
                              .map((entry) => '${entry.key}: ${entry.value}')
                              .join(' • '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                      if (created.isNotEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            created,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      );

  Widget _emptyState(String title, String subtitle) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, color: Colors.white38, size: 36),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
