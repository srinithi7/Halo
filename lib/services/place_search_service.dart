import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

/// What a search hit represents, so the UI can pick the right icon.
enum PlaceResultKind { safeSpot, community, place }

class PlaceResult {
  const PlaceResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    required this.kind,
  });

  final String id;
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
  final PlaceResultKind kind;

  ll.LatLng get point => ll.LatLng(latitude, longitude);

  /// Coarse key used to drop duplicate OSM results that resolve to the same
  /// spot (Nominatim often returns the same POI under several names).
  String get dedupeKey =>
      '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
}

/// Place search for the SafeWalk map.
///
/// Results are merged from two sources: local objects the app already knows
/// about (safe spots, communities) and OpenStreetMap Nominatim, which is the
/// same data source as the map tiles. Nominatim failures are swallowed so the
/// search box still works offline — local hits are always usable.
class PlaceSearchService {
  PlaceSearchService._();

  static const _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'HALO/1.0 (community safety walk app)';
  static const _timeout = Duration(seconds: 6);

  static Future<List<PlaceResult>> search(
    String query, {
    List<PlaceResult> localResults = const [],
    ll.LatLng? bias,
    int limit = 8,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return localResults;

    final local = _rankLocal(localResults, term, limit);
    if (kDebugMode) {
      // Debug builds stay fully offline so a demo never depends on the
      // network; the local index above is the whole result set.
      return local;
    }

    final remote = await _searchNominatim(term, bias: bias, limit: limit);
    final seen = <String>{for (final result in local) result.dedupeKey};
    final merged = <PlaceResult>[...local];
    for (final result in remote) {
      if (seen.add(result.dedupeKey)) merged.add(result);
    }
    return merged;
  }

  static List<PlaceResult> _rankLocal(
    List<PlaceResult> localResults,
    String term,
    int limit,
  ) {
    final needle = term.toLowerCase();
    final scored = <(int, PlaceResult)>[];
    for (final result in localResults) {
      final title = result.title.toLowerCase();
      final subtitle = result.subtitle.toLowerCase();
      int score;
      if (title == needle) {
        score = 0;
      } else if (title.startsWith(needle)) {
        score = 1;
      } else if (title.contains(needle)) {
        score = 2;
      } else if (subtitle.contains(needle)) {
        score = 3;
      } else {
        continue;
      }
      scored.add((score, result));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return scored.take(limit).map((entry) => entry.$2).toList();
  }

  static Future<List<PlaceResult>> _searchNominatim(
    String term, {
    ll.LatLng? bias,
    int limit = 8,
  }) async {
    try {
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {
          'q': term,
          'format': 'jsonv2',
          'limit': '$limit',
          'addressdetails': '1',
          // Bias ordering toward the user's area without hard-bounding it,
          // so searching for a city name from anywhere still finds it.
          if (bias != null) ...{
            'viewbox': _viewboxFor(bias),
            'bounded': '0',
          },
        },
      );
      final response =
          await http.get(uri, headers: {'User-Agent': _userAgent}).timeout(
        _timeout,
      );
      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final results = <PlaceResult>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final latitude = double.tryParse('${entry['lat']}');
        final longitude = double.tryParse('${entry['lon']}');
        if (latitude == null || longitude == null) continue;
        final displayName = '${entry['display_name'] ?? ''}';
        final name = '${entry['name'] ?? ''}'.trim();
        results.add(
          PlaceResult(
            id: 'osm-${entry['place_id']}',
            title: name.isNotEmpty ? name : displayName,
            subtitle: _subtitleFor(displayName),
            latitude: latitude,
            longitude: longitude,
            kind: PlaceResultKind.place,
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// A ~55 km box around [center], in Nominatim's "left,top,right,bottom"
  /// (longitude, latitude) order.
  static String _viewboxFor(ll.LatLng center) {
    const span = 0.5;
    final left = (center.longitude - span).clamp(-180.0, 180.0);
    final right = (center.longitude + span).clamp(-180.0, 180.0);
    final top = (center.latitude + span).clamp(-90.0, 90.0);
    final bottom = (center.latitude - span).clamp(-90.0, 90.0);
    return '$left,$top,$right,$bottom';
  }

  /// Nominatim's `display_name` is "a, b, c, city, state, country". Drop the
  /// title when it repeats, and keep only the tail so the row stays readable.
  static String _subtitleFor(String displayName) {
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) return '';
    if (parts.length > 4) {
      return parts.sublist(parts.length - 4, parts.length).join(', ');
    }
    return parts.sublist(1).join(', ');
  }
}
