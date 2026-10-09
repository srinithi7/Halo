import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/geo.dart';

/// A verified (or community-listed) place people can go to for help.
enum SafeSpotCategory {
  policeStation,
  hospital,
  pharmacy,
  cafe,
  shop,
  library,
  communityCentre,
  transitStop,
  other;

  static SafeSpotCategory fromValue(String? value) {
    return SafeSpotCategory.values.firstWhere(
      (category) => category.name == value,
      orElse: () => SafeSpotCategory.other,
    );
  }

  String get label {
    switch (this) {
      case SafeSpotCategory.policeStation:
        return 'Police station';
      case SafeSpotCategory.hospital:
        return 'Hospital / clinic';
      case SafeSpotCategory.pharmacy:
        return 'Pharmacy';
      case SafeSpotCategory.cafe:
        return 'Cafe / restaurant';
      case SafeSpotCategory.shop:
        return 'Shop';
      case SafeSpotCategory.library:
        return 'Library';
      case SafeSpotCategory.communityCentre:
        return 'Community centre';
      case SafeSpotCategory.transitStop:
        return 'Transit stop';
      case SafeSpotCategory.other:
        return 'Other';
    }
  }
}

/// Where a listing came from. [discovered] entries were generated from
/// OpenStreetMap rather than typed by a person, and the UI says so — a
/// machine-generated place must never masquerade as a human-verified refuge.
enum SafeSpotSource {
  community,
  discovered,
  official;

  static SafeSpotSource fromValue(String? value) {
    return SafeSpotSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => SafeSpotSource.community,
    );
  }

  String get label {
    switch (this) {
      case SafeSpotSource.community:
        return 'Added by the community';
      case SafeSpotSource.discovered:
        return 'Auto-discovered from OpenStreetMap';
      case SafeSpotSource.official:
        return 'Official listing';
    }
  }
}

/// A SafeWalk "safe spot": a named place, with a location, that anyone can
/// head to when they need to feel safe.
///
/// Verification is deliberately modelled as a *claim with an expiry*, not a
/// boolean: a spot stops being presented as verified once [verifiedUntil]
/// passes, rather than being permanently promoted by whoever added it.
class SafeSpot {
  SafeSpot({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.description,
    this.address,
    this.openHours,
    this.verifiedBy,
    this.verifiedUntil,
    this.source = SafeSpotSource.community,
    this.addedBy,
    this.vouches = 0,
    this.geohashPrefix,
  });

  final String id;
  final String name;
  final SafeSpotCategory category;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String? description;
  final String? address;
  final String? openHours;
  final String? verifiedBy;
  final DateTime? verifiedUntil;
  final SafeSpotSource source;

  /// Uid of the person who added the spot. Kept separate from
  /// [verifiedBy] so adding a place and vouching for a place stay distinct
  /// acts, and so a machine-discovered spot never has an author.
  final String? addedBy;
  final int vouches;
  final String? geohashPrefix;

  String get categoryLabel => category.label;
  String get sourceLabel => source.label;

  bool get isDiscovered => source == SafeSpotSource.discovered;

  /// A spot is only presented as verified while its verification window is
  /// still open — an expired one degrades to a plain community listing.
  bool isVerifiedAt(DateTime now) {
    final verifier = verifiedBy;
    if (verifier == null || verifier.isEmpty) return false;
    final until = verifiedUntil;
    return until == null || until.isAfter(now);
  }

  factory SafeSpot.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final location = data['location'] as GeoPoint?;
    final createdAt = data['createdAt'];
    final verifiedUntil = data['verifiedUntil'];
    final geohash = data['geohashPrefix'] as String?;

    return SafeSpot(
      id: doc.id,
      name: data['name'] as String? ?? 'Safe spot',
      category: SafeSpotCategory.fromValue(data['category'] as String?),
      latitude: location?.latitude ?? 0,
      longitude: location?.longitude ?? 0,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      description: data['description'] as String?,
      address: data['address'] as String?,
      openHours: data['openHours'] as String?,
      verifiedBy: data['verifiedBy'] as String?,
      verifiedUntil: verifiedUntil is Timestamp ? verifiedUntil.toDate() : null,
      source: SafeSpotSource.fromValue(data['source'] as String?),
      addedBy: data['addedBy'] as String?,
      vouches: (data['vouches'] as num?)?.toInt() ?? 0,
      geohashPrefix: geohash ??
          (location == null
              ? null
              : encodeGeohash(location.latitude, location.longitude)),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'category': category.name,
      'location': GeoPoint(latitude, longitude),
      'createdAt': Timestamp.fromDate(createdAt),
      'description': description,
      'address': address,
      'openHours': openHours,
      'verifiedBy': verifiedBy,
      'verifiedUntil':
          verifiedUntil == null ? null : Timestamp.fromDate(verifiedUntil!),
      'source': source.name,
      'addedBy': addedBy,
      'vouches': vouches,
      'geohashPrefix': geohashPrefix ?? encodeGeohash(latitude, longitude),
    };
  }
}
