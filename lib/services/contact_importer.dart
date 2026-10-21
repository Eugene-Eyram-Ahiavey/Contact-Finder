import 'package:uuid/uuid.dart';
import 'package:evangelism_caller_id/models/contact.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

/// Result of parsing an imported text or list.
class ImportBatchResult {
  final List<Contact> validContacts;
  final List<SkippedImportLine> skippedLines;
  final List<Contact> duplicateInBatch;

  const ImportBatchResult({
    required this.validContacts,
    required this.skippedLines,
    required this.duplicateInBatch,
  });

  int get totalLinesProcessed =>
      validContacts.length + skippedLines.length + duplicateInBatch.length;
}

class SkippedImportLine {
  final int lineNumber;
  final String rawLine;
  final String reason;

  const SkippedImportLine({
    required this.lineNumber,
    required this.rawLine,
    required this.reason,
  });
}

/// ContactImporter
///
/// Intelligently parses unstructured outreach lists copied from Apple Notes,
/// Google Keep, WhatsApp, or CSV/spreadsheet rows.
///
/// Supported common evangelism note patterns:
/// - "Kofi Mensah - 0244123456 - Tema - Prayed for healing"
/// - "Ama Serwaa, 0551122334, Spintex"
/// - "0277889900 - Kwabena (Madina)"
/// - "Pastor John: 0201234567"
/// - Tab-separated text copied from Excel: "Name\tPhone\tLocation\tNotes"
class ContactImporter {
  static const _uuid = Uuid();

  /// Regex pattern to locate a potential phone number within a line of text:
  /// Matches strings starting with optional '+' or '0', followed by digits, spaces, hyphens, parentheses (7 to 16 chars).
  static final RegExp _phonePattern = RegExp(
    r'(?:\+?\d{1,3}[\s-]?)?\(?0?\d{2,4}\)?[\s.-]?\d{3}[\s.-]?\d{3,4}',
  );

  /// Parses raw pasted text into validated [Contact] instances and flags any issues.
  static ImportBatchResult parseText(String rawText) {
    final lines = rawText.split(RegExp(r'\r?\n'));
    final List<Contact> valid = [];
    final List<SkippedImportLine> skipped = [];
    final List<Contact> duplicates = [];
    final Set<String> seenNormalizedNumbers = {};

    final now = DateTime.now();

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i].trim();
      final lineNumber = i + 1;

      // Skip completely empty lines
      if (rawLine.isEmpty) continue;

      // Check if this is a header row (e.g., from CSV or table copy)
      if (_isHeaderRow(rawLine)) {
        continue;
      }

      // 1. Locate the phone number within the line
      final phoneMatch = _phonePattern.firstMatch(rawLine);
      if (phoneMatch == null) {
        skipped.add(SkippedImportLine(
          lineNumber: lineNumber,
          rawLine: rawLine,
          reason: 'No phone number detected on this line',
        ));
        continue;
      }

      final rawPhone = phoneMatch.group(0)!.trim();
      final normalized = PhoneNumberNormalizer.normalize(rawPhone);

      if (normalized == null) {
        skipped.add(SkippedImportLine(
          lineNumber: lineNumber,
          rawLine: rawLine,
          reason: 'Invalid phone number format ("$rawPhone")',
        ));
        continue;
      }

      // Check for duplicate phone number within this same batch
      if (seenNormalizedNumbers.contains(normalized)) {
        duplicates.add(Contact(
          id: _uuid.v4(),
          name: 'Duplicate ($rawPhone)',
          phoneNumber: rawPhone,
          normalizedPhoneNumber: normalized,
          createdAt: now,
          updatedAt: now,
        ));
        continue;
      }

      // 2. Extract remaining text to identify Name, Location, and Notes
      final lineWithoutPhone =
          rawLine.replaceFirst(rawPhone, '').trim();

      // Split the remainder by common separators: commas, tabs, hyphens, colons, or pipes
      final parts = lineWithoutPhone
          .split(RegExp(r'[\t,\|\:\–\—\-]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      String name = 'Unknown Contact';
      String? location;
      String? notes;

      if (parts.isNotEmpty) {
        name = parts[0];
      }

      if (parts.length > 1) {
        // Check if part 2 looks like a location or note
        location = parts[1];
      }

      if (parts.length > 2) {
        notes = parts.sublist(2).join(' - ');
      }

      seenNormalizedNumbers.add(normalized);

      valid.add(Contact(
        id: _uuid.v4(),
        name: name,
        phoneNumber: rawPhone,
        normalizedPhoneNumber: normalized,
        location: location,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      ));
    }

    return ImportBatchResult(
      validContacts: valid,
      skippedLines: skipped,
      duplicateInBatch: duplicates,
    );
  }

  /// Determines whether a line is a header row (e.g. "Name, Phone, Location")
  static bool _isHeaderRow(String line) {
    final lower = line.toLowerCase();
    final hasName = lower.contains('name');
    final hasPhone = lower.contains('phone') ||
        lower.contains('number') ||
        lower.contains('mobile') ||
        lower.contains('contact');
    return hasName && hasPhone;
  }
}
