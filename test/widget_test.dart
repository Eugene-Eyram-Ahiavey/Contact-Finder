import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/main.dart';
import 'package:qara/models/call_center.dart';

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

  testWidgets('App renders Call Centers hub screen with onboarding welcome state on first launch',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(EvangelismCallerIdApp(database: appDb));
      // Give async FFI database query time to resolve on the real event loop
      await Future.delayed(const Duration(milliseconds: 150));
    });
    // Re-render UI after state update
    await tester.pump();

    // Verify title and welcome onboarding elements are present
    expect(find.text('Qara Call Centers'), findsOneWidget);
    expect(find.text('Welcome to Qara'), findsOneWidget);
    expect(find.text('Create Your First Call Center'), findsOneWidget);
  });

  testWidgets('App displays created Call Center card in the hub list',
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
      await tester.pumpWidget(EvangelismCallerIdApp(database: appDb));
      await Future.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();

    // Verify Call Center card is rendered
    expect(find.text('Spintex Saturday Outreach'), findsOneWidget);
    expect(find.text('Spintex Road'), findsOneWidget);
    expect(find.text('0 contacts'), findsOneWidget);
  });
}
