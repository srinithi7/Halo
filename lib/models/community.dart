import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart' as ll;

/// A joinable community — the real, membership-backed replacement for the
/// old free-text hashtag/groupId placeholder. Recognitions are submitted
/// into one community (stored in [RecognitionPost.groupId], which now
/// holds a [Community.id] rather than an arbitrary hashtag string), and
/// the Unsung Hero calculation (see lib/utils/unsung_hero.dart) is always
/// scoped to one community.
class Community {
  Community({
    required this.id,
    required this.name,
    required this.description,
    required this.memberIds,
    required this.createdAt,
    required this.createdBy,
    this.latitude,
    this.longitude,
    this.radiusMeters,
  });

  final String id;
  final String name;
  final String description;

  /// Uids of every member. A simple list (like [RecognitionPost.glowedBy])
  /// rather than a subcollection — fine at this app's scale, and it lets
  /// "is this user a member" and "how many members" both read directly off
  /// the community doc with no extra query.
  final List<String> memberIds;
  final DateTime createdAt;
  final String createdBy;

  /// Optional geographic footprint. Communities created before this existed
  /// simply have no centre and stay name-based, so [center] is null for them
  /// and the map skips them rather than guessing a location.
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;

  ll.LatLng? get center {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return null;
    return ll.LatLng(lat, lng);
  }

  /// The drawable circle, or null when the community has no usable footprint
  /// (missing centre, or a non-positive/implausibly large radius).
  ({ll.LatLng point, double radius})? get footprint {
    final point = center;
    final radius = radiusMeters;
    if (point == null || radius == null || radius <= 0) return null;
    if (radius > 100000) return null;
    return (point: point, radius: radius);
  }

  bool hasMember(String uid) => memberIds.contains(uid);

  factory Community.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawCreatedAt = data['createdAt'];
    final center = data['center'] as GeoPoint?;
    return Community(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed community',
      description: data['description'] as String? ?? '',
      memberIds:
          (data['memberIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt:
          rawCreatedAt is Timestamp ? rawCreatedAt.toDate() : DateTime.now(),
      createdBy: data['createdBy'] as String? ?? '',
      latitude: center?.latitude ?? (data['latitude'] as num?)?.toDouble(),
      longitude: center?.longitude ?? (data['longitude'] as num?)?.toDouble(),
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'memberIds': memberIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'center': (latitude == null || longitude == null)
          ? null
          : GeoPoint(latitude!, longitude!),
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
    };
  }
}
