import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// الهويات الأربع المعتمدة لتطبيق برق. SPARK اسم ميزة الحالات فقط.
enum BarqIdentity {
  blueLightning,
  butterfly,
  purpleShadow,
  skyJewel;

  bool get isBundled =>
      this == BarqIdentity.blueLightning || this == BarqIdentity.butterfly;

  bool get isAvailable =>
      isBundled || BarqIdentity.downloadedPackages.containsKey(name);

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'barq_visual_identity';
  static const _packagesStorageKey = 'barq_identity_packages_v1';
  static final Map<String, Map<String, dynamic>> downloadedPackages = {};
  static final ValueNotifier<BarqIdentity> selected =
      ValueNotifier<BarqIdentity>(BarqIdentity.blueLightning);

  static String label(BarqIdentity value) {
    switch (value) {
      case BarqIdentity.blueLightning:
        return 'البرق الأزرق';
      case BarqIdentity.butterfly:
        return 'الفراشة';
      case BarqIdentity.purpleShadow:
        return 'الظل البنفسجي';
      case BarqIdentity.skyJewel:
        return 'الجوهرة السماوية';
    }
  }

  static bool _isValidPackage(String identity, Map<String, dynamic> package) {
    if (package['identity'] != identity ||
        package['version'] is! String ||
        package['palette'] is! Map) {
      return false;
    }
    final palette = Map<String, dynamic>.from(package['palette'] as Map);
    const keys = [
      'primary', 'secondary', 'background', 'surface', 'text', 'mutedText',
      'onPrimary', 'onSecondary', 'border', 'glow', 'tagline', 'motif'
    ];
    for (final key in keys) {
      if (palette[key] is! String || (palette[key] as String).isEmpty) {
        return false;
      }
    }
    for (final key in keys.take(10)) {
      if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(palette[key] as String)) {
        return false;
      }
    }
    return true;
  }

  static Future<void> load() async {
    downloadedPackages.clear();
    try {
      final rawPackages = await _storage.read(key: _packagesStorageKey);
      if (rawPackages != null) {
        final decoded = jsonDecode(rawPackages);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key.toString();
            if ((key == BarqIdentity.purpleShadow.name ||
                    key == BarqIdentity.skyJewel.name) &&
                entry.value is Map) {
              final package = Map<String, dynamic>.from(entry.value as Map);
              if (_isValidPackage(key, package)) {
                downloadedPackages[key] = package;
              }
            }
          }
        }
      }
      final saved = await _storage.read(key: _storageKey);
      final restored = BarqIdentity.values
          .where((identity) => identity.name == saved)
          .firstOrNull;
      selected.value = restored != null && restored.isAvailable
          ? restored
          : BarqIdentity.blueLightning;
    } catch (_) {
      downloadedPackages.clear();
      selected.value = BarqIdentity.blueLightning;
    }
  }

  static Future<void> download(
    BarqIdentity identity, {
    required String apiBase,
    required String token,
  }) async {
    if (identity.isBundled) return;
    final response = await http.get(
      Uri.parse(apiBase + '/api/identity-packages/' + identity.name),
      headers: {
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('تعذر تنزيل حزمة الهوية (' +
          response.statusCode.toString() + ').');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['palette'] is! Map) {
      throw const FormatException('حزمة الهوية غير صالحة.');
    }
    final package = <String, dynamic>{
      'identity': decoded['identity'],
      'version': decoded['version'],
      'palette': Map<String, dynamic>.from(decoded['palette'] as Map),
    };
    if (!_isValidPackage(identity.name, package)) {
      throw const FormatException('حزمة الهوية لا تحتوي بيانات ألوان صالحة.');
    }
    downloadedPackages[identity.name] = package;
    try {
      await _storage.write(
        key: _packagesStorageKey,
        value: jsonEncode(downloadedPackages),
      );
    } catch (_) {
      downloadedPackages.remove(identity.name);
      rethrow;
    }
  }

  static Future<void> set(BarqIdentity identity) async {
    if (!identity.isAvailable) {
      throw StateError('نزّل حزمة الهوية أولاً قبل تفعيلها.');
    }
    await _storage.write(key: _storageKey, value: identity.name);
    selected.value = identity;
  }
}

/// ألوان الهوية ومعانيها البصرية.
@immutable
class BarqIdentityPalette {
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color onPrimary;
  final Color onSecondary;
  final Color border;
  final Color glow;
  final String tagline;
  final IconData motif;

  const BarqIdentityPalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.onPrimary,
    required this.onSecondary,
    required this.border,
    required this.glow,
    required this.tagline,
    required this.motif,
  });

  static BarqIdentityPalette forIdentity(BarqIdentity identity) {
    final package = BarqIdentity.downloadedPackages[identity.name];
    if (package != null && package['palette'] is Map) {
      final values = Map<String, dynamic>.from(package['palette'] as Map);
      Color color(String key) => Color(
          int.parse('FF' + (values[key] as String).substring(1), radix: 16));
      final motif = switch (values['motif']) {
        'diamond_outlined' => Icons.diamond_outlined,
        'diamond' => Icons.diamond_rounded,
        _ => Icons.auto_awesome_rounded,
      };
      return BarqIdentityPalette(
        primary: color('primary'),
        secondary: color('secondary'),
        background: color('background'),
        surface: color('surface'),
        text: color('text'),
        mutedText: color('mutedText'),
        onPrimary: color('onPrimary'),
        onSecondary: color('onSecondary'),
        border: color('border'),
        glow: color('glow'),
        tagline: values['tagline'] as String,
        motif: motif,
      );
    }
    switch (identity) {
      case BarqIdentity.blueLightning:
        return const BarqIdentityPalette(
          primary: Color(0xFF168BFF),
          secondary: Color(0xFFD6AD55),
          background: Color(0xFF090909),
          surface: Color(0xFF171717),
          text: Color(0xFFFFFFFF),
          mutedText: Color(0xFFB8BEC8),
          onPrimary: Color(0xFFFFFFFF),
          onSecondary: Color(0xFF090909),
          border: Color(0x553F91E8),
          glow: Color(0xFF168BFF),
          tagline: 'الهوية الرسمية',
          motif: Icons.flash_on_rounded,
        );
      case BarqIdentity.butterfly:
        return const BarqIdentityPalette(
          primary: Color(0xFFE15BFF),
          secondary: Color(0xFF8E24FF),
          background: Color(0xFF100719),
          surface: Color(0xFF21102B),
          text: Color(0xFFFFF5FF),
          mutedText: Color(0xFFD1B6DE),
          onPrimary: Color(0xFF250D30),
          onSecondary: Color(0xFFFFFFFF),
          border: Color(0x66D34BFF),
          glow: Color(0xFFD83DFF),
          tagline: 'أناقة بلا حدود',
          motif: Icons.auto_awesome_rounded,
        );
      case BarqIdentity.purpleShadow:
        return const BarqIdentityPalette(
          primary: Color(0xFF9B75F5),
          secondary: Color(0xFFD0B7FF),
          background: Color(0xFF0B0812),
          surface: Color(0xFF191326),
          text: Color(0xFFF8F4FF),
          mutedText: Color(0xFFBDB3CC),
          onPrimary: Color(0xFF160D25),
          onSecondary: Color(0xFF21152C),
          border: Color(0x667A55C7),
          glow: Color(0xFF9B35FF),
          tagline: 'قوة في التفاصيل',
          motif: Icons.diamond_outlined,
        );
      case BarqIdentity.skyJewel:
        return const BarqIdentityPalette(
          primary: Color(0xFFA9E8FF),
          secondary: Color(0xFF398DFF),
          background: Color(0xFF06111D),
          surface: Color(0xFF10243B),
          text: Color(0xFFF2FBFF),
          mutedText: Color(0xFFB7D0DD),
          onPrimary: Color(0xFF06202B),
          onSecondary: Color(0xFFFFFFFF),
          border: Color(0x6658C8E8),
          glow: Color(0xFF6ECFFF),
          tagline: 'صفاء يلامس النجوم',
          motif: Icons.diamond_rounded,
        );
    }
  }
}
