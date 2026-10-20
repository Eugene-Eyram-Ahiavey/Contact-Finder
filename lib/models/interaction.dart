/// Interaction Model
///
/// Represents an outreach or follow-up interaction with a contact.
///
/// Critical Design Rules from Project Brief:
/// 1. Must be kept separate from the basic Contact model.
/// 2. Each phone call or visit appends a new Interaction to the history,
///    preserving past context rather than overwriting it.
class Interaction {
  final String id;
  final String contactId;
  final DateTime date;
  final String outcome;
  final String? notes;
  final DateTime createdAt;

  const Interaction({
    required this.id,
    required this.contactId,
    required this.date,
    required this.outcome,
    this.notes,
    required this.createdAt,
  });

  Interaction copyWith({
    String? id,
    String? contactId,
    DateTime? date,
    String? outcome,
    String? notes,
    DateTime? createdAt,
  }) {
    return Interaction(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      date: date ?? this.date,
      outcome: outcome ?? this.outcome,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contact_id': contactId,
      'date': date.toIso8601String(),
      'outcome': outcome,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Interaction.fromMap(Map<String, dynamic> map) {
    return Interaction(
      id: map['id'] as String,
      contactId: map['contact_id'] as String,
      date: DateTime.parse(map['date'] as String),
      outcome: map['outcome'] as String,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Interaction &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          contactId == other.contactId;

  @override
  int get hashCode => id.hashCode ^ contactId.hashCode;

  @override
  String toString() =>
      'Interaction(id: $id, contactId: $contactId, outcome: $outcome, date: $date)';
}
