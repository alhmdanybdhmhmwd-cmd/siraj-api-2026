import 'package:material_ui/material_ui.dart';
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
          glow: Color(0xFF168BFF),
          tagline: 'الهوية الرسمية',
          motif: Icons.flash_on_rounded,
        );
      // Soft, luminous butterfly direction: pearl, rose and lilac.
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
          motif: Icons.flutter_dash_rounded,
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
          glow: Color(0xFF9B35FF),
          tagline: 'قوة في التفاصيل',
          motif: Icons.diamond_outlined,
        );
      // Cool crystal identity: sky cyan, ice and deep blue.
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
