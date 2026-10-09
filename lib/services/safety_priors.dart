import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// City-level safety priors, shaped like NCRB *Crime in India* aggregates.
///
/// ## Provenance — read this before using the numbers
///
/// NCRB publishes annual national/state/city aggregate tables (as
/// "Crimes against women", `Crimes by cause`, district crime rates). It does
/// **not** publish a free real-time per-neighbourhood safety feed, and
/// district-level tables are far too coarse to justify a per-street risk
/// number in a consumer app.
///
/// So this file ships **illustrative priors, explicitly flagged as such**
/// ([SafetyPrior.illustrative] is true), used for one narrow purpose only:
/// giving a cold-start area *relative* weight in the baseline picture. They
/// are not NCRB figures, they are not asserted to be accurate, and the UI
/// must show them as a coarse city-level prior rather than a local fact.
///
/// [SafetyPriorSource] is an interface precisely so a licensed or official
/// feed can replace this without touching any calling code.
class SafetyPrior {
  const SafetyPrior({
    required this.city,
    required this.center,
    required this.radiusKm,
    required this.relativeNightRisk,
    required this.relativeSoloRisk,
    required this.relativeReportingIndex,
    this.illustrative = true,
    this.sourceLabel = 'Illustrative city-level prior (not official NCRB data)',
    this.sampledYear,
  });

  final String city;
  final ll.LatLng center;
  final double radiusKm;

  /// 0..1, relative to other cities in this table. Higher means "treat
  /// unconfirmed areas in this city with more caution", not "this city is
  /// dangerous".
  final double relativeNightRisk;
  final double relativeSoloRisk;

  /// How likely people here are to report at all. A low reporting index is a
  /// warning that the absence of reports means little.
  final double relativeReportingIndex;

  /// True while these numbers are placeholders rather than sourced figures.
  final bool illustrative;
  final String sourceLabel;
  final int? sampledYear;

  bool appliesTo(ll.LatLng point) =>
      distanceKm(
          center.latitude, center.longitude, point.latitude, point.longitude) <=
      radiusKm;

  static double distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0088;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double degrees) => degrees * math.pi / 180;
}

/// Pluggable source of priors, so a real data feed can replace the default
/// illustrative table without changing any caller.
abstract class SafetyPriorSource {
  /// The prior covering [point], or null if the provider has no coverage.
  SafetyPrior? priorFor(ll.LatLng point);

  /// The disclaimer that must be displayed alongside any use of these values.
  String get disclaimer;
}

/// The default, explicitly illustrative prior table.
///
/// Every entry is a placeholder with a coarse city centroid. Replace this
/// class — do not edit the numbers to look authoritative.
class IllustrativeSafetyPriorSource implements SafetyPriorSource {
  const IllustrativeSafetyPriorSource();

  static const List<SafetyPrior> table = [
    SafetyPrior(
      city: 'Bengaluru',
      center: ll.LatLng(12.9716, 77.5946),
      radiusKm: 40,
      relativeNightRisk: 0.52,
      relativeSoloRisk: 0.44,
      relativeReportingIndex: 0.38,
    ),
    SafetyPrior(
      city: 'Mumbai',
      center: ll.LatLng(19.0760, 72.8777),
      radiusKm: 35,
      relativeNightRisk: 0.61,
      relativeSoloRisk: 0.55,
      relativeReportingIndex: 0.41,
    ),
    SafetyPrior(
      city: 'Delhi',
      center: ll.LatLng(28.6139, 77.2090),
      radiusKm: 45,
      relativeNightRisk: 0.78,
      relativeSoloRisk: 0.66,
      relativeReportingIndex: 0.29,
    ),
    SafetyPrior(
      city: 'Hyderabad',
      center: ll.LatLng(17.3850, 78.4867),
      radiusKm: 35,
      relativeNightRisk: 0.55,
      relativeSoloRisk: 0.47,
      relativeReportingIndex: 0.33,
    ),
    SafetyPrior(
      city: 'Chennai',
      center: ll.LatLng(13.0827, 80.2707),
      radiusKm: 30,
      relativeNightRisk: 0.48,
      relativeSoloRisk: 0.42,
      relativeReportingIndex: 0.35,
    ),
    SafetyPrior(
      city: 'Kolkata',
      center: ll.LatLng(22.5726, 88.3639),
      radiusKm: 30,
      relativeNightRisk: 0.57,
      relativeSoloRisk: 0.50,
      relativeReportingIndex: 0.31,
    ),
    SafetyPrior(
      city: 'Pune',
      center: ll.LatLng(18.5204, 73.8567),
      radiusKm: 30,
      relativeNightRisk: 0.47,
      relativeSoloRisk: 0.43,
      relativeReportingIndex: 0.36,
    ),
    SafetyPrior(
      city: 'Hyderabad (Secunderabad)',
      center: ll.LatLng(17.4399, 78.4985),
      radiusKm: 20,
      relativeNightRisk: 0.55,
      relativeSoloRisk: 0.47,
      relativeReportingIndex: 0.33,
    ),
  ];

  /// The nearest covering prior, if the point falls inside any coverage disc.
  /// Areas outside every disc get no prior at all rather than a fabricated
  /// fallback — "we have no data here" is a valid answer.
  @override
  SafetyPrior? priorFor(ll.LatLng point) {
    SafetyPrior? best;
    var bestDistance = double.infinity;
    for (final prior in table) {
      if (!prior.appliesTo(point)) continue;
      final distance = SafetyPrior.distanceKm(
        prior.center.latitude,
        prior.center.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < bestDistance) {
        best = prior;
        bestDistance = distance;
      }
    }
    return best;
  }

  @override
  String get disclaimer =>
      'City-level prior only. These are placeholder values, not official '
      'NCRB figures, and they describe a whole metro area - not your street. '
      'Do not use them to judge a specific place.';
}
