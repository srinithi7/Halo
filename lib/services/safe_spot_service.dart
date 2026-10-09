import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/community.dart';
import '../models/safe_spot.dart';
import '../utils/geo.dart';
import 'overpass_service.dart';

/// Persistence + discovery for Safe Spots.
class SafeSpotService {
  SafeSpotService({OverpassService? overpass})
      : _overpass = overpass ?? OverpassService();

  static const collectionName = 'safeSpots';
  static const _geohashPrecision = 5;
  static const _maxDiscoveryResults = 60;

  final OverpassService _overpass;

  /// Resolved lazily so the pure mapping/query helpers stay unit-testable
  /// without a Firebase app being initialised.
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  /// Live Safe Spots inside the currently viewed area.
  static Stream<List<SafeSpot>> watchSafeSpots({
    required ll.LatLng center,
    double radiusMeters = 2000,
  }) {
    if (kDebugMode) {
      return Stream<List<SafeSpot>>.multi((controller) {
        controller.add(demoSafeSpots(center: center));
        controller.onCancel = () {};
      });
    }
    final bounds = geohashBounds(
      center.latitude,
      center.longitude,
      radiusMeters,
      precision: _geohashPrecision,
    );
    return FirebaseFirestore.instance
        .collection(collectionName)
        .where('geohashPrefix', isGreaterThanOrEqualTo: bounds.lower)
        .where('geohashPrefix', isLessThan: bounds.upper)
        .limit(200)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                if (doc.data()['location'] case final GeoPoint point)
                  if (distanceMeters(
                        center.latitude,
                        center.longitude,
                        point.latitude,
                        point.longitude,
                      ) <=
                      radiusMeters)
                    SafeSpot.fromFirestore(doc),
            ]);
  }

  /// Communities that have declared a geographic footprint, scoped to the
  /// viewed area. Name-only communities are intentionally excluded — they
  /// have no location to match against.
  static Stream<List<Community>> watchCommunitiesWithArea({
    required ll.LatLng center,
    double radiusMeters = 5000,
  }) {
    if (kDebugMode) {
      return Stream<List<Community>>.multi((controller) {
        controller.add(const <Community>[]);
        controller.onCancel = () {};
      });
    }
    final bounds = geohashBounds(
      center.latitude,
      center.longitude,
      radiusMeters,
      precision: _geohashPrecision,
    );
    return FirebaseFirestore.instance
        .collection('communities')
        .where('geohashPrefix', isGreaterThanOrEqualTo: bounds.lower)
        .where('geohashPrefix', isLessThan: bounds.upper)
        .limit(100)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                if (doc.data()['center'] case final GeoPoint point)
                  if (distanceMeters(
                        center.latitude,
                        center.longitude,
                        point.latitude,
                        point.longitude,
                      ) <=
                      radiusMeters)
                    Community.fromFirestore(doc),
            ]);
  }

  /// Overpass passthrough, exposed so discovery UI can search the live
  /// amenity data directly.
  Future<List<OverpassElement>> query(String qlBody) => _overpass.query(qlBody);

  /// Adds a place someone nominates as safe.
  Future<String> createSafeSpot({
    required String name,
    required SafeSpotCategory category,
    required double latitude,
    required double longitude,
    String? description,
    String? address,
    String? openHours,
    SafeSpotSource source = SafeSpotSource.community,
    String? addedBy,
  }) async {
    final spot = SafeSpot(
      id: '',
      name: name.trim(),
      category: category,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
      description: description?.trim(),
      address: address?.trim(),
      openHours: openHours?.trim(),
      source: source,
      addedBy: addedBy ?? FirebaseAuth.instance.currentUser?.uid,
      geohashPrefix: encodeGeohash(
        latitude,
        longitude,
        _geohashPrecision,
      ),
    );
    final doc = await _collection.add(spot.toFirestore());
    return doc.id;
  }

  /// Records a community vouch: one more person says this place is real and
  /// worth going to.
  ///
  /// This is deliberately *not* verification. A vouch is a crowd signal, it
  /// is reversible, and it does not mint the green "verified" badge — that is
  /// reserved for a trusted process, so the count can never be inflated into
  /// an authority claim. Each user may only vouch once, enforced by the
  /// `vouches` increment rule on the server.
  Future<void> vouchSafeSpot(String id, {int currentVouches = 0}) async {
    await _collection.doc(id).update({
      'vouches': currentVouches + 1,
    });
  }

  /// Corrects a stale or moved entry.
  Future<void> updateSafeSpot(
    String id, {
    String? name,
    SafeSpotCategory? category,
    String? description,
    String? address,
    String? openHours,
  }) async {
    await _collection.doc(id).update({
      if (name != null) 'name': name.trim(),
      if (category != null) 'category': category.name,
      if (description != null) 'description': description.trim(),
      if (address != null) 'address': address.trim(),
      if (openHours != null) 'openHours': openHours.trim(),
    });
  }

  /// Removes a listing entirely.
  Future<void> deleteSafeSpot(String id) => _collection.doc(id).delete();

  /// Turns raw Overpass elements into Safe Spots.
  ///
  /// Auto-generation is here so a brand-new city is never an empty grey map:
  /// the places that matter for safety (police, clinics, pharmacies, staffed
  /// shops) exist in OpenStreetMap long before anyone nominates them. They are
  /// always written as [SafeSpotSource.discovered], which the UI presents as
  /// "unverified" — auto-generated is not the same as safe.
  List<SafeSpot> toSafeSpots(
    List<OverpassElement> elements, {
    required ll.LatLng center,
    double radiusMeters = 2000,
  }) {
    final spots = <SafeSpot>[];
    final seen = <String>{};
    for (final element in elements) {
      if (!isValidCoordinate(element.latitude, element.longitude)) continue;
      if (distanceMeters(
            center.latitude,
            center.longitude,
            element.latitude,
            element.longitude,
          ) >
          radiusMeters) {
        continue;
      }
      final category = _categoryFor(element);
      if (category == null) continue;
      // OSM frequently maps the same building several times (node + ways).
      // Collapse on name so one mall does not produce six pins.
      final key = '${element.name ?? ''}|${category.name}|'
          '${element.latitude.toStringAsFixed(4)}';
      if (!seen.add(key)) continue;
      spots.add(
        SafeSpot(
          id: 'osm:${element.id}',
          name: element.name?.trim().isNotEmpty == true
              ? element.name!.trim()
              : category.label,
          category: category,
          latitude: element.latitude,
          longitude: element.longitude,
          createdAt: DateTime.now(),
          openHours: element.openingHours,
          description: element.amenity == 'police'
              ? 'Police facility from OpenStreetMap. Not yet verified.'
              : null,
          source: SafeSpotSource.discovered,
          geohashPrefix: encodeGeohash(
            element.latitude,
            element.longitude,
            _geohashPrecision,
          ),
        ),
      );
      if (spots.length >= _maxDiscoveryResults) break;
    }
    spots.sort(
        (a, b) => a.distanceFrom(center).compareTo(b.distanceFrom(center)));
    return spots;
  }

  SafeSpotCategory? _categoryFor(OverpassElement element) {
    switch (element.amenity) {
      case 'police':
        return SafeSpotCategory.policeStation;
      case 'hospital':
      case 'clinic':
      case 'doctors':
        return SafeSpotCategory.hospital;
      case 'pharmacy':
        return SafeSpotCategory.pharmacy;
      case 'cafe':
      case 'restaurant':
      case 'fast_food':
        return SafeSpotCategory.cafe;
      case 'library':
        return SafeSpotCategory.library;
      case 'community_centre':
      case 'townhall':
        return SafeSpotCategory.communityCentre;
      case 'bus_station':
      case 'ferry_terminal':
        return SafeSpotCategory.transitStop;
      case 'atm':
        return SafeSpotCategory.other;
    }
    if (element.shop != null) return SafeSpotCategory.shop;
    if (element.highway == 'bus_stop') return SafeSpotCategory.transitStop;
    return null;
  }

  /// Overpass QL for safety-relevant amenities in an area.
  static String discoveryQuery(ll.LatLng center, double radiusMeters) {
    final south = center.latitude - radiusMeters / 111320;
    final west = center.longitude - radiusMeters / 111320;
    final north = center.latitude + radiusMeters / 111320;
    final east = center.longitude + radiusMeters / 111320;
    final box = '$south,$west,$north,$east';
    // Overpass QL, not Dart. The `\$` is a QL regex end-anchor, so it has to
    // be escaped to survive Dart string interpolation; everything else in
    // this block is literal QL.
    return '''
[out:json][timeout:20];
(
  nwr["amenity"~"^(police|hospital|clinic|doctors|pharmacy|cafe|restaurant|fast_food|library|community_centre|townhall|bus_station|ferry_terminal)\$"]($box);
  nwr["shop"]($box);
  nwr["highway"="bus_stop"]($box);
);
out center $_maxDiscoveryResults;
''';
  }

  /// Debug Safe Spots so the map is demonstrable with no network and no data.
  static List<SafeSpot> demoSafeSpots({required ll.LatLng center}) {
    final now = DateTime.now();
    SafeSpot spot(
      String id,
      String name,
      SafeSpotCategory category,
      double dLat,
      double dLon, {
      String? description,
      String? openHours,
      bool verified = false,
    }) {
      return SafeSpot(
        id: 'demo-$id',
        name: name,
        category: category,
        latitude: center.latitude + dLat,
        longitude: center.longitude + dLon,
        createdAt: now.subtract(const Duration(days: 21)),
        description: description,
        openHours: openHours,
        source: verified ? SafeSpotSource.official : SafeSpotSource.community,
        verifiedBy: verified ? 'demo-verifier' : null,
        verifiedUntil: verified ? now.add(const Duration(days: 90)) : null,
      );
    }

    return [
      spot(
        'police',
        'Nearby police station',
        SafeSpotCategory.policeStation,
        0.0035,
        -0.0021,
        description: 'Staffed 24x7.',
        verified: true,
      ),
      spot(
        'hospital',
        'District hospital',
        SafeSpotCategory.hospital,
        -0.0028,
        0.0041,
        description: 'Emergency department open at night.',
        verified: true,
      ),
      spot(
        'cafe',
        'Late-night cafe',
        SafeSpotCategory.cafe,
        0.0012,
        0.0026,
        description: 'Well-lit, busy until 1am. Community listed.',
        openHours: '08:00 - 01:00',
      ),
      spot(
        'pharmacy',
        '24hr pharmacy',
        SafeSpotCategory.pharmacy,
        -0.0014,
        -0.0037,
        openHours: '24 hours',
      ),
      spot(
        'library',
        'Public library',
        SafeSpotCategory.library,
        0.0052,
        0.0018,
        description: 'Open during the day.',
        openHours: '09:00 - 20:00',
      ),
    ];
  }

  void dispose() => _overpass.dispose();
}

extension on SafeSpot {
  /// Great-circle distance from the map centre, used only to order results.
  double distanceFrom(ll.LatLng other) =>
      distanceMeters(other.latitude, other.longitude, latitude, longitude);
}
