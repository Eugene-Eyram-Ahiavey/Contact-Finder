import 'package:qara/models/contact.dart';
import 'package:qara/utils/phone_number_normalizer.dart';

/// ReportGeneratorService
///
/// Generates formatted plain-text outreach call reports from contacts
/// within a Call Center. Reports are structured for WhatsApp sharing
/// with dynamic categorization based on whatever statuses team members
/// have actually used (no rigid predefined categories).
///
/// Design Principles:
/// 1. Dynamic Grouping: Categories are derived from actual contact statuses,
///    not hardcoded lists. If a team writes "Invalid Number" instead of
///    "Wrong Number", the report adapts automatically.
/// 2. WhatsApp Formatting: Uses * for bold headers (WhatsApp markdown).
/// 3. Clean Numbering: Each category section restarts numbering from 1.
/// 4. Executive Summary: Appended footer with total counts per category.
class ReportGeneratorService {
  /// The default status label for contacts that haven't been called yet.
  static const String pendingStatus = 'PENDING / TO CALL';

  /// Generates a complete formatted report string.
  ///
  /// [title] - Custom report heading (e.g., "SWOLLEN SATURDAY CALL LIST")
  /// [contacts] - All contacts in the Call Center
  /// [includePhoneNumbers] - Whether to include phone numbers in the report (default true)
  static String generateReport({
    required String title,
    required List<Contact> contacts,
    bool includePhoneNumbers = true,
  }) {
    if (contacts.isEmpty) {
      return '*$title*\n\nNo contacts in this Call Center.';
    }

    // Group contacts by their status (case-insensitive grouping, uppercase display)
    final Map<String, List<Contact>> groups = {};
    for (final contact in contacts) {
      final status = (contact.callStatus?.trim().isNotEmpty == true)
          ? contact.callStatus!.trim().toUpperCase()
          : pendingStatus;
      groups.putIfAbsent(status, () => []).add(contact);
    }

    // Sort group keys: put PENDING last, others alphabetically
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == pendingStatus) return 1;
        if (b == pendingStatus) return -1;
        return a.compareTo(b);
      });

    final buffer = StringBuffer();

    // Title
    buffer.writeln('*$title*');
    buffer.writeln();

    // Category sections
    for (final status in sortedKeys) {
      final categoryContacts = groups[status]!;
      buffer.writeln('*$status (${categoryContacts.length})*');
      buffer.writeln();

      for (int i = 0; i < categoryContacts.length; i++) {
        final c = categoryContacts[i];
        final number = '${i + 1}'.padLeft(2);
        final line = StringBuffer('$number. ${c.name}');

        if (includePhoneNumbers) {
          line.write(
              ' - ${PhoneNumberNormalizer.formatForDisplay(c.phoneNumber)}');
        }

        if (c.location != null && c.location!.trim().isNotEmpty) {
          line.write(' - ${c.location!.trim()}');
        }

        if (c.notes != null && c.notes!.trim().isNotEmpty) {
          line.write(' - ${c.notes!.trim()}');
        }

        buffer.writeln(line.toString());
      }

      buffer.writeln();
    }

    // Executive summary footer
    buffer.writeln();
    buffer.writeln('*TOTAL CONTACTS: ${contacts.length}*');

    for (final status in sortedKeys) {
      buffer.writeln('*$status: ${groups[status]!.length}*');
    }

    return buffer.toString().trimRight();
  }

  /// Returns a summary map of status -> count for display in the UI.
  static Map<String, int> getStatusSummary(List<Contact> contacts) {
    final Map<String, int> summary = {};
    for (final contact in contacts) {
      final status = (contact.callStatus?.trim().isNotEmpty == true)
          ? contact.callStatus!.trim().toUpperCase()
          : pendingStatus;
      summary[status] = (summary[status] ?? 0) + 1;
    }
    return summary;
  }
}
