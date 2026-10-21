import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:evangelism_caller_id/database/app_database.dart';
import 'package:evangelism_caller_id/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const channel = MethodChannel('com.mode.evangelism_caller_id/caller_id');
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
          await db.execute('''
            CREATE TABLE ${AppDatabase.tableContacts} (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone_number TEXT NOT NULL,
              normalized_phone_number TEXT NOT NULL UNIQUE,
              location TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE ${AppDatabase.tableInteractions} (
              id TEXT PRIMARY KEY,
              contact_id TEXT NOT NULL,
              date TEXT NOT NULL,
              outcome TEXT NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL
            )
          ''');
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

  testWidgets('App renders Evangelism Contacts home screen with empty state',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(EvangelismCallerIdApp(database: appDb));
      // Give async FFI database query time to resolve on the real event loop
      await Future.delayed(const Duration(milliseconds: 150));
    });
    // Re-render UI after state update
    await tester.pump();

    // Verify title and empty state are present
    expect(find.text('Evangelism Contacts'), findsOneWidget);
    expect(find.text('No Evangelism Contacts Yet'), findsOneWidget);
    expect(find.text('Paste Notes'), findsOneWidget);
  });
}
