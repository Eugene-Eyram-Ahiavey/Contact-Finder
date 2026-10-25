import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/models/interaction.dart';
import 'package:qara/utils/phone_number_normalizer.dart';

/// AppDatabase
///
/// Manages local SQLite storage for evangelism contacts and interaction history.
///
/// Architectural Guarantees:
/// 1. Offline-first: Data is stored securely and directly on the device storage.
/// 2. Fast O(1) Caller ID Lookup: Normalized phone numbers are strictly indexed.
/// 3. Interaction History: Follow-ups are stored in a relational `interactions` table
///    linked to contacts by `contact_id`.
class AppDatabase {
  static const String databaseName = 'qara.db';
  static const String legacyDatabaseName = 'evangelism_caller_id.db';
  static const int databaseVersion = 1;

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
      onCreate: _createTables,
      onConfigure: _onConfigure,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    // Enable SQLite foreign key constraints
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _createTables(Database db, int version) async {
    // Contacts Table
    await db.execute('''
      CREATE TABLE $tableContacts (
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

    // Index for ultra-fast incoming-call lookup by normalized phone number
    await db.execute('''
      CREATE INDEX idx_contacts_normalized_phone
      ON $tableContacts (normalized_phone_number)
    ''');

    // Index for search by name and location
    await db.execute('''
      CREATE INDEX idx_contacts_name ON $tableContacts (name)
    ''');
    await db.execute('''
      CREATE INDEX idx_contacts_location ON $tableContacts (location)
    ''');

    // Interactions History Table
    await db.execute('''
      CREATE TABLE $tableInteractions (
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
      CREATE INDEX idx_interactions_contact_id
      ON $tableInteractions (contact_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_interactions_date
      ON $tableInteractions (date DESC)
    ''');
  }

  // ==========================================
  // CONTACT CRUD OPERATIONS
  // ==========================================

  /// Inserts a new contact into the database.
  /// If a contact with the same normalized phone number already exists,
  /// throws a [DuplicatePhoneNumberException].
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
    final results = await db.query(
      tableContacts,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Contact.fromMap(results.first);
  }

  /// Finds a contact by phone number (handles both raw local and normalized formats).
  /// This is the core method invoked during an incoming call!
  Future<Contact?> findContactByPhoneNumber(String phoneNumber) async {
    final db = await database;
    final normalized = PhoneNumberNormalizer.normalize(phoneNumber);
    if (normalized == null) return null;

    final results = await db.query(
      tableContacts,
      where: 'normalized_phone_number = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return Contact.fromMap(results.first);
    }
    return null;
  }

  /// Searches contacts across name, raw phone number, or location.
  Future<List<Contact>> searchContacts(String query) async {
    final db = await database;
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return getAllContacts();
    }

    final searchPattern = '%$cleanQuery%';
    final results = await db.query(
      tableContacts,
      where: 'name LIKE ? OR phone_number LIKE ? OR normalized_phone_number LIKE ? OR location LIKE ?',
      whereArgs: [searchPattern, searchPattern, searchPattern, searchPattern],
      orderBy: 'name ASC',
    );

    return results.map(Contact.fromMap).toList();
  }

  /// Returns all contacts ordered alphabetically by name.
  Future<List<Contact>> getAllContacts() async {
    final db = await database;
    final results = await db.query(
      tableContacts,
      orderBy: 'name ASC',
    );
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
  /// (Used by caller ID to show: "Last outcome: Called back; conversation completed").
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
