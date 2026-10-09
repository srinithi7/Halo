import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

import 'overpass_service.dart';

/// How well lit an area is, inferred from OpenStreetMap street-lighting data.
///
/// This is an **estimate about infrastructure, not about safety.** It says
/// "there are fewer lamps mapped here", which is a real signal but an
/// incomplete one: unmapped lamps make a lit street look dark, and a bare
/// `lit=no` tag is often simply untagged rather than a survey finding. The
/// UI must present it with that caveat attached, and it must never be blended
/// into a claim about how dangerous a place is.
class LightingAssessment {
  const LightingAssessment({
    required this.score,
    required this.litRoadMeters,
    required this.totalRoadMeters,
    required this.lampCount,
    required this.areaSquareKm,
    this.sampledAt,
  });

  /// 0 (no mapped lighting) to 1 (thoroughly mapped lighting).
  final double score;

  /// Length of highway ways explicitly tagged `lit=yes`.
  final double litRoadMeters;

  /// Length of every highway way we saw, lit or not.
  final double totalRoadMeters;

  final int lampCount;
  final double areaSquareKm;

  /// When this assessment was sampled. Null means hand-constructed with no
  /// sample behind it, which the UI treats as 'age unknown'.
  final DateTime? sampledAt;

  bool get hasData => totalRoadMeters > 0 || lampCount > 0;

  double get litRatio =>
      totalRoadMeters <= 0 ? 0 : (litRoadMeters / totalRoadMeters).clamp(0, 1);

  double get lampsPerSquareKm =>
      areaSquareKm <= 0 ? 0 : lampCount / areaSquareKm;

  /// The headline band, kept coarse on purpose: a 0.42 vs 0.47 difference is
  /// not a difference anyone can act on.
  LightingBand get band {
    if (!hasData) return LightingBand.unknown;
    if (score >= 0.66) return LightingBand.wellLit;
    if (score >= 0.38) return LightingBand.partial;
    if (score > 0) return LightingBand.sparse;
    return LightingBand.unknown;
  }

  String get bandLabel {
    switch (band) {
      case LightingBand.wellLit:
        return 'Well lit on the map';
      case LightingBand.partial:
        return 'Partly lit on the map';
      case LightingBand.sparse:
        return 'Little lighting on the map';
      case LightingBand.unknown:
        return 'No lighting data for this area';
    }
  }

  /// The honest caveat, shown wherever the score is shown.
  static const caveat =
      'Estimated from OpenStreetMap lighting tags. Unmapped street lights '
      'are not counted, so a well-lit street can look dark here. This is not '
      'a measure of how safe a place is.';
}

enum LightingBand { wellLit, partial, sparse, unknown }

class LightingService {
  LightingService({OverpassService? overpass})
      : _overpass = overpass ?? OverpassService();

  final OverpassService _overpass;

  /// Fetches mapped lighting for an area.
  ///
  /// Returns `null` when Overpass is unreachable — the caller must show
  /// "we don't know", never a zero score, which would read as "pitch dark".
  Future<LightingAssessment?> assess({
    required ll.LatLng center,
    double radiusMeters = 1500,
  }) async {
    final elements = await _overpass.query(
      lightingQuery(center, radiusMeters),
    );
    if (elements.isEmpty) return null;

    var litMeters = 0.0;
    var totalMeters = 0.0;
    var lamps = 0;
    for (final element in elements) {
      if (element.highway == 'street_lamp' && element.amenity == null) {
        lamps++;
        continue;
      }
      if (element.highway == null) continue;
      final length = element.lengthMeters;
      if (length <= 0) continue;
      totalMeters += length;
      if (element.isLit) litMeters += length;
    }

    final areaSquareKm = _circleAreaSquareKm(radiusMeters);
    return LightingAssessment(
      score: _scoreFrom(litMeters, totalMeters, lamps, areaSquareKm),
      litRoadMeters: litMeters,
      totalRoadMeters: totalMeters,
      lampCount: lamps,
      areaSquareKm: areaSquareKm,
      sampledAt: DateTime.now(),
    );
  }

  /// Blends tagged lit-road ratio with mapped lamp density.
  ///
  /// The two are weighted because they fail differently: a city that tags its
  /// roads diligently but omits lamp nodes still has a usable lit ratio, and
  /// a city that maps lamps but never tags roads still has usable density.
  static double _scoreFrom(
    double litMeters,
    double totalMeters,
    int lamps,
    double areaSquareKm,
  ) {
    final litRatio =
        totalMeters <= 0 ? 0.0 : (litMeters / totalMeters).clamp(0.0, 1.0);
    // ~8 street lamps per km² is a well-lit urban residential density.
    final density =
        (areaSquareKm <= 0 ? 0.0 : lamps / areaSquareKm / 8.0).clamp(0.0, 1.0);
    final score = 0.7 * litRatio + 0.3 * density;
    return score.clamp(0.0, 1.0);
  }

  static double _circleAreaSquareKm(double radiusMeters) {
    const earthRadiusKm = 6371.0088;
    final r = radiusMeters / 1000 / earthRadiusKm;
    return 3.141592653589793 * r * r * 6371.0088 * 6371.0088;
  }

  /// Overpass QL for mapped street lighting in an area.
  static String lightingQuery(ll.LatLng center, double radiusMeters) {
    final box = bbox(center, radiusMeters);
    return '''
[out:json][timeout:25];
(
  way["highway"]["lit"]($box);
  node["highway"="street_lamp"]($box);
);
out geom tags;
''';
  }

  /// Shared bounding box string, clipped to sane latitudes so a wide radius
  /// near a pole does not produce an invalid Overpass query.
  static String bbox(ll.LatLng center, double radiusMeters) {
    final latDelta = radiusMeters / 111320;
    final south = (center.latitude - latDelta).clamp(-85.0, 85.0);
    final north = (center.latitude + latDelta).clamp(-85.0, 85.0);
    final lonScale =
        math.cos(center.latitude * math.pi / 180).abs().clamp(0.01, 1.0);
    final lonDelta = radiusMeters / (111320 * lonScale);
    final west = center.longitude - lonDelta;
    final east = center.longitude + lonDelta;
    return '$south,$west,$north,$east';
  }

  void dispose() => _overpass.dispose();
}
