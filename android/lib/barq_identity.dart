import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// الهويات الأربع المعتمدة لتطبيق برق. لا تتغير أسماء SPARK أو التطبيق هنا.
enum BarqIdentity {
  blueLightning,
  butterfly,
  purpleShadow,
  skyJewel;

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'barq_visual_identity';
  static final ValueNotifier<BarqIdentity> selected =
      ValueNotifier<BarqIdentity>(BarqIdentity.blueLightning);

  static String label(BarqIdentity value) {
    switch (value) {
      case BarqIdentity.blueLightning: return 'البرق الأزرق';
      case BarqIdentity.butterfly: return 'الفراشة';
      case BarqIdentity.purpleShadow: return 'الظل البنفسجي';
      case BarqIdentity.skyJewel: return 'الجوهرة السماوية';
    }
  }

  static Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      selected.value = BarqIdentity.values.firstWhere(
        (identity) => identity.name == saved,
        orElse: () => BarqIdentity.blueLightning,
      );
    } catch (_) {
      selected.value = BarqIdentity.blueLightning;
    }
  }

  static Future<void> set(BarqIdentity identity) async {
    await _storage.write(key: _storageKey, value: identity.name);
    selected.value = identity;
  }
}

/// Semantic palette tokens. Existing legacy hard-coded screen colors are
/// migrated in subsequent audited batches; this palette drives the app theme.
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
  });

  static BarqIdentityPalette forIdentity(BarqIdentity identity) {
    switch (identity) {
      // Preserves the currently deployed BARQ blue / gold / black / white look.
      case BarqIdentity.blueLightning:
        return const BarqIdentityPalette(
          primary: Color(0xFFD6AD55),
          secondary: Color(0xFF168BFF),
          background: Color(0xFF090909),
          surface: Color(0xFF171717),
          text: Color(0xFFFFFFFF),
          mutedText: Color(0xFFB8BEC8),
          onPrimary: Color(0xFF090909),
          onSecondary: Color(0xFFFFFFFF),
          border: Color(0x553F91E8),
        );
      // Soft, luminous butterfly direction: pearl, rose and lilac.
      case BarqIdentity.butterfly:
        return const BarqIdentityPalette(
          primary: Color(0xFFF0A8C8),
          secondary: Color(0xFFB9A0F5),
          background: Color(0xFF100D18),
          surface: Color(0xFF211A2B),
          text: Color(0xFFFFF7FC),
          mutedText: Color(0xFFC9BFD0),
          onPrimary: Color(0xFF241322),
          onSecondary: Color(0xFF21152C),
          border: Color(0x668F70C8),
        );
      // Deep, bold violet with restrained silver highlights.
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
        );
      // Cool crystal identity: sky cyan, ice and deep blue.
      case BarqIdentity.skyJewel:
        return const BarqIdentityPalette(
          primary: Color(0xFF75DFFF),
          secondary: Color(0xFF55AFFF),
          background: Color(0xFF07121B),
          surface: Color(0xFF102332),
          text: Color(0xFFF2FBFF),
          mutedText: Color(0xFFB7D0DD),
          onPrimary: Color(0xFF06202B),
          onSecondary: Color(0xFF061A2B),
          border: Color(0x6658C8E8),
        );
    }
  }
}
