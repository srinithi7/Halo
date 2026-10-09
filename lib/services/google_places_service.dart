import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

/// Optional Google Places text search, used to enrich place search with
/// business hours, ratings and wheelchair access that OSM does not carry.
///
/// It is a **strictly optional enhancement**. [isConfigured] is false unless a
/// key is supplied at build time, and every caller must degrade gracefully:
/// SafeWalk is fully usable with no Google key at all. Nothing here is on the
/// critical path for reporting an incident, locating a HALO, or finding a
/// safe spot.
class GooglePlacesService {
  GooglePlacesService({http.Client? client})
      : _client = client ?? http.Client();

  static const _configuredKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
  );

  static const _timeout = Duration(seconds: 10);

  /// Supply with:
  /// `flutter run --dart-define=GOOGLE_PLACES_API_KEY=...`
  ///
  /// The key is a build-time constant, so it ships in the binary. That is
  /// acceptable only for a key restricted by Android app signature and
  /// restricted to the Places API — which is the only way this should ever
  /// be deployed. An unrestricted key here would be an abuse liability.
  final http.Client _client;

  bool get isConfigured => _configuredKey.isNotEmpty;

  /// Why Places is unavailable, for display. Never invent a reason.
  String get unavailableReason =>
      'Google Places needs a build-time API key. SafeWalk works without it - '
      'search falls back to OpenStreetMap and community places.';

  /// Text search biased toward [center].
  Future<List<GooglePlaceResult>> search(
    String query, {
    ll.LatLng? center,
  }) async {
    if (!isConfigured || query.trim().isEmpty) return const [];
    final url = Uri.https('places.googleapis.com', '/v1/places:searchText', {
      'key': _configuredKey,
      if (center != null) 'locationBias': _bias(center),
    });

    final response = await _client
        .post(
          url,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'textQuery': query.trim(),
            'pageSize': 15,
            'languageCode': 'en',
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw PlacesException('Places returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final places = decoded['places'];
    if (places is! List) return const [];
    return [
      for (final place in places)
        if (place is Map<String, dynamic>) GooglePlaceResult.tryParse(place),
    ].whereType<GooglePlaceResult>().toList();
  }

  static String _bias(ll.LatLng center) {
    // Places expects "circle:radius@lat,lng" with metres.
    return 'circle:30000@${center.latitude},${center.longitude}';
  }

  void dispose() => _client.close();
}

class PlacesException implements Exception {
  PlacesException(this.message);
  final String message;

  @override
  String toString() => 'PlacesException: $message';
}

class GooglePlaceResult {
  const GooglePlaceResult({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.rating,
    this.isOpenNow,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final double? rating;
  final bool? isOpenNow;

  static GooglePlaceResult? tryParse(Map<String, dynamic> json) {
    final location = json['location'];
    if (location is! Map) return null;
    final lat = location['latitude'];
    final lon = location['longitude'];
    if (lat is! num || lon is! num) return null;
    final displayName = json['displayName'];
    return GooglePlaceResult(
      id: json['id'] as String? ?? '',
      name: displayName is Map && displayName['text'] is String
          ? displayName['text'] as String
          : 'Place',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      address: json['formattedAddress'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      isOpenNow: (json['currentOpeningHours'] as Map?)?['openNow'] as bool?,
    );
  }
}
