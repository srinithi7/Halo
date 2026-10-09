import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/moderation_service.dart';
import '../utils/geo.dart';

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

/// How much of the reporter's identity a report carries.
///
/// The default is [anonymous], and that default is not negotiable for the
/// sensitive categories: a report that can be traced to a person is a
/// different product with different risks, so it is opt-in and labelled.
enum ReportAnonymity {
  /// Nothing identifying is written. Not even a pseudonym.
  anonymous,

  /// A stable, non-reversible handle is written so the same person can be
  /// rate-limited and can recognise their own reports. Still no raw user id,
  /// so there is nothing to de-anonymise. See [ReporterPseudonym].
  pseudonymous;

  static ReportAnonymity fromValue(String? value) {
    return ReportAnonymity.values.firstWhere(
      (a) => a.name == value,
      orElse: () => ReportAnonymity.anonymous,
    );
  }

  String get label {
    switch (this) {
      case ReportAnonymity.anonymous:
        return 'Anonymous';
      case ReportAnonymity.pseudonymous:
        return 'Pseudonymous';
    }
  }
}

/// A SafeWalk incident report.
///
/// Identity handling is explicit rather than incidental: every report carries
/// a [ReportAnonymity] value, so "was this anonymous?" is a recorded fact and
/// not an inference from which fields happen to be present. The raw user id is
/// never written here under any setting — a pseudonym is the most that ever
/// leaves the device.
class Incident {
  Incident({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.timeOfDay,
    required this.reportedAt,
    this.description,
    this.geohashPrefix,
    this.anonymity = ReportAnonymity.anonymous,
    this.reporterHandle,
    this.locationSource,
    this.moderationStatusName,
  });

  final String id;
  final double latitude;
  final double longitude;
  final IncidentType type;
  final String timeOfDay;
  final DateTime reportedAt;

  /// Free-text detail, only ever set when [type] is [IncidentType.other] —
  /// the fixed categories are self-explanatory and don't need it.
  final String? description;

  /// 5-character geohash of this report's location. Stored on every write
  /// so "reports near me" is a server-side geohash range query (a bounding
  /// box) rather than an unbounded global scan, with the exact radius
  /// applied afterwards by [distanceMeters].
  final String? geohashPrefix;

  /// Whether this report was filed anonymously or with a stable
  /// pseudonymous handle. Recorded explicitly, never inferred.
  final ReportAnonymity anonymity;

  /// Stable pseudonym for the reporter, present only when
  /// [anonymity] is [ReportAnonymity.pseudonymous]. Null for a fully
  /// anonymous report. This is never a user id and is never displayed.
  final String? reporterHandle;

  /// True when this report carries no link back to the reporter at all.
  bool get isFullyAnonymous => anonymity == ReportAnonymity.anonymous;

  /// How this report's coordinates were obtained: `gps` when they came from
  /// the device's own position fix, `mapPoint` when a user picked a point on
  /// the map, `crosshair` when the map centre was used.
  ///
  /// Recorded because the two mean very different things. A GPS report is
  /// something that happened *to you*; a map-point report is someone
  /// describing a place, and the difference matters to anyone reading it.
  final String? locationSource;

  /// Raw moderation value as stored, kept as the wire representation so the
  /// model stays a plain data mirror of the document.
  final String? moderationStatusName;

  /// Layer 1 + Layer 2 moderation state. Defaults to published so a
  /// pre-moderation report is never invisible by accident.
  IncidentModerationStatus get moderationStatus =>
      IncidentModerationStatus.fromValue(moderationStatusName);

  /// Whether this report has cleared Layer 1 without flags, or has been
  /// confirmed by Layer 2. Unconfirmed reports are marked in the UI but stay
  /// visible — they are real signal, just not corroborated.
  bool get isConfirmed =>
      moderationStatus == IncidentModerationStatus.published ||
      moderationStatus == IncidentModerationStatus.confirmed;

  factory Incident.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final location = data['location'] as GeoPoint?;
    final rawReportedAt = data['reportedAt'];
    final geohash = data['geohashPrefix'] as String?;

    return Incident(
      id: doc.id,
      latitude: location?.latitude ?? 0,
      longitude: location?.longitude ?? 0,
      type: IncidentType.fromValue(data['type'] as String?),
      timeOfDay: data['timeOfDay'] as String? ?? timeOfDayLabel(DateTime.now()),
      reportedAt:
          rawReportedAt is Timestamp ? rawReportedAt.toDate() : DateTime.now(),
      description: data['description'] as String?,
      reporterHandle: data['reporterHandle'] as String?,
      locationSource: data['locationSource'] as String?,
      moderationStatusName: data['moderationStatus'] as String?,
      anonymity: ReportAnonymity.fromValue(data['anonymity'] as String?),
      geohashPrefix: geohash ??
          (location == null
              ? null
              : encodeGeohash(location.latitude, location.longitude)),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'location': GeoPoint(latitude, longitude),
      'type': type.name,
      'timeOfDay': timeOfDay,
      'reportedAt': Timestamp.fromDate(reportedAt),
      'description': description,
      'anonymity': anonymity.name,
      // Written as null rather than omitted, so a report can never be
      // misread as "pseudonymous but the handle was lost".
      'reporterHandle':
          anonymity == ReportAnonymity.pseudonymous ? reporterHandle : null,
      'geohashPrefix': geohashPrefix ?? encodeGeohash(latitude, longitude),
      'locationSource': locationSource,
    };
  }

  Incident copyWith({
    String? id,
    double? latitude,
    double? longitude,
    IncidentType? type,
    String? timeOfDay,
    DateTime? reportedAt,
    String? description,
    String? geohashPrefix,
    ReportAnonymity? anonymity,
    String? reporterHandle,
    String? locationSource,
    String? moderationStatusName,
  }) {
    return Incident(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      reportedAt: reportedAt ?? this.reportedAt,
      description: description ?? this.description,
      geohashPrefix: geohashPrefix ?? this.geohashPrefix,
      anonymity: anonymity ?? this.anonymity,
      reporterHandle: reporterHandle ?? this.reporterHandle,
      locationSource: locationSource ?? this.locationSource,
      moderationStatusName: moderationStatusName ?? this.moderationStatusName,
    );
  }
}
