/// CallCenter Model
///
/// Represents an evangelism outreach campaign, project, or location grouping
/// (analogous to 'Projects' in ChatGPT or 'Gems' in Gemini).
///
/// Each Call Center contains a focused collection of contacts gathered during
/// that specific outreach event or dedicated follow-up campaign.
class CallCenter {
  final String id;
  final String name;
  final String? description;
  final String? location;
  final String? colorHex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int contactCount;

  const CallCenter({
    required this.id,
    required this.name,
    this.description,
    this.location,
    this.colorHex,
    required this.createdAt,
    required this.updatedAt,
    this.contactCount = 0,
  });

  CallCenter copyWith({
    String? id,
    String? name,
    String? description,
    String? location,
    String? colorHex,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? contactCount,
  }) {
    return CallCenter(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      contactCount: contactCount ?? this.contactCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'location': location,
      'color_hex': colorHex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CallCenter.fromMap(Map<String, dynamic> map, {int contactCount = 0}) {
    return CallCenter(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Untitled Call Center',
      description: map['description'] as String?,
      location: map['location'] as String?,
      colorHex: map['color_hex'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      contactCount: (map['contact_count'] as num?)?.toInt() ?? contactCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallCenter &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;

  @override
  String toString() =>
      'CallCenter(id: $id, name: $name, contacts: $contactCount, location: $location)';
}

