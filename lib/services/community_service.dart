import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/community.dart';
import '../utils/geo.dart';

/// Firestore service layer for [Community] membership mutations.
class CommunityService {
  CommunityService._();

  static final _collection =
      FirebaseFirestore.instance.collection('communities');

  /// Creates a community. The geographic footprint is optional: a community
  /// with no centre stays a name-based team group and is simply not drawn on
  /// the SafeWalk map, so nothing is guessed on the user's behalf.
  static Future<void> create({
    required String name,
    required String description,
    required String creatorUid,
    double? latitude,
    double? longitude,
    double? radiusMeters,
  }) {
    final hasCenter = latitude != null && longitude != null;
    final community = Community(
      id: '',
      name: name,
      description: description,
      memberIds: [creatorUid],
      createdAt: DateTime.now(),
      createdBy: creatorUid,
      latitude: hasCenter ? latitude : null,
      longitude: hasCenter ? longitude : null,
      radiusMeters: hasCenter ? radiusMeters : null,
    );
    final payload = community.toFirestore();
    if (hasCenter) {
      payload['geohashPrefix'] = encodeGeohash(latitude, longitude);
    }
    return _collection.add(payload);
  }

  /// Adds [uid] to a community's members. Uses arrayUnion (not a
  /// read-modify-write of the full list) so concurrent joins from
  /// different users never race each other — same pattern as
  /// RecognitionService.toggleGlow.
  static Future<void> join(String communityId, String uid) {
    return _collection.doc(communityId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
    });
  }

  static Future<void> leave(String communityId, String uid) {
    return _collection.doc(communityId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
    });
  }

  /// Renames/redescribes a community — Firestore rules restrict this to
  /// the community's own creator (checked against createdBy server-side,
  /// not just hidden client-side).
  static Future<void> updateDetails(String communityId,
      {required String name, required String description}) {
    return _collection.doc(communityId).update({
      'name': name,
      'description': description,
    });
  }

  /// Sets (or clears) a community's map footprint. Clearing writes explicit
  /// nulls so the community goes back to being name-based instead of
  /// silently keeping a stale circle.
  static Future<void> updateArea(
    String communityId, {
    double? latitude,
    double? longitude,
    double? radiusMeters,
  }) {
    final hasCenter = latitude != null && longitude != null;
    return _collection.doc(communityId).update({
      'center': hasCenter ? GeoPoint(latitude, longitude) : null,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'geohashPrefix': hasCenter ? encodeGeohash(latitude, longitude) : null,
    });
  }
}
