import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

import '../models/incident.dart';
import '../models/unseen_hero.dart';
import '../utils/geo.dart';

/// A density cluster drawn as a soft zone on the SafeWalk map.
///
/// Zones are derived, never stored: they are recomputed from whatever is
/// inside the current area filter, so a zone can never survive the reports
/// that produced it. [intensity] is normalised against the busiest cluster
/// in the same set, which is what drives colour and size.
class ZoneCluster {
  const ZoneCluster({
    required this.center,
    required this.radiusMeters,
    required this.count,
    required this.intensity,
    required this.latest,
  });

  final ll.LatLng center;
  final double radiusMeters;
  final int count;

  /// 0..1, relative to the busiest cluster in the set.
  final double intensity;
  final DateTime latest;

  /// Recent reports are the actionable ones, so they push a zone towards its
  /// maximum size. Without this a cluster of two-month-old reports would draw
  /// as loud as this morning's.
  double get freshness {
    final ageHours = DateTime.now().difference(latest).inMinutes / 60;
    if (ageHours <= 24) return 1;
    if (ageHours >= 24 * 30) return 0.25;
    return (1 - ((ageHours - 24) / (24 * 30 - 24)) * 0.75).clamp(0.25, 1);
  }

  double get weight => intensity * freshness;
}

/// Which window the heat layer is summarising.
enum HeatRange {
  last48Hours,
  last30Days,
  allHistory;

  Duration? get window {
    switch (this) {
      case HeatRange.last48Hours:
        return const Duration(hours: 48);
      case HeatRange.last30Days:
        return const Duration(days: 30);
      case HeatRange.allHistory:
        return null;
    }
  }

  String get label {
    switch (this) {
      case HeatRange.last48Hours:
        return '48h';
      case HeatRange.last30Days:
        return '30d';
      case HeatRange.allHistory:
        return 'All';
    }
  }
}

/// Groups nearby points into map zones by a fixed metric grid.
class SafetyZones {
  SafetyZones._();

  /// Buckets incidents into red risk zones.
  static List<ZoneCluster> incidentZones(
    List<Incident> incidents, {
    double cellMeters = 150,
    int maxZones = 12,
  }) {
    return _cluster(
      items: [
        for (final incident in incidents)
          if (isValidCoordinate(incident.latitude, incident.longitude))
            _ZonePoint(
              ll.LatLng(incident.latitude, incident.longitude),
              incident.reportedAt,
            ),
      ],
      cellMeters: cellMeters,
      maxZones: maxZones,
      baseRadiusMeters: cellMeters * 0.7,
      radiusPerReport: cellMeters * 0.45,
      maxRadiusMeters: cellMeters * 4.5,
    );
  }

  /// The heat layer: coarse cells over a time window, sized and coloured by
  /// how many reports fall inside them.
  ///
  /// Coarser than [incidentZones] on purpose — a heat layer is a density
  /// summary, so a tighter grid would just redraw the individual pins in a
  /// blur. [intensity] is the cell's share of the busiest cell, so a quiet
  /// street stays cool instead of being stretched to full red.
  static List<ZoneCluster> heatCells(
    List<Incident> incidents, {
    HeatRange range = HeatRange.allHistory,
    double cellMeters = 420,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    // A null window means "no cutoff at all". It must not collapse to
    // `reference - Duration.zero`, which would filter out every past report.
    final window = range.window;
    final cutoff = window == null ? null : reference.subtract(window);
    return _cluster(
      items: [
        for (final incident in incidents)
          if (isValidCoordinate(incident.latitude, incident.longitude) &&
              (cutoff == null || !incident.reportedAt.isBefore(cutoff)))
            _ZonePoint(
              ll.LatLng(incident.latitude, incident.longitude),
              incident.reportedAt,
            ),
      ],
      cellMeters: cellMeters,
      maxZones: 64,
      baseRadiusMeters: cellMeters * 0.55,
      radiusPerReport: cellMeters * 0.3,
      maxRadiusMeters: cellMeters * 2.4,
    );
  }

  /// Buckets opted-in Unseen Heroes into gold support-density zones.
  static List<ZoneCluster> heroZones(
    List<NearbyUnseenHero> heroes, {
    double cellMeters = 300,
    int maxZones = 8,
  }) {
    return _cluster(
      items: [
        for (final hero in heroes)
          if (isValidCoordinate(
            hero.presence.latitude,
            hero.presence.longitude,
          ))
            _ZonePoint(
              ll.LatLng(
                hero.presence.latitude,
                hero.presence.longitude,
              ),
              hero.presence.recognizedAt,
            ),
      ],
      cellMeters: cellMeters,
      maxZones: maxZones,
      baseRadiusMeters: cellMeters * 0.6,
      radiusPerReport: cellMeters * 0.3,
      maxRadiusMeters: cellMeters * 3,
    );
  }

  static List<ZoneCluster> _cluster({
    required List<_ZonePoint> items,
    required double cellMeters,
    required int maxZones,
    required double baseRadiusMeters,
    required double radiusPerReport,
    required double maxRadiusMeters,
  }) {
    if (items.isEmpty) return const [];

    final cellDegrees = cellMeters / 111320;
    final buckets = <String, List<_ZonePoint>>{};
    for (final point in items) {
      final row = (point.position.latitude / cellDegrees).round();
      final column = (point.position.longitude / cellDegrees).round();
      buckets.putIfAbsent('$row:$column', () => <_ZonePoint>[]).add(point);
    }

    final raw = buckets.values.map((points) {
      var latitude = 0.0;
      var longitude = 0.0;
      var latest = points.first.timestamp;
      for (final point in points) {
        latitude += point.position.latitude;
        longitude += point.position.longitude;
        if (point.timestamp.isAfter(latest)) latest = point.timestamp;
      }
      final count = points.length;
      return (
        count: count,
        latest: latest,
        center: ll.LatLng(
          latitude / count,
          longitude / count,
        ),
        radius: math.min(
          maxRadiusMeters,
          baseRadiusMeters + radiusPerReport * math.sqrt(count),
        ),
      );
    }).toList();

    raw.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return b.latest.compareTo(a.latest);
    });

    final top = raw.take(maxZones).toList();
    final maxCount = top.isEmpty ? 1 : top.first.count;
    return [
      for (final zone in top)
        ZoneCluster(
          center: zone.center,
          radiusMeters: zone.radius,
          count: zone.count,
          intensity: (zone.count / maxCount).clamp(0.0, 1.0),
          latest: zone.latest,
        ),
    ];
  }
}

class _ZonePoint {
  const _ZonePoint(this.position, this.timestamp);

  final ll.LatLng position;
  final DateTime timestamp;
}
