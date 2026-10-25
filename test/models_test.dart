import 'package:flutter_test/flutter_test.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/models/interaction.dart';

void main() {
  group('Contact Model Tests', () {
    final now = DateTime.parse('2026-10-20T12:00:00.000Z');

    final testContact = Contact(
      id: 'contact-1',
      name: 'Kofi Mensah',
      phoneNumber: '0244123456',
      normalizedPhoneNumber: '+233244123456',
      location: 'Tema Community 1',
      notes: 'Met at outreach near the market',
      createdAt: now,
      updatedAt: now,
    );

    test('serializes to map and deserializes back faithfully', () {
      final map = testContact.toMap();
      expect(map['id'], 'contact-1');
      expect(map['name'], 'Kofi Mensah');
      expect(map['phone_number'], '0244123456'); // Preserves leading zero!
      expect(map['normalized_phone_number'], '+233244123456');
      expect(map['location'], 'Tema Community 1');

      final reconstructed = Contact.fromMap(map);
      expect(reconstructed.id, testContact.id);
      expect(reconstructed.name, testContact.name);
      expect(reconstructed.phoneNumber, testContact.phoneNumber);
      expect(reconstructed.normalizedPhoneNumber, testContact.normalizedPhoneNumber);
      expect(reconstructed.location, testContact.location);
      expect(reconstructed.notes, testContact.notes);
    });

    test('copyWith updates fields without mutating the original', () {
      final updated = testContact.copyWith(
        name: 'Kofi Mensah Jr.',
        location: 'Accra Central',
      );

      expect(updated.name, 'Kofi Mensah Jr.');
      expect(updated.location, 'Accra Central');
      expect(updated.phoneNumber, '0244123456'); // Unchanged
      expect(testContact.name, 'Kofi Mensah'); // Original remained untouched
    });

    test('handles missing optional fields in fromMap gracefully', () {
      final minimalMap = {
        'id': 'contact-2',
        'name': null,
        'phone_number': '0551122334',
        'normalized_phone_number': '+233551122334',
        'location': null,
        'notes': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final contact = Contact.fromMap(minimalMap);
      expect(contact.name, 'Unknown Contact');
      expect(contact.location, isNull);
      expect(contact.notes, isNull);
      expect(contact.phoneNumber, '0551122334');
    });
  });

  group('Interaction Model Tests', () {
    final now = DateTime.parse('2026-10-20T12:00:00.000Z');

    final testInteraction = Interaction(
      id: 'inter-1',
      contactId: 'contact-1',
      date: now,
      outcome: 'Called; no answer',
      notes: 'Rang 5 times, will call back Thursday',
      createdAt: now,
    );

    test('serializes to map and deserializes back faithfully', () {
      final map = testInteraction.toMap();
      expect(map['id'], 'inter-1');
      expect(map['contact_id'], 'contact-1');
      expect(map['outcome'], 'Called; no answer');

      final reconstructed = Interaction.fromMap(map);
      expect(reconstructed.id, testInteraction.id);
      expect(reconstructed.contactId, testInteraction.contactId);
      expect(reconstructed.outcome, testInteraction.outcome);
      expect(reconstructed.notes, testInteraction.notes);
    });

    test('copyWith updates fields without mutating original', () {
      final updated = testInteraction.copyWith(
        outcome: 'Conversation completed',
      );

      expect(updated.outcome, 'Conversation completed');
      expect(testInteraction.outcome, 'Called; no answer');
    });
  });
}
