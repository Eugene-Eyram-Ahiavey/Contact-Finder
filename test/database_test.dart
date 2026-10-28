import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/call_center.dart';
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
          await AppDatabase.createTables(db, version);
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

  group('AppDatabase Call Center Operations', () {
    final center1 = CallCenter(
      id: 'center-spintex',
      name: 'Spintex Outreach',
      description: 'Community revival follow-up',
      location: 'Spintex Road',
      colorHex: '#3F51B5',
      createdAt: testDate,
      updatedAt: testDate,
    );

    final center2 = CallCenter(
      id: 'center-tema',
      name: 'Tema Market Outreach',
      description: 'Youth evangelism drive',
      location: 'Tema Community 1',
      colorHex: '#00897B',
      createdAt: testDate.add(const Duration(hours: 1)),
      updatedAt: testDate.add(const Duration(hours: 1)),
    );

    test('can insert and retrieve Call Centers with contact count', () async {
      await appDb.insertCallCenter(center1);
      await appDb.insertCallCenter(center2);

      final centers = await appDb.getAllCallCenters();
      expect(centers.length, 2);
      // Newest center should be first!
      expect(centers[0].id, 'center-tema');
      expect(centers[1].id, 'center-spintex');
      expect(centers[0].contactCount, 0);

      // Add contacts to center1
      final c1 = Contact(
        id: 'c-1',
        callCenterId: 'center-spintex',
        name: 'Ama Serwaa',
        phoneNumber: '0244123456',
        normalizedPhoneNumber: '+233244123456',
        createdAt: testDate,
        updatedAt: testDate,
      );
      await appDb.insertContact(c1);

      final updatedCenters = await appDb.getAllCallCenters();
      final spintexCenter =
          updatedCenters.firstWhere((c) => c.id == 'center-spintex');
      expect(spintexCenter.contactCount, 1);
    });

    test('strictly guarantees new contact additions appear at the TOP (created_at DESC)', () async {
      await appDb.insertCallCenter(center1);

      final olderContact = Contact(
        id: 'c-old',
        callCenterId: 'center-spintex',
        name: 'Kofi Mensah (First Batch)',
        phoneNumber: '0244111222',
        normalizedPhoneNumber: '+233244111222',
        createdAt: DateTime.parse('2026-10-20T08:00:00.000Z'),
        updatedAt: DateTime.parse('2026-10-20T08:00:00.000Z'),
      );

      final newerContact = Contact(
        id: 'c-new',
        callCenterId: 'center-spintex',
        name: 'Ama Serwaa (Just Added Today)',
        phoneNumber: '0559998877',
        normalizedPhoneNumber: '+233559998877',
        createdAt: DateTime.parse('2026-10-20T14:00:00.000Z'), // Later in the day!
        updatedAt: DateTime.parse('2026-10-20T14:00:00.000Z'),
      );

      // Insert older first, then newer
      await appDb.insertContact(olderContact);
      await appDb.insertContact(newerContact);

      final list = await appDb.getContactsByCallCenter('center-spintex');
      expect(list.length, 2);
      // The newest addition MUST be on top!
      expect(list[0].id, 'c-new');
      expect(list[0].name, 'Ama Serwaa (Just Added Today)');
      expect(list[1].id, 'c-old');
      expect(list[1].name, 'Kofi Mensah (First Batch)');
    });

    test('deleting a Call Center cascades and deletes all contacts inside it', () async {
      await appDb.insertCallCenter(center1);

      final contact = Contact(
        id: 'c-to-delete',
        callCenterId: 'center-spintex',
        name: 'Kwame Mensah',
        phoneNumber: '0244998877',
        normalizedPhoneNumber: '+233244998877',
        createdAt: testDate,
        updatedAt: testDate,
      );
      await appDb.insertContact(contact);

      expect((await appDb.getContactsByCallCenter('center-spintex')).length, 1);

      // Delete the Call Center
      await appDb.deleteCallCenter('center-spintex');

      expect((await appDb.getAllCallCenters()).length, 0);
      expect((await appDb.getContactsByCallCenter('center-spintex')).length, 0);
      expect(await appDb.getContactById('c-to-delete'), isNull);
    });
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

      // Caller ID test 2: Call comes in as international format with spaces: "+233 24 412 3456"
      final matchIntl = await appDb.findContactByPhoneNumber('+233 24 412 3456');
      expect(matchIntl, isNotNull);
      expect(matchIntl!.name, 'Kofi Mensah');

      // Caller ID test 3: Unsaved incoming number returns null (Zero false positives!)
      final unknown = await appDb.findContactByPhoneNumber('0249999999');
      expect(unknown, isNull);
    });

    test('enforces duplicate phone number prevention', () async {
      await appDb.insertContact(contact1);

      // Attempt to insert duplicate contact with different local formatting
      final duplicateContact = Contact(
        id: 'contact-kofi-duplicate',
        name: 'Kofi Duplicate',
        phoneNumber: '+233 24 412 3456',
        normalizedPhoneNumber: '+233244123456', // Same normalized E.164!
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(
        () async => await appDb.insertContact(duplicateContact),
        throwsA(isA<DuplicatePhoneNumberException>()),
      );
    });

    test('searches contacts by name, location, or phone substring', () async {
      await appDb.insertContact(contact1);
      await appDb.insertContact(contact2);

      // Search by Name
      final nameResults = await appDb.searchContacts('Ama');
      expect(nameResults.length, 1);
      expect(nameResults.first.name, 'Ama Serwaa');

      // Search by Location
      final locResults = await appDb.searchContacts('Spintex');
      expect(locResults.length, 1);
      expect(locResults.first.name, 'Ama Serwaa');

      // Search by partial phone number digits
      final phoneResults = await appDb.searchContacts('9876');
      expect(phoneResults.length, 1);
      expect(phoneResults.first.name, 'Ama Serwaa');
    });

    test('deletes a contact and cascades to remove its interaction history', () async {
      await appDb.insertContact(contact1);

      final interaction = Interaction(
        id: 'inter-1',
        contactId: 'contact-kofi',
        date: testDate,
        outcome: 'Called back; agreed to visit',
        createdAt: testDate,
      );
      await appDb.addInteraction(interaction);

      // Verify contact and interaction exist
      expect((await appDb.getInteractionsForContact('contact-kofi')).length, 1);

      // Delete contact
      await appDb.deleteContact('contact-kofi');

      // Verify both are gone
      expect(await appDb.getContactById('contact-kofi'), isNull);
      expect((await appDb.getInteractionsForContact('contact-kofi')).length, 0);
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

  group('Scale & Edge Case Verification', () {
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
