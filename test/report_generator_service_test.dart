import 'package:flutter_test/flutter_test.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/services/report_generator_service.dart';

void main() {
  group('ReportGeneratorService Tests', () {
    final now = DateTime.parse('2026-10-20T12:00:00.000Z');

    test('generates dynamic grouped report matching team statuses', () {
      final contacts = [
        Contact(
          id: '1',
          name: 'Kwabena Darko',
          phoneNumber: '0244111222',
          normalizedPhoneNumber: '+233244111222',
          location: 'East Legon',
          callStatus: 'Coming',
          createdAt: now,
          updatedAt: now,
        ),
        Contact(
          id: '2',
          name: 'Akua Mansa',
          phoneNumber: '0555333444',
          normalizedPhoneNumber: '+233555333444',
          callStatus: 'coming', // Different casing should group together
          createdAt: now,
          updatedAt: now,
        ),
        Contact(
          id: '3',
          name: 'Yaw Boateng',
          phoneNumber: '0200555666',
          normalizedPhoneNumber: '+233200555666',
          notes: 'Busy at work',
          callStatus: 'Invalid Number', // Custom dynamic status
          createdAt: now,
          updatedAt: now,
        ),
        Contact(
          id: '4',
          name: 'Kofi Mensah',
          phoneNumber: '0277888999',
          normalizedPhoneNumber: '+233277888999',
          callStatus: null, // Pending / to call
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final report = ReportGeneratorService.generateReport(
        title: 'TEST OUTREACH CALL REPORT',
        contacts: contacts,
      );

      // Verify Title
      expect(report.contains('*TEST OUTREACH CALL REPORT*'), isTrue);

      // Verify dynamic category headers
      expect(report.contains('*COMING (2)*'), isTrue);
      expect(report.contains('*INVALID NUMBER (1)*'), isTrue);
      expect(report.contains('*PENDING / TO CALL (1)*'), isTrue);

      // Verify contact lines inside sections
      expect(report.contains('01. Kwabena Darko - 024 411 1222 - East Legon'), isTrue);
      expect(report.contains('02. Akua Mansa - 055 533 3444'), isTrue);
      expect(report.contains('01. Yaw Boateng - 020 055 5666 - Busy at work'), isTrue);
      expect(report.contains('01. Kofi Mensah - 027 788 8999'), isTrue);

      // Verify executive summary footer
      expect(report.contains('*TOTAL CONTACTS: 4*'), isTrue);
      expect(report.contains('*COMING: 2*'), isTrue);
      expect(report.contains('*INVALID NUMBER: 1*'), isTrue);
      expect(report.contains('*PENDING / TO CALL: 1*'), isTrue);
    });

    test('generates empty report when contact list is empty', () {
      final report = ReportGeneratorService.generateReport(
        title: 'EMPTY REPORT',
        contacts: [],
      );

      expect(report, '*EMPTY REPORT*\n\nNo contacts in this Call Center.');
    });

    test('respects includePhoneNumbers flag', () {
      final contacts = [
        Contact(
          id: '1',
          name: 'Kwabena Darko',
          phoneNumber: '0244111222',
          normalizedPhoneNumber: '+233244111222',
          location: 'East Legon',
          callStatus: 'Coming',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final report = ReportGeneratorService.generateReport(
        title: 'NO NUMBERS REPORT',
        contacts: contacts,
        includePhoneNumbers: false,
      );

      expect(report.contains('024 411 1222'), isFalse);
      expect(report.contains('01. Kwabena Darko - East Legon'), isTrue);
    });

    test('getStatusSummary returns counts for all statuses', () {
      final contacts = [
        Contact(
          id: '1',
          name: 'Person A',
          phoneNumber: '0244000001',
          normalizedPhoneNumber: '+233244000001',
          callStatus: 'Coming',
          createdAt: now,
          updatedAt: now,
        ),
        Contact(
          id: '2',
          name: 'Person B',
          phoneNumber: '0244000002',
          normalizedPhoneNumber: '+233244000002',
          callStatus: 'Coming',
          createdAt: now,
          updatedAt: now,
        ),
        Contact(
          id: '3',
          name: 'Person C',
          phoneNumber: '0244000003',
          normalizedPhoneNumber: '+233244000003',
          callStatus: null,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final summary = ReportGeneratorService.getStatusSummary(contacts);
      expect(summary['COMING'], 2);
      expect(summary[ReportGeneratorService.pendingStatus], 1);
    });
  });
}

