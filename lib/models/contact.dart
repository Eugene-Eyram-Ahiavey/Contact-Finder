/// Contact Model
///
/// Represents an evangelism contact.
///
/// Critical Design Rules from Project Brief:
/// 1. [phoneNumber] MUST be stored as a String (not a number) to preserve
///    leading zeros (e.g., Ghanaian numbers starting with '024...') and international signs.
/// 2. [normalizedPhoneNumber] is the standardized E.164 string (e.g., '+233244123456')
///    used by the database index and native caller ID matching.
/// 3. [callCenterId] associates this contact with a specific outreach campaign/project.
/// 4. Interaction history is intentionally separated into the [Interaction] model
///    to allow appending follow-ups rather than overwriting past history.
class Contact {
  final String id;
  final String? callCenterId;
  final String? callCenterName;
  final String name;
  final String phoneNumber;
  final String normalizedPhoneNumber;
  final String? location;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Contact({
    required this.id,
    this.callCenterId,
    this.callCenterName,
    required this.name,
    required this.phoneNumber,
    required this.normalizedPhoneNumber,
    this.location,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// In JavaScript, you update an object immutably with the spread operator:
  /// `const updated = { ...contact, name: 'New Name' };`
  ///
  /// In Dart, classes use a `copyWith` method to produce a copy with selective field updates.
  Contact copyWith({
    String? id,
    String? callCenterId,
    String? callCenterName,
    String? name,
    String? phoneNumber,
    String? normalizedPhoneNumber,
    String? location,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id ?? this.id,
      callCenterId: callCenterId ?? this.callCenterId,
      callCenterName: callCenterName ?? this.callCenterName,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      normalizedPhoneNumber:
          normalizedPhoneNumber ?? this.normalizedPhoneNumber,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts the Contact instance into a Map for SQLite storage or JSON serialization.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'call_center_id': callCenterId,
      'name': name,
      'phone_number': phoneNumber,
      'normalized_phone_number': normalizedPhoneNumber,
      'location': location,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Reconstructs a Contact instance from a database row Map.
  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'] as String,
      callCenterId: map['call_center_id'] as String?,
      callCenterName: map['call_center_name'] as String?,
      name: map['name'] as String? ?? 'Unknown Contact',
      phoneNumber: map['phone_number'] as String,
      normalizedPhoneNumber: map['normalized_phone_number'] as String,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Contact &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          phoneNumber == other.phoneNumber &&
          normalizedPhoneNumber == other.normalizedPhoneNumber;

  @override
  int get hashCode =>
      id.hashCode ^ phoneNumber.hashCode ^ normalizedPhoneNumber.hashCode;

  @override
  String toString() =>
      'Contact(id: $id, name: $name, phone: $phoneNumber, center: $callCenterId)';
}
