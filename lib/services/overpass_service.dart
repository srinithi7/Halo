import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/geo.dart';

/// Minimal Overpass API client used to enrich the map with data HALO does not
/// itself host: nearby amenities (which seed Safe Spots) and street-lighting
/// coverage (which feeds the darkness heuristic).
///
/// Every call is best-effort and failure-tolerant. Overpass is a free public
/// service: it rate-limits aggressively, goes down regularly, and must never
/// be allowed to block or break the safety map. Callers are expected to treat
/// an error as "we learned nothing", not as "the area is empty".
class OverpassService {
  OverpassService({http.Client? client}) : _client = client ?? http.Client();

  static const _defaultEndpoint = 'https://overpass-api.de/api/interpreter';
  static const _timeout = Duration(seconds: 12);

  final http.Client _client;
  DateTime? _lastRequestAt;
  static const _minInterval = Duration(seconds: 2);

  /// Overridable so tests and release builds can point at a mirror.
  static const endpointOverride = String.fromEnvironment('OVERPASS_ENDPOINT');

  String get endpoint =>
      endpointOverride.isNotEmpty ? endpointOverride : _defaultEndpoint;

  /// Serialises requests so a pan across the map cannot fire a burst that
  /// gets the whole client rate-limited.
  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final wait = _minInterval - DateTime.now().difference(last);
      if (wait.isNegative == false) await Future<void>.delayed(wait);
    }
    _lastRequestAt = DateTime.now();
  }

  Future<List<OverpassElement>> query(String qlBody) async {
    await _throttle();
    final response = await _client.post(
      Uri.parse(endpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'data': qlBody},
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw OverpassException('Overpass returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final elements = (decoded as Map<String, dynamic>)['elements'];
    if (elements is! List) return const [];
    return [
      for (final element in elements)
        if (element is Map<String, dynamic>)
          if (OverpassElement.tryParse(element) case final parsed?) parsed,
    ];
  }

  void dispose() => _client.close();
}

class OverpassException implements Exception {
  OverpassException(this.message);
  final String message;

  @override
  String toString() => 'OverpassException: $message';
}

/// A single Overpass result — either a node (point of interest) or a way
/// (a stretch of lit street).
class OverpassElement {
  const OverpassElement({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.tags,
    this.geometry = const [],
  });

  final String id;
  final double latitude;
  final double longitude;
  final Map<String, String> tags;

  /// Ordered node coordinates for a way, empty for a point feature.
  final List<({double lat, double lon})> geometry;

  String? get name => tags['name'];
  String? get amenity => tags['amenity'];
  String? get shop => tags['shop'];
  String? get highway => tags['highway'];
  String? get lit => tags['lit'];
  String? get openingHours => tags['opening_hours'];
  String? get operator => tags['operator'];
  String? get emergency => tags['emergency'];

  bool get isLit =>
      lit == 'yes' || lit == '1' || lit == 'true' || tags['lit'] == 'yes';

  /// Real length of a way, measured from its actual geometry. Using this
  /// rather than a bounding-box guess is what makes a lighting estimate
  /// defensible instead of decorative.
  double get lengthMeters {
    if (geometry.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < geometry.length; i++) {
      total += distanceMeters(
        geometry[i - 1].lat,
        geometry[i - 1].lon,
        geometry[i].lat,
        geometry[i].lon,
      );
    }
    return total;
  }

  /// The midpoint of a way, used as its representative point.
  ({double lat, double lon})? get midpoint {
    if (geometry.isEmpty) return null;
    return geometry[geometry.length ~/ 2];
  }

  static OverpassElement? tryParse(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final geometry = <({double lat, double lon})>[];
    final rawGeometry = json['geometry'];
    if (rawGeometry is List) {
      for (final point in rawGeometry) {
        if (point is Map && point['lat'] is num && point['lon'] is num) {
          geometry.add((
            lat: (point['lat'] as num).toDouble(),
            lon: (point['lon'] as num).toDouble(),
          ));
        }
      }
    }

    // Ways carry their position in `geometry`/`center`; nodes in `lat`/`lon`.
    double? lat = json['lat'] is num ? (json['lat'] as num).toDouble() : null;
    double? lon = json['lon'] is num ? (json['lon'] as num).toDouble() : null;
    if ((lat == null || lon == null) && geometry.isNotEmpty) {
      final mid = geometry[geometry.length ~/ 2];
      lat = mid.lat;
      lon = mid.lon;
    }
    if (lat == null || lon == null) return null;

    return OverpassElement(
      id: '${json['type'] ?? 'node'}/${json['id'] ?? ''}',
      latitude: lat,
      longitude: lon,
      geometry: geometry,
      tags: {
        if (rawTags is Map)
          for (final entry in rawTags.entries)
            if (entry.value != null) '${entry.key}': '${entry.value}',
      },
    );
  }
}
