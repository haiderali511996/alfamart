// End-to-end UI smoke test: runs the real app on a desktop SQLite engine.
//
//   flutter test test/app_flow_test.dart
//   SCREENSHOTS=1 flutter test test/app_flow_test.dart   # also saves PNGs
import 'dart:io';

import 'package:alfamart_cashflow/app.dart';
import 'package:alfamart_cashflow/data/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _shots = Platform.environment['SCREENSHOTS'] != null;

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> settle(WidgetTester t, [int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  if (!_shots) return;
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump();
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('screenshots/$name.png'));
}

/// Scrolls the page's list until [f] is built and on screen.
Future<void> scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    250,
    scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first,
  );
  await t.pump();
}

Future<void> enter(WidgetTester t, String label, String text) async {
  await t.enterText(find.widgetWithText(TextFormField, label).first, text);
  await t.pump();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = await AppDatabase.defaultPath();
    if (File(path).existsSync()) File(path).deleteSync();
    if (_shots) {
      autoUpdateGoldenFiles = true;
      await _loadFonts();
    }
  });

  testWidgets('setup, add cashier, record entries, see dashboard', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);

    await t.pumpWidget(const AlfaMartApp());
    await settle(t, 4);
    await shot(t, '01_splash');
    await settle(t, 10);

    // First launch → create admin.
    expect(find.text('Welcome! Create the Admin account'), findsOneWidget);
    await enter(t, 'Full name', 'Haider Ali');
    await enter(t, 'Username', 'admin');
    await enter(t, 'Password', 'alfa123');
    await enter(t, 'Confirm password', 'alfa123');
    await shot(t, '02_setup');
    await t.tap(find.text('Create Admin & Continue'));
    await settle(t, 30);

    expect(find.text('Net Cash Flow'), findsOneWidget);

    // Add a cashier.
    await t.tap(find.text('More'));
    await settle(t, 2);
    await t.tap(find.text('Counters & Cashiers'));
    await settle(t, 4);
    await t.tap(find.text('Add Cashier'));
    await settle(t, 4);
    await t.enterText(find.widgetWithText(TextField, 'Cashier name'), 'Ali');
    await t.tap(find.text('Save'));
    await settle(t, 6);
    expect(find.text('Ali'), findsWidgets);
    await shot(t, '06_cashiers');
    await t.pageBack();
    await settle(t, 3);
    await t.tap(find.text('Dashboard'));
    await settle(t, 3);

    // Counter sale with an expense and cash to purchaser on the same screen.
    await t.tap(find.text('Add Entry'));
    await settle(t, 3);
    await t.tap(find.text('Counter Sale'));
    await settle(t, 6);
    expect(find.text('Duty time: 7:00 AM – 8:00 PM'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '19000'), findsOneWidget); // opening cash prefilled
    await t.tap(find.text('Cashier').last);
    await settle(t, 2);
    await t.tap(find.text('Ali').last);
    await settle(t, 3);
    await enter(t, 'Cash', '20000');
    await enter(t, 'POS Machine', '5000');
    await enter(t, 'Online Banking', '3000');
    await enter(t, 'JazzCash', '1000');
    expect(find.text('Rs 29,000'), findsWidgets); // live total

    await scrollTo(t, find.text('Add expense'));
    await t.tap(find.text('Add expense'));
    await settle(t, 3);
    await enter(t, 'Amount', '500');
    await enter(t, 'Details', 'Tea for staff');
    await t.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(t, 3);

    await scrollTo(t, find.widgetWithText(TextButton, 'Add'));
    await t.tap(find.widgetWithText(TextButton, 'Add').last);
    await settle(t, 3);
    await enter(t, 'Purchaser name', 'Kamran');
    await enter(t, 'Amount given', '5000');
    await t.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(t, 3);

    // Expected drawer: 19,000 + 20,000 − 500 − 5,000 = 33,500. Count 33,000 → short 500.
    await scrollTo(t, find.text('Cash counted in drawer (optional)'));
    await enter(t, 'Cash counted in drawer (optional)', '33000');
    await settle(t, 2);
    expect(find.text('Rs 33,500'), findsOneWidget);
    await shot(t, '04_shift_form');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(t, 3);
    expect(find.text('Cash is SHORT'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await settle(t, 8);

    // Advance to the purchaser.
    await t.tap(find.text('Add Entry'));
    await settle(t, 3);
    await t.tap(find.text('Advance to Purchaser'));
    await settle(t, 6);
    expect(find.widgetWithText(TextFormField, 'Kamran'), findsOneWidget); // remembered name
    await enter(t, 'Advance amount', '10000');
    await t.tap(find.text('Save'));
    await settle(t, 8);

    // Purchase.
    await t.tap(find.text('Add Entry'));
    await settle(t, 3);
    await t.tap(find.text('Purchase').last);
    await settle(t, 4);
    await enter(t, 'Supplier / Vendor', 'Nestle');
    await enter(t, 'Purchase amount', '12000');
    await t.tap(find.text('Save'));
    await settle(t, 8);

    expect(find.text('Rs 29,000'), findsWidgets); // sales tile
    expect(find.text('Rs 12,000'), findsWidgets); // purchase tile
    expect(find.text('Rs 500'), findsWidgets); // expense tile
    expect(find.text('Rs 16,500'), findsWidgets); // net
    // Purchaser: advance 10,000 + 5,000 from Counter 1 − 12,000 bought = 3,000 to return.
    await scrollTo(t, find.text('Purchaser Account'));
    await settle(t, 2);
    expect(find.text('To return Rs 3,000'), findsOneWidget);
    expect(find.text('Taken from Counter 1: Rs 5,000'), findsOneWidget);
    await shot(t, '08_purchaser');

    await shot(t, '03_dashboard');

    await t.tap(find.text('Records'));
    await settle(t, 4);
    expect(find.text('Ali · Counter 1'), findsOneWidget);
    await shot(t, '05_records');

    await t.tap(find.text('More'));
    await settle(t, 2);
    await t.tap(find.text('Export to Excel'));
    await settle(t, 6);
    await shot(t, '07_export');
    await t.pageBack();
    await settle(t, 2);

    // Logout → login screen.
    await t.ensureVisible(find.text('Logout', skipOffstage: false));
    await settle(t, 2);
    await t.tap(find.text('Logout'));
    await settle(t, 2);
    await t.tap(find.widgetWithText(FilledButton, 'Logout'));
    await settle(t, 6);
    expect(find.text('Admin / Manager Login'), findsOneWidget);
    await shot(t, '00_login');

    await enter(t, 'Username', 'admin');
    await enter(t, 'Password', 'wrong999');
    await t.tap(find.text('Login'));
    await settle(t, 20);
    expect(find.textContaining('attempts left'), findsOneWidget);
  });
}
