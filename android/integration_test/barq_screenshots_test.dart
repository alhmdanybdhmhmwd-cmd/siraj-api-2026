import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:barq/main.dart' as barq;

const demoUser = <String, dynamic>{
  'id': 'demo-owner',
  'displayName': 'مستخدم برق',
  'username': 'barq_demo',
  'phone': '+967770000000',
};

const demoFriend = <String, dynamic>{
  'id': 'demo-friend-1',
  'displayName': 'سارة أحمد',
  'username': 'sara',
  'phone': '+967770000001',
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture BARQ actual UI screens using isolated demo fixtures', (tester) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> capture(String name, Widget screen) async {
      await tester.pumpWidget(barq.SirajApp(homeOverride: screen));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      await binding.takeScreenshot(name);
    }

    await capture('01-login', const barq.LoginPage());
    await capture('02-password-recovery', const barq.PasswordRecoveryPage());

    await capture(
      '03-home-chats',
      const barq.HomePage(user: demoUser, screenshotMode: true),
    );
    await tester.tap(find.text('SPARK').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04-home-spark');

    await tester.tap(find.text('جهات الاتصال').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05-home-contacts');

    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('06-home-account');

    await capture(
      '07-private-chat',
      const barq.ChatPage(
        friend: demoFriend,
        currentUserId: 'demo-owner',
        screenshotMode: true,
      ),
    );

    await capture(
      '08-group-chat',
      barq.GroupChatPage(
        group: const {
          'id': 'demo-group-1',
          'name': 'فريق برق',
          'description': 'مساحة الفريق ومناقشاته',
        },
        currentUserId: 'demo-owner',
        screenshotMode: true,
        onAddMember: () {},
        onShareInvite: () {},
        onGroupChanged: () async {},
      ),
    );

    await capture(
      '09-public-profile',
      barq.PublicProfilePage(
        person: demoFriend,
        currentUserId: 'demo-owner',
        canMessage: true,
      ),
    );

    await capture(
      '10-nearby-devices',
      const barq.NearbyDevicesPage(
        user: demoUser,
        friends: [demoFriend],
        screenshotMode: true,
      ),
    );

    await capture(
      '11-spark-viewer',
      const barq.SparkMediaViewer(
        statusId: 'demo-spark-1',
        authorId: 'demo-friend-1',
        currentUserId: 'demo-owner',
        media: [],
        author: 'سارة أحمد',
        caption: 'لحظات جميلة تستحق المشاركة ✨',
      ),
    );
  });
}
