import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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

final Directory screenshotOutput =
    Directory('../artifacts/barq-ui-screenshots');

Future<void> captureScreen(
  WidgetTester tester,
  String name,
  Widget screen, {
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  tester.view.physicalSize = const Size(432, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await screenshotOutput.create(recursive: true);
  final boundaryKey = GlobalKey();
  print('BARQ_SCREENSHOT_BEGIN: $name');
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: barq.SirajApp(homeOverride: screen),
    ),
  );
  await tester.pump(const Duration(milliseconds: 900));
  if (afterPump != null) await afterPump(tester);
  await tester.pump(const Duration(milliseconds: 300));

  final boundary = boundaryKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  if (boundary.debugNeedsPaint) {
    await tester.pump();
  }
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG encoding failed for $name');
    await File('${screenshotOutput.path}/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    print('BARQ_SCREENSHOT_SAVED: $name');
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('01 capture login', (tester) async {
    await captureScreen(tester, '01-login', const barq.LoginPage());
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('02 capture password recovery', (tester) async {
    await captureScreen(
      tester, '02-password-recovery', const barq.PasswordRecoveryPage());
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('03 capture home chats', (tester) async {
    await captureScreen(
      tester, '03-home-chats',
      const barq.HomePage(user: demoUser, screenshotMode: true));
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('04 capture home SPARK', (tester) async {
    await captureScreen(
      tester, '04-home-spark',
      const barq.HomePage(user: demoUser, screenshotMode: true),
      afterPump: (tester) async {
        await tester.tap(find.text('SPARK').last);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('05 capture contacts', (tester) async {
    await captureScreen(
      tester, '05-home-contacts',
      const barq.HomePage(user: demoUser, screenshotMode: true),
      afterPump: (tester) async {
        await tester.tap(find.text('جهات الاتصال').last);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('06 capture account', (tester) async {
    await captureScreen(
      tester, '06-home-account',
      const barq.HomePage(user: demoUser, screenshotMode: true),
      afterPump: (tester) async {
        await tester.tap(find.text('حسابي').last);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('07 capture private chat', (tester) async {
    await captureScreen(
      tester, '07-private-chat',
      const barq.ChatPage(
        friend: demoFriend,
        currentUserId: 'demo-owner',
        screenshotMode: true,
      ));
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('08 capture group chat', (tester) async {
    await captureScreen(
      tester, '08-group-chat',
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
      ));
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('09 capture public profile', (tester) async {
    await captureScreen(
      tester, '09-public-profile',
      const barq.PublicProfilePage(
        person: demoFriend,
        currentUserId: 'demo-owner',
        canMessage: true,
      ));
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('10 capture nearby devices', (tester) async {
    await captureScreen(
      tester, '10-nearby-devices',
      const barq.NearbyDevicesPage(
        user: demoUser,
        friends: [demoFriend],
        screenshotMode: true,
      ));
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('11 capture SPARK viewer', (tester) async {
    await captureScreen(
      tester, '11-spark-viewer',
      const barq.SparkMediaViewer(
        statusId: 'demo-spark-1',
        authorId: 'demo-friend-1',
        currentUserId: 'demo-owner',
        media: [],
        author: 'سارة أحمد',
        caption: 'لحظات جميلة تستحق المشاركة ✨',
      ));
  }, timeout: const Timeout(Duration(seconds: 45)));
}
