class AssignmentModel {
  final String id;
  final String deviceId;
  final String personId;
  final DateTime assignedAt;
  final DateTime? unassignedAt;
  final String assignmentType;
  final String? notes;
  final String? personName;
  final String? personCode;

  AssignmentModel({
    required this.id,
    required this.deviceId,
    required this.personId,
    required this.assignedAt,
    this.unassignedAt,
    required this.assignmentType,
    this.notes,
    this.personName,
    this.personCode,
  });

  factory AssignmentModel.fromJson(Map<String, dynamic> json) {
    return AssignmentModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      personId: json['person_id'] ?? '',
      assignedAt: DateTime.parse(json['assigned_at']).toLocal(),
      unassignedAt: json['unassigned_at'] != null ? DateTime.parse(json['unassigned_at']).toLocal() : null,
      assignmentType: json['assignment_type'] ?? 'RESPONSIBLE',
      notes: json['notes'],
      personName: json['person_name'],
      personCode: json['person_code'],
    );
  }
}
