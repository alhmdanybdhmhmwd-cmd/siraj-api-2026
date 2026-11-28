import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barq_admin/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  Future<void> openAdminTab(WidgetTester tester, String label) async {
    await tester.pumpWidget(const BarqAdminApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Platform overview is reachable and owner-gated', (
    tester,
  ) async {
    await openAdminTab(tester, 'إدارة المنصة');

    expect(find.text('إدارة المنصة'), findsWidgets);
    expect(
      find.textContaining('ملخص تشغيلي للقراءة فقط'),
      findsOneWidget,
    );
    expect(
      find.text('سجّل الدخول بحساب المالك لعرض ملخص المنصة'),
      findsOneWidget,
    );
    expect(find.text('إجمالي المستخدمين'), findsNothing);
    expect(find.text('إجمالي المجموعات'), findsNothing);
    expect(find.text('سلامة الخدمات'), findsNothing);
    expect(find.text('قاعدة بيانات BARQ Admin'), findsNothing);
    expect(
      find.textContaining('لا يعرض محتوى الرسائل أو بيانات الحسابات الخاصة'),
      findsOneWidget,
    );
  });

  testWidgets('Users page is reachable and protects account data', (
    tester,
  ) async {
    await openAdminTab(tester, 'المستخدمون');

    expect(find.text('المستخدمون'), findsWidgets);
    expect(
      find.textContaining('أرقام الهاتف مخفية في القائمة'),
      findsOneWidget,
    );
    expect(find.text('ابحث بالاسم أو اسم برق أو رقم الهاتف'), findsOneWidget);
    expect(
      find.text('سجّل الدخول بحساب المالك لعرض المستخدمين'),
      findsOneWidget,
    );
    expect(find.textContaining('كلمة المرور'), findsNothing);
    expect(find.textContaining('الرسائل الخاصة'), findsNothing);
  });

  testWidgets('Groups page is reachable and does not expose private content', (
    tester,
  ) async {
    await openAdminTab(tester, 'المجموعات');

    expect(find.text('المجموعات'), findsWidgets);
    expect(
      find.textContaining('لا يتم فتح الرسائل أو الوسائط الخاصة'),
      findsOneWidget,
    );
    expect(find.text('ابحث باسم المجموعة أو وصفها'), findsOneWidget);
    expect(
      find.text('سجّل الدخول بحساب المالك لعرض المجموعات'),
      findsOneWidget,
    );
    expect(find.text('لا توجد مجموعات'), findsNothing);
    expect(find.text('مجموعة برق'), findsNothing);
    expect(find.textContaining('محتوى الرسائل'), findsNothing);
  });
}
