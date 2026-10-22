import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';
import 'package:evangelism_caller_id/models/contact.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

/// Result of parsing an imported text or spreadsheet.
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
/// Google Keep, WhatsApp, CSV files, or Excel spreadsheets (.xlsx).
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

  /// Parses raw pasted text or CSV into validated [Contact] instances and flags any issues.
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

  /// Parses an Excel spreadsheet (.xlsx) binary data into [ImportBatchResult].
  static ImportBatchResult parseExcelBytes(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final List<Contact> valid = [];
    final List<SkippedImportLine> skipped = [];
    final List<Contact> duplicates = [];
    final Set<String> seenNormalizedNumbers = {};
    final now = DateTime.now();

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.rows.isEmpty) continue;

      int nameIdx = -1;
      int phoneIdx = -1;
      int locationIdx = -1;
      int notesIdx = -1;

      int startRow = 0;
      final headerRow = sheet.rows.first;
      for (int c = 0; c < headerRow.length; c++) {
        final val = headerRow[c]?.value?.toString().toLowerCase() ?? '';
        if (val.contains('name')) nameIdx = c;
        if (val.contains('phone') ||
            val.contains('number') ||
            val.contains('mobile') ||
            val.contains('contact')) {
          phoneIdx = c;
        }
        if (val.contains('loc') ||
            val.contains('area') ||
            val.contains('city') ||
            val.contains('town')) {
          locationIdx = c;
        }
        if (val.contains('note') ||
            val.contains('remark') ||
            val.contains('comment') ||
            val.contains('detail')) {
          notesIdx = c;
        }
      }

      if (phoneIdx != -1) {
        startRow = 1;
      }

      for (int r = startRow; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String? rawPhone;
        String name = 'Unknown Contact';
        String? location;
        String? notes;

        if (phoneIdx != -1 && phoneIdx < row.length && row[phoneIdx]?.value != null) {
          rawPhone = row[phoneIdx]!.value.toString().trim();
          if (nameIdx != -1 && nameIdx < row.length && row[nameIdx]?.value != null) {
            name = row[nameIdx]!.value.toString().trim();
          }
          if (locationIdx != -1 && locationIdx < row.length && row[locationIdx]?.value != null) {
            location = row[locationIdx]!.value.toString().trim();
          }
          if (notesIdx != -1 && notesIdx < row.length && row[notesIdx]?.value != null) {
            notes = row[notesIdx]!.value.toString().trim();
          }
        } else {
          // Heuristic cell search
          for (int c = 0; c < row.length; c++) {
            final cellStr = row[c]?.value?.toString().trim() ?? '';
            final match = _phonePattern.firstMatch(cellStr);
            if (match != null && rawPhone == null) {
              rawPhone = match.group(0);
            } else if (cellStr.isNotEmpty && name == 'Unknown Contact') {
              name = cellStr;
            } else if (cellStr.isNotEmpty && location == null) {
              location = cellStr;
            } else if (cellStr.isNotEmpty) {
              notes = (notes == null) ? cellStr : '$notes - $cellStr';
            }
          }
        }

        if (rawPhone == null || rawPhone.isEmpty) {
          final rowSummary = row.map((c) => c?.value?.toString() ?? '').join(', ').trim();
          if (rowSummary.isNotEmpty) {
            skipped.add(SkippedImportLine(
              lineNumber: r + 1,
              rawLine: rowSummary,
              reason: 'No phone number found in row',
            ));
          }
          continue;
        }

        final normalized = PhoneNumberNormalizer.normalize(rawPhone);
        if (normalized == null) {
          skipped.add(SkippedImportLine(
            lineNumber: r + 1,
            rawLine: '$name ($rawPhone)',
            reason: 'Invalid phone number format ("$rawPhone")',
          ));
          continue;
        }

        if (seenNormalizedNumbers.contains(normalized)) {
          duplicates.add(Contact(
            id: _uuid.v4(),
            name: name,
            phoneNumber: rawPhone,
            normalizedPhoneNumber: normalized,
            createdAt: now,
            updatedAt: now,
          ));
          continue;
        }

        seenNormalizedNumbers.add(normalized);
        valid.add(Contact(
          id: _uuid.v4(),
          name: name.isNotEmpty ? name : 'Unknown Contact',
          phoneNumber: rawPhone,
          normalizedPhoneNumber: normalized,
          location: location,
          notes: notes,
          createdAt: now,
          updatedAt: now,
        ));
      }
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
