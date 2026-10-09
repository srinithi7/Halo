import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/incident.dart';
import '../utils/geo.dart';
import '../utils/reporter_pseudonym.dart';
import 'moderation_service.dart';

/// Location-scoped reads for SafeWalk incident reports.
///
/// Firestore cannot do a true radius query, so "reports near me" is a two
/// stage filter: a geohash prefix range turns the circle into a cheap
/// server-side bounding box, then [distanceMeters] applies the exact radius
/// to the (small) result set. This is the same approach used for Unseen
/// Heroes in `unseen_hero_service.dart`, so incidents and heroes are always
/// scoped consistently to the same area.
class IncidentService {
  IncidentService._();

  static const _incidents = 'incidents';
  static const defaultLimit = 200;
  static const heatLimit = 500;

  /// The single write path for an incident report.
  ///
  /// Everything identity- and moderation-related happens here rather than at
  /// the call site, so there is exactly one place to audit for "what leaves
  /// the device when someone reports harassment".
  ///
  /// [anonymity] is honoured literally: a fully anonymous report writes a null
  /// handle and nothing else identifying, and a pseudonymous report without a
  /// usable handle is downgraded to anonymous rather than written half-formed.
  static Future<String> submitIncident({
    required double latitude,
    required double longitude,
    required IncidentType type,
    String? description,
    ReportAnonymity anonymity = ReportAnonymity.anonymous,
    String? userId,
    DateTime? reportedAt,
    String? locationSource,
  }) async {
    final handle = ReporterPseudonym.forUserId(userId);
    final effective = switch (anonymity) {
      ReportAnonymity.anonymous => ReportAnonymity.anonymous,
      ReportAnonymity.pseudonymous =>
        // No signed-in user, or an unusable handle: stay anonymous rather
        // than persist a report that claims to be linkable but is not.
        ReporterPseudonym.isWellFormed(handle)
            ? ReportAnonymity.pseudonymous
            : ReportAnonymity.anonymous,
    };

    final now = DateTime.now();
    final incident = Incident(
      id: '',
      latitude: latitude,
      longitude: longitude,
      type: type,
      timeOfDay: timeOfDayLabel(reportedAt ?? now),
      reportedAt: reportedAt ?? now,
      description: description,
      anonymity: effective,
      reporterHandle: effective == ReportAnonymity.pseudonymous ? handle : null,
      locationSource: locationSource,
    );

    // Layer 1 runs on-device against the real type and text, before the
    // write, so the verdict stored on the document is the one that was
    // actually applied to this report.
    final layer1 = ModerationService.evaluate(
      type: type,
      description: description,
    );

    return FirebaseFirestore.instance.collection(_incidents).add({
      ...incident.toFirestore(),
      ...ModerationService.initialStatus(
        verdict: layer1.verdict,
        flags: layer1.flags,
        evaluatedAt: now,
      ),
    }).then((doc) => doc.id);
  }

  /// Streams the reports within [radiusMeters] of [center], newest first.
  ///
  /// [since] is applied after the geohash range so a caller can ask for a
  /// window (for example the last 48 hours) without needing a second
  /// composite index on the hot path.
  static Stream<List<Incident>> watchIncidents({
    required ll.LatLng center,
    required double radiusMeters,
    DateTime? since,
    int limit = defaultLimit,
  }) async* {
    if (kDebugMode) {
      yield demoIncidents(
        center: center,
        radiusMeters: radiusMeters,
        since: since,
      );
      return;
    }

    final bounds = geohashBounds(
      center.latitude,
      center.longitude,
      radiusMeters,
    );

    final query = FirebaseFirestore.instance
        .collection(_incidents)
        .where('geohashPrefix', isGreaterThanOrEqualTo: bounds.lower)
        .where('geohashPrefix', isLessThanOrEqualTo: bounds.upper)
        .orderBy('reportedAt', descending: true)
        .limit(limit);

    await for (final snapshot in query.snapshots()) {
      yield filterToArea(
        snapshot.docs.map(Incident.fromFirestore),
        center: center,
        radiusMeters: radiusMeters,
        since: since,
      );
    }
  }

  /// Convenience wrapper used by the heat map: the same area, but a longer
  /// history and a bigger cap than the "recent" list.
  static Stream<List<Incident>> watchHistoricalIncidents({
    required ll.LatLng center,
    required double radiusMeters,
    int lookbackDays = 180,
  }) {
    return watchIncidents(
      center: center,
      radiusMeters: radiusMeters,
      since: DateTime.now().subtract(Duration(days: lookbackDays)),
      limit: heatLimit,
    );
  }

  /// Applies the exact circle and time window to an already-bounded set of
  /// reports, then sorts newest first.
  static List<Incident> filterToArea(
    Iterable<Incident> incidents, {
    required ll.LatLng center,
    required double radiusMeters,
    DateTime? since,
  }) {
    final kept = <Incident>[];
    for (final incident in incidents) {
      if (!isValidCoordinate(incident.latitude, incident.longitude)) continue;
      if (since != null && incident.reportedAt.isBefore(since)) continue;
      final distance = distanceMeters(
        center.latitude,
        center.longitude,
        incident.latitude,
        incident.longitude,
      );
      if (distance <= radiusMeters) kept.add(incident);
    }
    kept.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    return kept;
  }

  /// Deterministic offline sample data so the SafeWalk area view, the risk
  /// zones, the HALO density map and the heat layer all have something real
  /// to render before a backend is deployed. Debug builds only.
  static List<Incident> demoIncidents({
    required ll.LatLng center,
    required double radiusMeters,
    DateTime? since,
  }) {
    final random = math.Random(7);
    final now = DateTime.now();
    final incidents = <Incident>[];

    for (final cluster in _demoClusters(center)) {
      for (var index = 0; index < cluster.count; index++) {
        final angle = random.nextDouble() * math.pi * 2;
        final spread = math.sqrt(random.nextDouble()) * cluster.spreadMeters;
        final latitude =
            cluster.center.latitude + (spread * math.cos(angle)) / 111320;
        final longitude = cluster.center.longitude +
            (spread * math.sin(angle)) /
                (111320 * math.cos(cluster.center.latitude * math.pi / 180));
        final ageHours =
            (math.pow(random.nextDouble(), 2.2) * 24 * 90).toDouble();
        final reportedAt = now.subtract(
          Duration(minutes: (ageHours * 60).round()),
        );
        final type =
            IncidentType.values[random.nextInt(IncidentType.values.length)];
        incidents.add(
          Incident(
            id: 'demo-${cluster.name}-$index',
            latitude: latitude,
            longitude: longitude,
            type: type,
            timeOfDay: timeOfDayLabel(reportedAt),
            reportedAt: reportedAt,
            description: type == IncidentType.other
                ? 'Demo report: waterlogging after rain.'
                : null,
          ),
        );
      }
    }

    return filterToArea(
      incidents,
      center: center,
      radiusMeters: radiusMeters,
      since: since,
    );
  }

  static List<_DemoCluster> _demoClusters(ll.LatLng center) {
    return [
      _DemoCluster(
        name: 'market',
        center: ll.LatLng(center.latitude + 0.006, center.longitude - 0.006),
        spreadMeters: 420,
        count: 26,
      ),
      _DemoCluster(
        name: 'underpass',
        center: ll.LatLng(center.latitude - 0.008, center.longitude + 0.004),
        spreadMeters: 520,
        count: 17,
      ),
      _DemoCluster(
        name: 'bus-stop',
        center: ll.LatLng(center.latitude + 0.002, center.longitude + 0.011),
        spreadMeters: 380,
        count: 9,
      ),
      _DemoCluster(
        name: 'park',
        center: ll.LatLng(center.latitude - 0.013, center.longitude - 0.012),
        spreadMeters: 640,
        count: 4,
      ),
    ];
  }
}

class _DemoCluster {
  const _DemoCluster({
    required this.name,
    required this.center,
    required this.spreadMeters,
    required this.count,
  });

  final String name;
  final ll.LatLng center;
  final double spreadMeters;
  final int count;
}
