import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'security.dart';

const _blue = Color(0xFF2785FF);
const _gold = Color(0xFFE8B95B);
const _surface = Color(0xFF151E31);
const _background = Color(0xFF0A1020);

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
      colorScheme: ColorScheme.fromSeed(seedColor: _blue, brightness: Brightness.dark, surface: _surface),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF202B42),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
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

class _AdminHomePageState extends State<AdminHomePage> with WidgetsBindingObserver {
  static const _secure = FlutterSecureStorage();
  static const _cacheWorkspace = 'barq_admin_workspace_cache';
  static const _cacheTasks = 'barq_admin_tasks_cache';
  static const _cacheApprovals = 'barq_admin_approvals_cache';
  static const _cacheAudit = 'barq_admin_audit_cache';
  static const _outboxKey = 'barq_admin_task_outbox';

  String _apiBase = '';
  String _token = '';
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
    _readCache(prefs);
    if (_apiBase.isEmpty || _token.isEmpty) {
      if (mounted) setState(() {
        _loading = false;
        _online = false;
        _connectionMessage = 'أكمل إعداد الاتصال';
      });
      return;
    }
    if (!isValidAdminApiBase(_apiBase)) {
      if (mounted) setState(() {
        _loading = false;
        _online = false;
        _connectionMessage = 'عنوان الخادم غير آمن؛ استخدم HTTPS صحيحًا';
      });
      return;
    }
    if (mounted) setState(() {
      _loading = true;
      _connectionMessage = 'جارٍ المزامنة';
    });
    try {
      await _syncOutbox(prefs);
      final workspaceResponse = await http.get(
        Uri.parse(_base + '/v1/workspace'), headers: _headers,
      ).timeout(const Duration(seconds: 18));
      if (workspaceResponse.statusCode == 401) {
        throw Exception('انتهت صلاحية جلسة المالك؛ أعد تسجيل الدخول');
      }
      if (workspaceResponse.statusCode != 200) {
        throw Exception('تعذر تحميل مساحة العمل (' + workspaceResponse.statusCode.toString() + ')');
      }
      final workspaceData = jsonDecode(workspaceResponse.body) as Map<String, dynamic>;
      final taskData = await _getJson('/v1/tasks');
      final approvalData = await _getJson('/v1/approvals');
      final auditData = await _getJson('/v1/audit');
      _workspace = Map<String, dynamic>.from(workspaceData['workspace'] as Map? ?? {});
      _tasks = (taskData['tasks'] as List? ?? [])
        .whereType<Map>().map((item) => AdminTask.fromJson(Map<String, dynamic>.from(item))).toList();
      _approvals = (approvalData['approvals'] as List? ?? [])
        .whereType<Map>().map((item) => AdminApproval.fromJson(Map<String, dynamic>.from(item))).toList();
      _auditEvents = (auditData['events'] as List? ?? [])
        .whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      await prefs.setString(_cacheWorkspace, jsonEncode(_workspace));
      await prefs.setString(_cacheTasks, jsonEncode(_tasks.map((task) => task.toJson()).toList()));
      await prefs.setString(_cacheApprovals, jsonEncode(approvalData['approvals'] ?? []));
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
      if (workspace != null) _workspace = Map<String, dynamic>.from(jsonDecode(workspace) as Map);
      final tasks = prefs.getString(_cacheTasks);
      if (tasks != null) {
        _tasks = (jsonDecode(tasks) as List).whereType<Map>()
          .map((item) => AdminTask.fromJson(Map<String, dynamic>.from(item))).toList();
      }
      final audit = prefs.getString(_cacheAudit);
      if (audit != null) _auditEvents = (jsonDecode(audit) as List).whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
      final approvals = prefs.getString(_cacheApprovals);
      if (approvals != null) {
        _approvals = (jsonDecode(approvals) as List).whereType<Map>()
          .map((item) => AdminApproval.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (_) {
      // The server remains authoritative if a local cache is damaged.
    }
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await http.get(Uri.parse(_base + path), headers: _headers)
      .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw Exception('تعذر تحميل البيانات (' + response.statusCode.toString() + ')');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> _syncOutbox(SharedPreferences prefs) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final raw = prefs.getString(_outboxKey);
      if (raw == null) return;
      final pending = (jsonDecode(raw) as List).whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
      final remaining = <Map<String, dynamic>>[];
      for (final item in pending) {
        try {
          final response = await http.post(
            Uri.parse(_base + '/v1/tasks'),
            headers: {..._headers, 'X-Idempotency-Key': item['idempotencyKey'].toString()},
            body: jsonEncode({
              'title': item['title'],
              'description': item['description'],
              'priority': item['priority'] ?? 'normal',
            }),
          ).timeout(const Duration(seconds: 18));
          if (response.statusCode < 200 || response.statusCode >= 300) remaining.add(item);
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
      '-' + Random.secure().nextInt(1 << 32).toString();
    final payload = {
      'title': cleanTitle,
      'description': description.trim(),
      'priority': 'normal',
      'idempotencyKey': idempotencyKey,
    };
    if (_online && _apiBase.isNotEmpty && _token.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse(_base + '/v1/tasks'),
          headers: {..._headers, 'X-Idempotency-Key': idempotencyKey},
          body: jsonEncode({
            'title': cleanTitle,
            'description': description.trim(),
            'priority': 'normal',
          }),
        ).timeout(const Duration(seconds: 18));
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
    final pending = raw == null ? <Map<String, dynamic>>[] :
      (jsonDecode(raw) as List).whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item)).toList();
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
        const SnackBar(content: Text('حُفظت المهمة على هذا الهاتف وستُزامن عند عودة الاتصال')),
      );
    }
  }

  Future<void> _decideApproval(String id, String status) async {
    try {
      final response = await http.patch(
        Uri.parse(_base + '/v1/approvals/' + id),
        headers: _headers,
        body: jsonEncode({'status': status}),
      ).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) throw Exception('تعذر حفظ القرار');
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إنهاء جلسة الإدارة؟'),
        content: const Text('سيُحذف رمز الجلسة والبيانات المخزنة محليًا من هذا الهاتف. المهام التي لم تُرسل بعد ستُحذف أيضًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إنهاء الجلسة')),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: 'barq_admin_owner_token');
    for (final key in [_cacheWorkspace, _cacheTasks, _cacheApprovals, _cacheAudit, _outboxKey]) {
      await prefs.remove(key);
    }
    await prefs.remove('barq_admin_api_base');
    if (!mounted) return;
    setState(() {
      _apiBase = '';
      _token = '';
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
    final tokenController = TextEditingController(text: _token);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إعداد الاتصال الآمن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('عنوان خادم الإدارة ورمز جلسة المالك. لا تضع أسرار الخادم هنا.'),
            const SizedBox(height: 16),
            TextField(controller: baseController, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'عنوان خادم BARQ Admin')),
            const SizedBox(height: 12),
            TextField(controller: tokenController, obscureText: true,
              decoration: const InputDecoration(labelText: 'رمز جلسة المالك')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ الاتصال')),
          ],
        ),
      ),
    );
    if (saved == true) {
      final base = baseController.text.trim().replaceFirst(RegExp(r'/+$'), '');
      if (!isValidAdminApiBase(base) || tokenController.text.trim().isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل عنوان HTTPS صحيحًا ورمز جلسة غير فارغ')),
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('barq_admin_api_base', base);
        await _secure.write(key: 'barq_admin_owner_token', value: tokenController.text.trim());
        await _load();
      }
    }
    baseController.dispose();
    tokenController.dispose();
  }

  Future<String> _requestImageAnalysis(Uint8List bytes, String mimeType, String prompt) async {
    if (_apiBase.isEmpty || _token.isEmpty || !isValidAdminApiBase(_apiBase)) {
      throw Exception('أكمل إعداد اتصال HTTPS وجلسة المالك أولًا');
    }
    if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw Exception('حجم الصورة يجب ألا يتجاوز 4 ميغابايت');
    }
    final response = await http.post(
      Uri.parse(_base + '/v1/brain/vision'),
      headers: _headers,
      body: jsonEncode({
        'prompt': prompt.trim().isEmpty ? 'حلل هذه الصورة واشرح ما يظهر فيها.' : prompt.trim(),
        'image': 'data:' + mimeType + ';base64,' + base64Encode(bytes),
      }),
    ).timeout(const Duration(seconds: 90));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = data is Map && data['error'] == 'admin_ai_unavailable'
          ? 'خدمة الذكاء الاصطناعي غير مهيأة على الخادم بعد'
          : data is Map && data['error'] == 'vision_model_license_required'
              ? 'يلزم تفعيل اتفاقية ترخيص نموذج الرؤية في حساب Cloudflare قبل استخدام تحليل الصور'
              : data is Map && data['error'] == 'image_too_large'
                  ? 'الصورة أكبر من الحد المسموح'
                  : data is Map && data['error'] == 'vision_rate_limited'
                      ? 'وصلت إلى الحد المؤقت: ثلاث صور في الدقيقة. انتظر قليلًا ثم حاول مجددًا'
                      : 'تعذر تحليل الصورة (' + response.statusCode.toString() + ')';
      throw Exception(message);
    }
    final answer = data is Map ? (data['answer'] ?? '').toString().trim() : '';
    if (answer.isEmpty) throw Exception('لم يُرجع المساعد نتيجة');
    return answer;
  }

  Future<void> _showVisionAnalysis() async {
    if (_apiBase.isEmpty || _token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اضبط اتصال الخادم وجلسة المالك أولًا')),
      );
      return;
    }
    final picker = ImagePicker();
    final promptController = TextEditingController(text: 'حلل الصورة بالتفصيل، واشرح العناصر المهمة وأي نص ظاهر فيها.');
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
            padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .82),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تحليل صورة مع BARQ Brain',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('اختر صورة من المعرض أو التقط صورة بالكاميرا. الحد الأقصى 4 ميغابايت، ولا تُحفظ الصورة على الخادم.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 14),
                    if (selectedBytes == null)
                      Container(
                        height: 150,
                        decoration: BoxDecoration(color: const Color(0xFF202B42),
                          borderRadius: BorderRadius.circular(16)),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 42, color: Colors.white54),
                          SizedBox(height: 8),
                          Text('لم يتم اختيار صورة بعد', style: TextStyle(color: Colors.white60)),
                        ]),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(selectedBytes!, height: 210, fit: BoxFit.contain),
                      ),
                    if (selectedName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(selectedName, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: busy ? null : () async {
                          final file = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 82,
                            maxWidth: 1920,
                            maxHeight: 1920,
                          );
                          if (file == null) return;
                          final bytes = await file.readAsBytes();
                          final ext = file.name.toLowerCase().split('.').last;
                          final mime = ext == 'png' ? 'image/png' :
                            ext == 'webp' ? 'image/webp' :
                            (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : '';
                          if (mime.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('صيغة الصورة غير مدعومة؛ استخدم JPEG أو PNG أو WebP')),
                            );
                            return;
                          }
                          if (bytes.length > 4 * 1024 * 1024) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('اختر صورة لا تتجاوز 4 ميغابايت')),
                            );
                            return;
                          }
                          setSheetState(() { selectedBytes = bytes; selectedMime = mime; selectedName = file.name; });
                        },
                        icon: const Icon(Icons.photo_library_outlined), label: const Text('المعرض'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: busy ? null : () async {
                          final file = await picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 82,
                            maxWidth: 1920,
                            maxHeight: 1920,
                          );
                          if (file == null) return;
                          final bytes = await file.readAsBytes();
                          final ext = file.name.toLowerCase().split('.').last;
                          final mime = ext == 'png' ? 'image/png' :
                            ext == 'webp' ? 'image/webp' :
                            (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : '';
                          if (mime.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('صيغة الصورة غير مدعومة؛ استخدم JPEG أو PNG أو WebP')),
                            );
                            return;
                          }
                          if (bytes.length > 4 * 1024 * 1024) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('اختر صورة لا تتجاوز 4 ميغابايت')),
                            );
                            return;
                          }
                          setSheetState(() { selectedBytes = bytes; selectedMime = mime; selectedName = file.name; });
                        },
                        icon: const Icon(Icons.camera_alt_outlined), label: const Text('الكاميرا'))),
                    ]),
                    const SizedBox(height: 12),
                    TextField(controller: promptController, maxLines: 3, maxLength: 2000,
                      decoration: const InputDecoration(labelText: 'ماذا تريد أن تعرف عن الصورة؟')),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: busy || selectedBytes == null ? null : () async {
                        setSheetState(() => busy = true);
                        try {
                          result = await _requestImageAnalysis(selectedBytes!, selectedMime, promptController.text);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (mounted && result != null) {
                            await showDialog<void>(context: this.context, builder: (dialogContext) => AlertDialog(
                              title: const Text('نتيجة تحليل الصورة'),
                              content: SingleChildScrollView(child: SelectableText(result!)),
                              actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('إغلاق'))],
                            ));
                          }
                        } catch (error) {
                          setSheetState(() => busy = false);
                          if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                          );
                        }
                      },
                      icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                      label: Text(busy ? 'جارٍ تحليل الصورة...' : 'حلّل الصورة'),
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
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(assistant ? 'مهمة جديدة إلى BARQ Brain' : 'إضافة مهمة',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(controller: titleController, autofocus: true,
              decoration: InputDecoration(labelText: assistant ? 'ما الذي تريد من المساعد إنجازه؟' : 'عنوان المهمة')),
            const SizedBox(height: 12),
            TextField(controller: descriptionController, maxLines: 4,
              decoration: const InputDecoration(labelText: 'التفاصيل والسياق')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ المهمة')),
          ],
        ),
      ),
    );
    if (result == true) {
      final title = titleController.text.trim();
      final details = descriptionController.text.trim();
      await _createTask(assistant && !title.startsWith('BARQ Brain')
        ? 'BARQ Brain: ' + title : title, details);
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BARQ Admin', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
          Text(_connectionMessage, style: TextStyle(
            fontSize: 11, color: _online ? const Color(0xFF6DD6A4) : Colors.white60,
          )),
        ]),
        actions: [
          IconButton(tooltip: 'إعدادات الاتصال', onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined)),
          IconButton(tooltip: 'إنهاء الجلسة', onPressed: _token.isEmpty ? null : _logout,
            icon: const Icon(Icons.logout)),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _tasks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _tab, children: [_dashboard(), _tasksView(), _approvalsView(), _auditView()]),
      ),
      floatingActionButton: _tab == 1
        ? FloatingActionButton.extended(onPressed: () => _showCreateTask(),
            icon: const Icon(Icons.add), label: const Text('مهمة جديدة'))
        : _tab == 0
          ? FloatingActionButton.extended(onPressed: () => _showCreateTask(assistant: true),
              icon: const Icon(Icons.bolt), label: const Text('اسأل BARQ Brain'))
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'المهام'),
          NavigationDestination(icon: Icon(Icons.verified_user_outlined), label: 'الموافقات'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'السجل'),
        ],
      ),
    );
  }

  Widget _dashboard() {
    final pending = _approvals.where((item) => item.status == 'pending').length;
    final active = _tasks.where((task) =>
      ['queued', 'running', 'paused', 'needs_approval'].contains(task.status)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _workspaceCard(),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _metricCard('المهام النشطة', active.toString(), Icons.bolt, _blue)),
          const SizedBox(width: 10),
          Expanded(child: _metricCard('بانتظار موافقتك', pending.toString(), Icons.shield_outlined, _gold)),
        ]),
        const SizedBox(height: 18),
        const Text('BARQ Brain', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              CircleAvatar(backgroundColor: Color(0x332785FF), child: Icon(Icons.auto_awesome, color: _blue)),
              SizedBox(width: 10),
              Expanded(child: Text('مساعد المشروع والإطلاق', style: TextStyle(fontWeight: FontWeight.bold))),
              Icon(Icons.cloud_done_outlined, color: _gold),
            ]),
            const SizedBox(height: 12),
            const Text('أرسل له مهمة أو اطلب تحليلًا أو خطة تسويق. عند اتصال خدمة الخادم، تُنفّذ مهام التحليل والصياغة بعيدًا عن هاتفك.'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1A2785FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _blue.withValues(alpha: .25)),
              ),
              child: const Text(
                'اتفاق المالك: المرحلة الأولى فقط حاليًا. لا يبدأ فهم أو فهرسة كود BARQ قبل إذن صريح. لا دمج أو نشر أو تغيير إنتاج دون موافقة محددة. BARQ هو المنتج، وSPARK ميزة القصص، وBARQ Admin تطبيق الإدارة المستقل. مزود تسجيل الدخول لم يُعتمد بعد؛ لا تفترض Google أو غيره.',
                style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _showCreateTask(assistant: true),
              icon: const Icon(Icons.add), label: const Text('إرسال مهمة للمساعد')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _showVisionAnalysis,
              icon: const Icon(Icons.image_search_outlined), label: const Text('أرسل صورة لتحليلها')),
          ]),
        )),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('آخر المهام', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('عرض الكل')),
        ]),
        if (_tasks.isEmpty) _emptyState('لا توجد مهام بعد', 'ابدأ بإرسال أول مهمة إلى BARQ Brain')
        else ..._tasks.take(3).map(_taskTile),
      ],
    );
  }

  Widget _workspaceCard() {
    final project = (_workspace['current_project'] ?? 'BARQ').toString();
    final phase = (_workspace['current_phase'] ?? 'لم تُحدد المرحلة').toString();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [Color(0xFF174C91), Color(0xFF15243E), Color(0xFF151E31)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt, color: _gold, size: 28),
          const SizedBox(width: 8),
          const Text('مساحة عمل المالك', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Icon(_online ? Icons.cloud_done : Icons.cloud_off,
            color: _online ? const Color(0xFF6DD6A4) : Colors.white60),
        ]),
        const SizedBox(height: 20),
        Text(project, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('آخر موضع محفوظ: ' + phase, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 14),
        const Text('حالة المزامنة', style: TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 3),
        Text(_online ? 'متصل — الخادم هو المرجع الأساسي' : 'عرض آخر نسخة محفوظة على هذا الهاتف',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ),
  );

  Widget _tasksView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
    children: [
      const Text('سجل المهام ونقاط التقدم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('المهام التي وصلت إلى الخادم يمكن استعادتها من أي جهاز بعد تسجيل الدخول.',
        style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 14),
      if (_tasks.isEmpty) _emptyState('قائمة المهام فارغة', 'أضف مهمة جديدة أو أرسل طلبًا إلى BARQ Brain')
      else ..._tasks.map(_taskTile),
    ],
  );

  Widget _taskTile(AdminTask task) {
    final local = task.status == 'draft_offline';
    final statusColor = local ? _gold : switch (task.status) {
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(20)),
              child: Text(local ? 'محلي' : task.status, style: TextStyle(color: statusColor, fontSize: 11)),
            ),
          ]),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
          if (task.nextAction.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text('التالي: ' + task.nextAction, style: const TextStyle(color: _gold, fontSize: 12)),
          ],
          if (!local && task.checkpointVersion > 0) ...[
            const SizedBox(height: 5),
            Text('نقطة التقدم ' + task.checkpointVersion.toString(),
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ]),
      ),
    );
  }

  Widget _approvalsView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
    children: [
      const Text('موافقات المالك', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('لا ينشر المساعد ولا ينفق ولا يغيّر الإنتاج دون قرار واضح منك.',
        style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 14),
      if (_approvals.isEmpty) _emptyState('لا توجد طلبات موافقة', 'ستظهر هنا الإجراءات الحساسة قبل تنفيذها')
      else ..._approvals.map((approval) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(approval.actionType, style: const TextStyle(fontWeight: FontWeight.bold))),
              Text(approval.status, style: TextStyle(color: approval.status == 'pending' ? _gold : Colors.white60)),
            ]),
            const SizedBox(height: 10),
            Text((approval.preview['summary'] ?? '').toString()),
            const SizedBox(height: 5),
            Text('الهدف: ' + (approval.preview['target'] ?? '').toString(),
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text('البيئة: ' + (approval.preview['environment'] ?? '').toString(),
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
            if (approval.status == 'pending') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => _decideApproval(approval.id, 'rejected'), child: const Text('رفض'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(
                  onPressed: () => _decideApproval(approval.id, 'approved'), child: const Text('موافقة'))),
              ]),
            ],
          ]),
        ),
      )),
    ],
  );

  Widget _auditView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
    children: [
      const Text('سجل النشاط والتدقيق', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('سجل للقراءة فقط للأحداث المسجلة على مساحة إدارة BARQ.',
        style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 14),
      if (_auditEvents.isEmpty)
        _emptyState('لا توجد أحداث مسجلة', 'ستظهر هنا تغييرات مساحة العمل والمهام والموافقات')
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((event['event_type'] ?? 'event').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _gold)),
                const SizedBox(height: 5),
                Text('الهدف: ${event['target_type'] ?? '-'} / ${event['target_id'] ?? '-'}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if (details.isNotEmpty)
                  Text(details.entries.map((entry) => '${entry.key}: ${entry.value}').join(' • '),
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
                if (created.isNotEmpty)
                  Align(alignment: AlignmentDirectional.centerStart,
                    child: Text(created, style: const TextStyle(fontSize: 10, color: Colors.white38))),
              ]),
            ),
          );
        }),
    ],
  );

  Widget _emptyState(String title, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.inbox_outlined, color: Colors.white38, size: 36),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(subtitle, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
    ),
  );
}
