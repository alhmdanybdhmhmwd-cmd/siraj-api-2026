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

void main() {
  testWidgets(
    'capture BARQ actual UI screens without Android emulator',
    (tester) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final output = Directory('../artifacts/barq-ui-screenshots');
    print('BARQ_SCREENSHOT_TEST_STARTED');
    await output.create(recursive: true);
    final boundaryKey = GlobalKey();

    Future<void> saveCurrent(String name) async {
      print('BARQ_SCREENSHOT_BEGIN: $name');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('PNG encoding failed for $name');
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        print('BARQ_SCREENSHOT_SAVED: $name');
      } finally {
        image.dispose();
      }
    }

    Future<void> capture(String name, Widget screen) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: barq.SirajApp(homeOverride: screen),
        ),
      );
      await saveCurrent(name);
    }

    print('BARQ_SCREEN_STEP: login');
    await capture('01-login', const barq.LoginPage());
    print('BARQ_SCREEN_STEP: recovery');
    await capture('02-password-recovery', const barq.PasswordRecoveryPage());

    print('BARQ_SCREEN_STEP: home');
    await capture(
      '03-home-chats',
      const barq.HomePage(user: demoUser, screenshotMode: true),
    );
    print('BARQ_SCREEN_STEP: spark-tab');
    await tester.tap(find.text('SPARK').last);
    await saveCurrent('04-home-spark');

    print('BARQ_SCREEN_STEP: contacts-tab');
    await tester.tap(find.text('جهات الاتصال').last);
    await saveCurrent('05-home-contacts');

    print('BARQ_SCREEN_STEP: account-tab');
    await tester.tap(find.text('حسابي').last);
    await saveCurrent('06-home-account');

    print('BARQ_SCREEN_STEP: private-chat');
    await capture(
      '07-private-chat',
      const barq.ChatPage(
        friend: demoFriend,
        currentUserId: 'demo-owner',
        screenshotMode: true,
      ),
    );

    print('BARQ_SCREEN_STEP: group-chat');
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

    print('BARQ_SCREEN_STEP: public-profile');
    await capture(
      '09-public-profile',
      const barq.PublicProfilePage(
        person: demoFriend,
        currentUserId: 'demo-owner',
        canMessage: true,
      ),
    );

    print('BARQ_SCREEN_STEP: nearby-devices');
    await capture(
      '10-nearby-devices',
      const barq.NearbyDevicesPage(
        user: demoUser,
        friends: [demoFriend],
        screenshotMode: true,
      ),
    );

    print('BARQ_SCREEN_STEP: spark-viewer');
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

    final pngs = output
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.png'))
        .length;
    print('BARQ_SCREENSHOT_TOTAL: $pngs');
    expect(pngs, greaterThanOrEqualTo(8));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
