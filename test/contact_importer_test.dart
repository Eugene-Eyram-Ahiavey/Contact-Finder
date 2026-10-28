import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qara/services/contact_importer.dart';

void main() {
  group('ContactImporter Tests', () {
    test('parses common hyphenated notes format faithfully', () {
      const sampleNotes = '''
Kofi Mensah - 0244123456 - Tema - Prayed for healing
Ama Serwaa - 0551122334 - Spintex - Wants Sunday ride
Brother John - 0277889900 - Madina
''';

      final result = ContactImporter.parseText(sampleNotes);
      expect(result.validContacts.length, 3);
      expect(result.skippedLines, isEmpty);
      expect(result.duplicateInBatch, isEmpty);

      final first = result.validContacts[0];
      expect(first.name, 'Kofi Mensah');
      expect(first.phoneNumber, '0244123456');
      expect(first.normalizedPhoneNumber, '+233244123456');
      expect(first.location, 'Tema');
      expect(first.notes, 'Prayed for healing');

      final second = result.validContacts[1];
      expect(second.name, 'Ama Serwaa');
      expect(second.phoneNumber, '0551122334');
      expect(second.normalizedPhoneNumber, '+233551122334');
      expect(second.location, 'Spintex');
      expect(second.notes, 'Wants Sunday ride');

      final third = result.validContacts[2];
      expect(third.name, 'Brother John');
      expect(third.location, 'Madina');
      expect(third.notes, isNull);
    });

    test('parses comma-separated and colon formats', () {
      const input = '''
Sister Grace, 0201234567, East Legon
Pastor Peter: 0241112233: Osu: Visiting next Tuesday
''';

      final result = ContactImporter.parseText(input);
      expect(result.validContacts.length, 2);

      expect(result.validContacts[0].name, 'Sister Grace');
      expect(result.validContacts[0].normalizedPhoneNumber, '+233201234567');
      expect(result.validContacts[0].location, 'East Legon');

      expect(result.validContacts[1].name, 'Pastor Peter');
      expect(result.validContacts[1].normalizedPhoneNumber, '+233241112233');
      expect(result.validContacts[1].location, 'Osu');
      expect(result.validContacts[1].notes, 'Visiting next Tuesday');
    });

    test('parses tab-separated values copied from Excel tables', () {
      const excelCopy = "Name\tPhone\tLocation\tNotes\n"
          "Emmanuel Tetteh\t0249876543\tDansoman\tAccepted Christ\n";

      final result = ContactImporter.parseText(excelCopy);
      expect(result.validContacts.length, 1); // Header row was intelligently skipped!
      expect(result.validContacts[0].name, 'Emmanuel Tetteh');
      expect(result.validContacts[0].normalizedPhoneNumber, '+233249876543');
      expect(result.validContacts[0].location, 'Dansoman');
      expect(result.validContacts[0].notes, 'Accepted Christ');
    });

    test('flags invalid lines without phone numbers', () {
      const mixedText = '''
Kofi Mensah - 0244123456 - Tema
Notes from outreach on Saturday:
Everyone was very welcoming!
Ama Serwaa - 0551122334 - Spintex
''';

      final result = ContactImporter.parseText(mixedText);
      expect(result.validContacts.length, 2);
      expect(result.skippedLines.length, 2);
      expect(result.skippedLines[0].lineNumber, 2);
      expect(result.skippedLines[0].reason, contains('No phone number'));
    });

    test('detects duplicate numbers within the same batch', () {
      const duplicateInput = '''
Kofi Mensah - 0244123456 - Tema
Kofi Duplicate - 024 412 3456 - Accra
''';

      final result = ContactImporter.parseText(duplicateInput);
      expect(result.validContacts.length, 1);
      expect(result.duplicateInBatch.length, 1);
    });

    test('parses binary Excel (.xlsx) file bytes faithfully', () {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Add Header
      sheet.appendRow([
        TextCellValue('Name'),
        TextCellValue('Phone Number'),
        TextCellValue('Location'),
        TextCellValue('Outreach Notes'),
      ]);

      // Add Contact Row 1
      sheet.appendRow([
        TextCellValue('Sarah Osei'),
        TextCellValue('0244556677'),
        TextCellValue('Airport Residential'),
        TextCellValue('Requested follow-up call'),
      ]);

      // Add Contact Row 2
      sheet.appendRow([
        TextCellValue('David Kwarteng'),
        TextCellValue('+233501234567'),
        TextCellValue('Cantonments'),
        TextCellValue('Bible study invite'),
      ]);

      final bytes = excel.save()!;
      final result = ContactImporter.parseExcelBytes(bytes);

      expect(result.validContacts.length, 2);
      expect(result.skippedLines, isEmpty);

      final first = result.validContacts[0];
      expect(first.name, 'Sarah Osei');
      expect(first.phoneNumber, '0244556677');
      expect(first.normalizedPhoneNumber, '+233244556677');
      expect(first.location, 'Airport Residential');
      expect(first.notes, 'Requested follow-up call');

      final second = result.validContacts[1];
      expect(second.name, 'David Kwarteng');
      expect(second.phoneNumber, '+233501234567');
      expect(second.normalizedPhoneNumber, '+233501234567');
      expect(second.location, 'Cantonments');
      expect(second.notes, 'Bible study invite');
    });

    test('binds parsed contacts to specified callCenterId', () {
      const notes = 'Samuel Addo - 0241239876 - Madina';
      final result = ContactImporter.parseText(notes, callCenterId: 'center-madina');
      expect(result.validContacts.length, 1);
      expect(result.validContacts[0].callCenterId, 'center-madina');
    });
  });
}
