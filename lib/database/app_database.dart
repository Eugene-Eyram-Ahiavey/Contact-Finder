import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:qara/models/call_center.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/models/interaction.dart';
import 'package:qara/utils/phone_number_normalizer.dart';

/// AppDatabase
///
/// Manages local SQLite storage for Call Centers (outreach projects/gems),
/// evangelism contacts, and follow-up interaction history.
///
/// Architectural Guarantees:
/// 1. Offline-first: Data is stored securely and directly on device flash memory.
/// 2. Campaign Isolation: Contacts are organized into Call Centers.
/// 3. Ordering: New contacts within a Call Center are strictly returned newest-first (`created_at DESC`).
/// 4. Fast O(1) Caller ID Lookup: Normalized phone numbers are strictly indexed.
/// 5. Interaction History: Follow-ups are stored in a relational `interactions` table
///    linked to contacts by `contact_id`.
class AppDatabase {
  static const String databaseName = 'qara.db';
  static const String legacyDatabaseName = 'evangelism_caller_id.db';
  static const int databaseVersion = 2;

  static const String tableCallCenters = 'call_centers';
  static const String tableContacts = 'contacts';
  static const String tableInteractions = 'interactions';

  Database? _db;

  /// Default constructor for production app
  AppDatabase();

  /// Testing constructor for injecting an in-memory or mock Database
  AppDatabase.withDatabase(Database db) : _db = db;

  /// Returns the active SQLite database instance, initializing if needed.
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, databaseName);
    final legacyPath = p.join(dbPath, legacyDatabaseName);

    try {
      final legacyFile = File(legacyPath);
      final newFile = File(path);
      if (await legacyFile.exists() && !await newFile.exists()) {
        await legacyFile.copy(path);
      }
    } catch (_) {
      // In-memory or platform where File is not supported
    }

    return await openDatabase(
      path,
      version: databaseVersion,
      onCreate: createTables,
      onUpgrade: onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    // Enable SQLite foreign key constraints
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Creates all required database tables and indexes.
  static Future<void> createTables(Database db, int version) async {
    // 1. Call Centers Table (Projects / Campaigns)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCallCenters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        location TEXT,
        color_hex TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_call_centers_created_at
      ON $tableCallCenters (created_at DESC)
    ''');

    // 2. Contacts Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableContacts (
        id TEXT PRIMARY KEY,
        call_center_id TEXT,
        name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        normalized_phone_number TEXT NOT NULL UNIQUE,
        location TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (call_center_id) REFERENCES $tableCallCenters (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_contacts_call_center_id
      ON $tableContacts (call_center_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_contacts_call_center_created
      ON $tableContacts (call_center_id, created_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_contacts_normalized_phone
      ON $tableContacts (normalized_phone_number)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_contacts_name ON $tableContacts (name)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_contacts_location ON $tableContacts (location)
    ''');

    // 3. Interactions History Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableInteractions (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        date TEXT NOT NULL,
        outcome TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (contact_id) REFERENCES $tableContacts (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_interactions_contact_id
      ON $tableInteractions (contact_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_interactions_date
      ON $tableInteractions (date DESC)
    ''');
  }

  /// Migrates database schemas across versions without data loss.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Create call_centers table if upgrading from v1
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableCallCenters (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          location TEXT,
          color_hex TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_call_centers_created_at
        ON $tableCallCenters (created_at DESC)
      ''');

      // Check if call_center_id column exists in contacts table
      final tableInfo = await db.rawQuery('PRAGMA table_info($tableContacts)');
      final columnNames = tableInfo.map((row) => row['name'] as String).toList();

      if (!columnNames.contains('call_center_id')) {
        await db.execute(
          'ALTER TABLE $tableContacts ADD COLUMN call_center_id TEXT REFERENCES $tableCallCenters(id) ON DELETE CASCADE',
        );
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_contacts_call_center_id
          ON $tableContacts (call_center_id)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_contacts_call_center_created
          ON $tableContacts (call_center_id, created_at DESC)
        ''');
      }

      // If existing contacts have no call_center_id, group them into a default "General Outreach" Call Center
      final unassignedCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableContacts WHERE call_center_id IS NULL'),
      ) ?? 0;

      if (unassignedCount > 0) {
        final now = DateTime.now().toIso8601String();
        const defaultCenterId = 'default_general_outreach';

        await db.rawInsert('''
          INSERT OR IGNORE INTO $tableCallCenters (id, name, description, location, color_hex, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', [
          defaultCenterId,
          'General Outreach',
          'Imported legacy contacts',
          null,
          '#3F51B5',
          now,
          now,
        ]);

        await db.rawUpdate('''
          UPDATE $tableContacts
          SET call_center_id = ?
          WHERE call_center_id IS NULL
        ''', [defaultCenterId]);
      }
    }
  }

  // ==========================================
  // CALL CENTER CRUD OPERATIONS
  // ==========================================

  /// Inserts a new Call Center (outreach campaign/project).
  Future<void> insertCallCenter(CallCenter center) async {
    final db = await database;
    await db.insert(
      tableCallCenters,
      center.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Retrieves all Call Centers ordered with the newest first,
  /// including the dynamic contact count for each center.
  Future<List<CallCenter>> getAllCallCenters() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT cc.*, COUNT(c.id) AS contact_count
      FROM $tableCallCenters cc
      LEFT JOIN $tableContacts c ON c.call_center_id = cc.id
      GROUP BY cc.id
      ORDER BY cc.created_at DESC
    ''');

    return results.map((row) => CallCenter.fromMap(row)).toList();
  }

  /// Finds a specific Call Center by ID, including its contact count.
  Future<CallCenter?> getCallCenterById(String id) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT cc.*, COUNT(c.id) AS contact_count
      FROM $tableCallCenters cc
      LEFT JOIN $tableContacts c ON c.call_center_id = cc.id
      WHERE cc.id = ?
      GROUP BY cc.id
      LIMIT 1
    ''', [id]);

    if (results.isEmpty) return null;
    return CallCenter.fromMap(results.first);
  }

  /// Updates an existing Call Center's name, description, or location.
  Future<int> updateCallCenter(CallCenter center) async {
    final db = await database;
    return await db.update(
      tableCallCenters,
      center.toMap(),
      where: 'id = ?',
      whereArgs: [center.id],
    );
  }

  /// Deletes a Call Center and cascades deletion to all its contacts and interaction history.
  Future<int> deleteCallCenter(String id) async {
    final db = await database;
    return await db.delete(
      tableCallCenters,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns the total number of Call Centers.
  Future<int> getCallCentersCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $tableCallCenters');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==========================================
  // CONTACT CRUD OPERATIONS
  // ==========================================

  /// Inserts a new contact into the database.
  /// Throws [DuplicatePhoneNumberException] if the normalized number already exists.
  Future<void> insertContact(Contact contact) async {
    final db = await database;
    try {
      await db.insert(
        tableContacts,
        contact.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DuplicatePhoneNumberException(
          'A contact with phone number ${contact.phoneNumber} (${contact.normalizedPhoneNumber}) already exists.',
        );
      }
      rethrow;
    }
  }

  /// Inserts multiple contacts in a single SQLite batch transaction for high-performance bulk operations.
  Future<void> insertContactsBatch(List<Contact> contacts) async {
    final db = await database;
    final batch = db.batch();
    for (final contact in contacts) {
      batch.insert(
        tableContacts,
        contact.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Finds a contact by their unique ID.
  Future<Contact?> getContactById(String id) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT c.*, cc.name AS call_center_name
      FROM $tableContacts c
      LEFT JOIN $tableCallCenters cc ON cc.id = c.call_center_id
      WHERE c.id = ?
      LIMIT 1
    ''', [id]);

    if (results.isEmpty) return null;
    return Contact.fromMap(results.first);
  }

  /// Retrieves all contacts belonging to a specific Call Center.
  /// GUARANTEE: Strictly sorted with new additions at the TOP (`created_at DESC`).
  Future<List<Contact>> getContactsByCallCenter(String callCenterId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT c.*, cc.name AS call_center_name
      FROM $tableContacts c
      LEFT JOIN $tableCallCenters cc ON cc.id = c.call_center_id
      WHERE c.call_center_id = ?
      ORDER BY c.created_at DESC
    ''', [callCenterId]);

    return results.map(Contact.fromMap).toList();
  }

  /// Searches contacts within a specific Call Center.
  /// GUARANTEE: Strictly sorted with new additions at the TOP (`created_at DESC`).
  Future<List<Contact>> searchContactsInCallCenter(
    String callCenterId,
    String query,
  ) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return getContactsByCallCenter(callCenterId);
    }

    final db = await database;
    final searchPattern = '%$cleanQuery%';
    final results = await db.rawQuery('''
      SELECT c.*, cc.name AS call_center_name
      FROM $tableContacts c
      LEFT JOIN $tableCallCenters cc ON cc.id = c.call_center_id
      WHERE c.call_center_id = ?
        AND (c.name LIKE ? OR c.phone_number LIKE ? OR c.normalized_phone_number LIKE ? OR c.location LIKE ? OR c.notes LIKE ?)
      ORDER BY c.created_at DESC
    ''', [callCenterId, searchPattern, searchPattern, searchPattern, searchPattern, searchPattern]);

    return results.map(Contact.fromMap).toList();
  }

  /// Finds a contact across any Call Center by incoming phone number.
  /// Used during incoming call screening!
  Future<Contact?> findContactByPhoneNumber(String phoneNumber) async {
    final db = await database;
    final normalized = PhoneNumberNormalizer.normalize(phoneNumber);
    if (normalized == null) return null;

    final results = await db.rawQuery('''
      SELECT c.*, cc.name AS call_center_name
      FROM $tableContacts c
      LEFT JOIN $tableCallCenters cc ON cc.id = c.call_center_id
      WHERE c.normalized_phone_number = ?
      LIMIT 1
    ''', [normalized]);

    if (results.isNotEmpty) {
      return Contact.fromMap(results.first);
    }
    return null;
  }

  /// Global search across all Call Centers.
  Future<List<Contact>> searchContacts(String query) async {
    final db = await database;
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return getAllContacts();
    }

    final searchPattern = '%$cleanQuery%';
    final results = await db.rawQuery('''
      SELECT c.*, cc.name AS call_center_name
      FROM $tableContacts c
      LEFT JOIN $tableCallCenters cc ON cc.id = c.call_center_id
      WHERE c.name LIKE ? OR c.phone_number LIKE ? OR c.normalized_phone_number LIKE ? OR c.location LIKE ?
      ORDER BY c.created_at DESC
    ''', [searchPattern, searchPattern, searchPattern, searchPattern]);

    return results.map(Contact.fromMap).toList();
  }

  /// Returns all contacts across all Call Centers with newest additions first.
  /// Used for Caller ID synchronization to native Android and iOS extensions.
  Future<List<Contact>> getAllContacts() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT c.*, cc.name AS call_center_name
      FROM $tableContacts c
      LEFT JOIN $tableCallCenters cc ON cc.id = c.call_center_id
      ORDER BY c.created_at DESC
    ''');
    return results.map(Contact.fromMap).toList();
  }

  /// Updates an existing contact.
  Future<int> updateContact(Contact contact) async {
    final db = await database;
    return await db.update(
      tableContacts,
      contact.toMap(),
      where: 'id = ?',
      whereArgs: [contact.id],
    );
  }

  /// Deletes a contact and automatically cascades to delete their interactions.
  Future<int> deleteContact(String id) async {
    final db = await database;
    return await db.delete(
      tableContacts,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==========================================
  // INTERACTION HISTORY OPERATIONS
  // ==========================================

  /// Records a new outreach or follow-up interaction for a contact.
  Future<void> addInteraction(Interaction interaction) async {
    final db = await database;
    await db.insert(
      tableInteractions,
      interaction.toMap(),
    );
  }

  /// Retrieves all interactions for a specific contact, ordered from newest to oldest.
  Future<List<Interaction>> getInteractionsForContact(String contactId) async {
    final db = await database;
    final results = await db.query(
      tableInteractions,
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'date DESC',
    );
    return results.map(Interaction.fromMap).toList();
  }

  /// Returns the most recent interaction for a contact, if any.
  Future<Interaction?> getLatestInteraction(String contactId) async {
    final db = await database;
    final results = await db.query(
      tableInteractions,
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Interaction.fromMap(results.first);
  }

  /// Closes the database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}

/// Thrown when attempting to insert a contact whose normalized phone number already exists.
class DuplicatePhoneNumberException implements Exception {
  final String message;
  const DuplicatePhoneNumberException(this.message);

  @override
  String toString() => 'DuplicatePhoneNumberException: $message';
}
