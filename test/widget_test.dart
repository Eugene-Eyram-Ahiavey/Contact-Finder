import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/screens/call_centers_screen.dart';
import 'package:qara/widgets/welcome_call_center_view.dart';

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

  testWidgets('WelcomeCallCenterView renders according to Figma specifications and triggers callbacks',
      (WidgetTester tester) async {
    bool createPressed = false;
    bool syncPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeCallCenterView(
            onCreateCenterPressed: () => createPressed = true,
            onSyncPressed: () => syncPressed = true,
          ),
        ),
      ),
    );

    // Let the entrance animation settle
    await tester.pumpAndSettle();

    // Verify key UI elements
    expect(find.text('Welcome to Qara'), findsOneWidget);
    expect(find.text('Create A Call Center'), findsOneWidget);
    expect(
      find.textContaining('Start by creating your first Call Center'),
      findsOneWidget,
    );

    // Tap the Create button and verify callback
    await tester.tap(find.text('Create A Call Center'));
    expect(createPressed, isTrue);

    // Tap the Sync button and verify callback
    await tester.tap(find.byIcon(Icons.sync_rounded));
    expect(syncPressed, isTrue);
  });

  testWidgets('CallCentersScreen displays Welcome screen when no centers exist',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CallCentersScreen(database: appDb),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Welcome view is displayed
    expect(find.byType(WelcomeCallCenterView), findsOneWidget);
    expect(find.text('Welcome to Qara'), findsOneWidget);
  });

  testWidgets('CallCentersScreen displays created Call Center card in the hub list',
      (WidgetTester tester) async {
    final now = DateTime.now();
    await appDb.insertCallCenter(CallCenter(
      id: 'center-spintex',
      name: 'Spintex Saturday Outreach',
      location: 'Spintex Road',
      description: 'Youth evangelism drive',
      colorHex: '#3F51B5',
      createdAt: now,
      updatedAt: now,
    ));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CallCentersScreen(database: appDb),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Call Center card is rendered
    expect(find.text('Spintex Saturday Outreach'), findsOneWidget);
    expect(find.text('Spintex Road'), findsOneWidget);
    expect(find.text('0 contacts'), findsOneWidget);
  });
}
