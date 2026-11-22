# تسليم مصدر Android — المرحلة الثانية

أُعدّ مسار GitHub Actions ليدعم طريقتين لإدخال المصدر:
1. وضع مجلد المشروع مباشرة في `android/`.
2. رفع الملف `BARQ_PHASE_2_ANDROID_GITHUB_READY.zip` إلى جذر الفرع؛ سيفكّه المسار تلقائيًا أثناء التشغيل.

## الفحوص
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- رفع APK التحقق كـ Artifact لمدة 7 أيام.

## ما لا يفعله
- لا يبني APK إصدارًا رسميًا ولا يوقعه.
- لا ينشر Worker أو يغير قاعدة الإنتاج.
- لا يحتاج أسرار Firebase Admin أو Cloudflare أو مفاتيح توقيع.
- لا يدمج طلب المراجعة تلقائيًا.

## الحالة الحالية
حزمة المصدر تم التحقق من سلامة ZIP وبنية ملفات Flutter وGradle وملفات XML وFirebase JSON محليًا. لكن فحوص Flutter نفسها لم تُنفذ بعد؛ لا بد من رفع ZIP إلى جذر هذا الفرع أو إدخال مجلد android ثم تشغيل Actions.
