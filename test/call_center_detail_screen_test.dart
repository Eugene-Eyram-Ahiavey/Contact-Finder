import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/screens/call_center_detail_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const channel = MethodChannel('com.mode.qara/caller_id');
  late Database rawDb;
  late AppDatabase appDb;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return true;
    });

    rawDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.databaseVersion,
        onCreate: (db, version) async {
          await AppDatabase.createTables(db, version);
        },
      ),
    );
    appDb = AppDatabase.withDatabase(rawDb);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await rawDb.close();
  });

  testWidgets(
      'Screen 1: CallCenterDetailScreen renders empty workspace according to Figma specifications',
      (WidgetTester tester) async {
    final testCenter = CallCenter(
      id: 'test-center-1',
      name: 'GCTU',
      location: 'Tesano',
      description: 'Campus Outreach',
      colorHex: '#00897B',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CallCenterDetailScreen(
            callCenter: testCenter,
            database: appDb,
            onCenterUpdated: () {},
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify Top Header
    expect(find.text('GCTU'), findsOneWidget);
    expect(find.text('0 Contacts'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    // 2. Verify Pill Search Bar
    expect(find.text('Search in GCTU...'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);

    // 3. Verify Empty State Graphic & Group Icon
    expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);

    // 4. Verify Empty State Typography
    expect(find.text('No Contacts here yet'), findsOneWidget);
    expect(
      find.textContaining('Add a Contact or Paste your outreach contacts'),
      findsOneWidget,
    );

    // 5. Verify Stacked Pill Action Buttons
    expect(find.text('Add Contact'), findsOneWidget);
    expect(find.text('Upload/Paste Contacts'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1_outlined), findsOneWidget);
    expect(find.byIcon(Icons.content_paste_outlined), findsOneWidget);

    // 6. Verify No Floating Action Button in empty state
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}

