import 'package:cloud_firestore/cloud_firestore.dart';

/// SafeWalk incident category.
enum IncidentType {
  harassment,
  poorLighting,
  isolated,
  drunkCrowd,
  other;

  static IncidentType fromValue(String? value) {
    return IncidentType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => IncidentType.other,
    );
  }
}

String timeOfDayLabel(DateTime dt) {
  final hour = dt.hour;
  if (hour < 6) return 'Night';
  if (hour < 12) return 'Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 21) return 'Evening';
  return 'Night';
}

/// A SafeWalk incident report.
///
/// IMPORTANT — fully anonymous: unlike [RecognitionPost], there is no
/// internal-only identity field here at all. No userId or device id is
/// ever stored on an incident document, even for backend/moderation use.
class Incident {
  Incident({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.timeOfDay,
    required this.reportedAt,
  });

  final String id;
  final double latitude;
  final double longitude;
  final IncidentType type;
  final String timeOfDay;
  final DateTime reportedAt;

  factory Incident.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final location = data['location'] as GeoPoint?;
    final rawReportedAt = data['reportedAt'];

    return Incident(
      id: doc.id,
      latitude: location?.latitude ?? 0,
      longitude: location?.longitude ?? 0,
      type: IncidentType.fromValue(data['type'] as String?),
      timeOfDay: data['timeOfDay'] as String? ?? timeOfDayLabel(DateTime.now()),
      reportedAt: rawReportedAt is Timestamp ? rawReportedAt.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'location': GeoPoint(latitude, longitude),
      'type': type.name,
      'timeOfDay': timeOfDay,
      'reportedAt': Timestamp.fromDate(reportedAt),
    };
  }
}
