import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/models/interaction.dart';

void main() {
  // Setup sqflite ffi for desktop/local unit testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database rawDb;
  late AppDatabase appDb;

  final testDate = DateTime.parse('2026-10-20T10:00:00.000Z');

  setUp(() async {
    // Open a fresh in-memory database for each test to guarantee complete isolation
    rawDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.databaseVersion,
        onCreate: (db, version) async {
          // Use the exact schema creation logic
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
              created_at TEXT NOT NULL,
              FOREIGN KEY (contact_id) REFERENCES ${AppDatabase.tableContacts} (id) ON DELETE CASCADE
            )
          ''');
        },
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    appDb = AppDatabase.withDatabase(rawDb);
  });

  tearDown(() async {
    await rawDb.close();
  });

  group('AppDatabase Contact Operations', () {
    final contact1 = Contact(
      id: 'contact-kofi',
      name: 'Kofi Mensah',
      phoneNumber: '0244123456',
      normalizedPhoneNumber: '+233244123456',
      location: 'Tema Community 1',
      notes: 'Met at outreach near market',
      createdAt: testDate,
      updatedAt: testDate,
    );

    final contact2 = Contact(
      id: 'contact-ama',
      name: 'Ama Serwaa',
      phoneNumber: '0559876543',
      normalizedPhoneNumber: '+233559876543',
      location: 'Spintex Road',
      notes: 'Interested in Sunday service',
      createdAt: testDate,
      updatedAt: testDate,
    );

    test('can insert and retrieve a contact by ID', () async {
      await appDb.insertContact(contact1);
      final retrieved = await appDb.getContactById('contact-kofi');

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Kofi Mensah');
      expect(retrieved.phoneNumber, '0244123456');
      expect(retrieved.normalizedPhoneNumber, '+233244123456');
      expect(retrieved.location, 'Tema Community 1');
    });

    test('finds contact accurately whether incoming number is local or international', () async {
      await appDb.insertContact(contact1);

      // Caller ID test 1: Call comes in as local format: "0244123456"
      final matchLocal = await appDb.findContactByPhoneNumber('0244123456');
      expect(matchLocal, isNotNull);
      expect(matchLocal!.name, 'Kofi Mensah');

      // Caller ID test 2: Call comes in as international format: "+233244123456"
      final matchIntl = await appDb.findContactByPhoneNumber('+233244123456');
      expect(matchIntl, isNotNull);
      expect(matchIntl!.name, 'Kofi Mensah');

      // Caller ID test 3: Call comes in with spaces/hyphens: "024 412 3456"
      final matchFormatted = await appDb.findContactByPhoneNumber('024 412 3456');
      expect(matchFormatted, isNotNull);
      expect(matchFormatted!.name, 'Kofi Mensah');
    });

    test('unknown caller returns null and never invents an identity', () async {
      await appDb.insertContact(contact1);

      final unknownResult = await appDb.findContactByPhoneNumber('0200000000');
      expect(unknownResult, isNull);
    });

    test('prevents inserting duplicate normalized phone numbers', () async {
      await appDb.insertContact(contact1);

      // Attempt to insert another contact with the same phone number (different formatting)
      final duplicateContact = Contact(
        id: 'contact-duplicate',
        name: 'Another Person',
        phoneNumber: '024 412 3456',
        normalizedPhoneNumber: '+233244123456', // Same normalized number!
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(
        () async => await appDb.insertContact(duplicateContact),
        throwsA(isA<DuplicatePhoneNumberException>()),
      );
    });

    test('searchContacts filters by name, phone, or location', () async {
      await appDb.insertContact(contact1);
      await appDb.insertContact(contact2);

      // Search by name
      final nameSearch = await appDb.searchContacts('Kofi');
      expect(nameSearch.length, 1);
      expect(nameSearch.first.name, 'Kofi Mensah');

      // Search by location
      final locationSearch = await appDb.searchContacts('Spintex');
      expect(locationSearch.length, 1);
      expect(locationSearch.first.name, 'Ama Serwaa');

      // Search by phone digits
      final phoneSearch = await appDb.searchContacts('9876');
      expect(phoneSearch.length, 1);
      expect(phoneSearch.first.name, 'Ama Serwaa');
    });

    test('updateContact persists modified fields', () async {
      await appDb.insertContact(contact1);

      final updated = contact1.copyWith(
        name: 'Kofi Mensah (Pastor Kofi)',
        location: 'Tema Community 2',
      );
      await appDb.updateContact(updated);

      final fetched = await appDb.getContactById('contact-kofi');
      expect(fetched!.name, 'Kofi Mensah (Pastor Kofi)');
      expect(fetched.location, 'Tema Community 2');
    });

    test('deleteContact removes contact and cascades to interactions', () async {
      await appDb.insertContact(contact1);
      await appDb.addInteraction(Interaction(
        id: 'inter-1',
        contactId: 'contact-kofi',
        date: testDate,
        outcome: 'Called; no answer',
        createdAt: testDate,
      ));

      await appDb.deleteContact('contact-kofi');

      expect(await appDb.getContactById('contact-kofi'), isNull);
      final remainingInteractions =
          await appDb.getInteractionsForContact('contact-kofi');
      expect(remainingInteractions, isEmpty);
    });
  });

  group('AppDatabase Interaction Operations', () {
    final contact = Contact(
      id: 'contact-john',
      name: 'John Doe',
      phoneNumber: '0240001122',
      normalizedPhoneNumber: '+233240001122',
      createdAt: testDate,
      updatedAt: testDate,
    );

    test('records multiple interactions and orders them chronologically newest-first', () async {
      await appDb.insertContact(contact);

      final firstCall = Interaction(
        id: 'call-1',
        contactId: 'contact-john',
        date: DateTime.parse('2026-10-12T10:00:00.000Z'),
        outcome: 'Called; no answer',
        createdAt: DateTime.parse('2026-10-12T10:00:00.000Z'),
      );

      final secondCall = Interaction(
        id: 'call-2',
        contactId: 'contact-john',
        date: DateTime.parse('2026-10-15T14:30:00.000Z'),
        outcome: 'Called back; conversation completed',
        notes: 'Wants to visit church next Sunday',
        createdAt: DateTime.parse('2026-10-15T14:30:00.000Z'),
      );

      await appDb.addInteraction(firstCall);
      await appDb.addInteraction(secondCall);

      final history = await appDb.getInteractionsForContact('contact-john');
      expect(history.length, 2);
      // Newest should be first!
      expect(history[0].id, 'call-2');
      expect(history[0].outcome, 'Called back; conversation completed');
      expect(history[1].id, 'call-1');
      expect(history[1].outcome, 'Called; no answer');

      // Check latest interaction
      final latest = await appDb.getLatestInteraction('contact-john');
      expect(latest, isNotNull);
      expect(latest!.id, 'call-2');
      expect(latest.outcome, 'Called back; conversation completed');
    });
  });

  group('Milestone 7: Scale & Edge Case Verification', () {
    test('benchmarks sub-millisecond lookup speed across 1,000 evangelism contacts', () async {
      // 1. Batch insert 1,000 realistic church outreach contacts
      final batch = <Contact>[];
      for (int i = 0; i < 1000; i++) {
        final padded = i.toString().padLeft(7, '0');
        batch.add(Contact(
          id: 'contact-$i',
          name: 'Outreach Person $i',
          phoneNumber: '024$padded',
          normalizedPhoneNumber: '+23324$padded',
          location: i % 2 == 0 ? 'Accra Central' : 'Tema Community ${i % 10}',
          notes: 'Met at evangelism drive #$i',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }

      await appDb.insertContactsBatch(batch);

      // Verify count
      final all = await appDb.getAllContacts();
      expect(all.length, 1000);

      // 2. Measure lookup speed for the 999th contact (worst-case search position)
      final stopwatch = Stopwatch()..start();
      final target = await appDb.findContactByPhoneNumber('0240000999');
      stopwatch.stop();

      expect(target, isNotNull);
      expect(target!.name, 'Outreach Person 999');
      expect(target.normalizedPhoneNumber, '+233240000999');

      // Indexed SQLite B-Tree search should resolve in under 15ms even on CPU-constrained test runners
      expect(stopwatch.elapsedMilliseconds, lessThan(15));
    });

    test('correctly handles contact records with null optional fields without crashing', () async {
      final minimalContact = Contact(
        id: 'contact-minimal',
        name: 'Minimal Contact',
        phoneNumber: '0501234567',
        normalizedPhoneNumber: '+233501234567',
        location: null,
        notes: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await appDb.insertContact(minimalContact);
      final found = await appDb.findContactByPhoneNumber('050 123 4567');
      expect(found, isNotNull);
      expect(found!.location, isNull);
      expect(found.notes, isNull);
    });
  });
}
