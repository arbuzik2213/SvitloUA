// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svitlo_ua/address.dart';
import 'package:svitlo_ua/regions.dart';
import 'package:svitlo_ua/screens/address_screen.dart';
import 'package:svitlo_ua/screens/home_screen.dart';
import 'package:svitlo_ua/theme.dart';

Future<void> loadFont(String family, ByteData data) async {
  await (FontLoader(family)..addFont(Future.value(data))).load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    HttpOverrides.global = null;
    await loadFont('Unbounded', await rootBundle.load('assets/fonts/Unbounded.ttf'));
    await loadFont('Golos', await rootBundle.load('assets/fonts/GolosText.ttf'));
    final icons = File('${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf');
    await loadFont('packages/cupertino_icons/CupertinoIcons', ByteData.sublistView(icons.readAsBytesSync()));
  });

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  }

  Future<void> pumpReal(WidgetTester t, Widget w, {int ticks = 40}) async {
    await t.runAsync(() async {
      await t.pumpWidget(w);
      for (var i = 0; i < ticks; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await t.pump();
      }
    });
    await t.pump(const Duration(milliseconds: 400));
  }

  Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: home);

  testWidgets('oblasts', (t) async {
    phone(t);
    await pumpReal(t, app(const OblastScreen()), ticks: 2);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/oblasts.png'));
  });

  testWidgets('queue pick kharkiv', (t) async {
    phone(t);
    await pumpReal(t, app(QueuePickScreen(oblast: oblastById('kharkiv')!)), ticks: 2);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/queue_kharkiv.png'));
  });

  testWidgets('home zhytomyr', (t) async {
    phone(t);
    final a = SavedAddress(oblastId: 'zhytomyr', path: const [
      AddressOption('7', 'Житомирський'),
      AddressOption('16657', 'місто Житомир'),
      AddressOption('173934', 'вул. Київська'),
      AddressOption('59', '59', {'queue': 'GPV1.2'}),
    ], queue: 'GPV1.2');
    SharedPreferences.setMockInitialValues({'address_v3': jsonEncode(a.toJson()), 'oblast_v2': 'zhytomyr'});
    await pumpReal(t, app(const HomeScreen()));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/home_zhytomyr.png'));
  });
}
