import 'dart:math' as math;

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

bool isValidCoordinate(double latitude, double longitude) {
  return latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      latitude.isFinite &&
      longitude.isFinite;
}

double coarsenLatitude(double value) => (value * 1000).roundToDouble() / 1000;

double coarsenLongitude(double value) => (value * 1000).roundToDouble() / 1000;

String encodeGeohash(double latitude, double longitude, [int precision = 5]) {
  var latMin = -90.0;
  var latMax = 90.0;
  var lonMin = -180.0;
  var lonMax = 180.0;
  var even = true;
  var bits = 0;
  var hash = StringBuffer();
  var value = 0;

  while (hash.length < precision) {
    if (even) {
      final mid = (lonMin + lonMax) / 2;
      if (longitude >= mid) {
        value = (value << 1) | 1;
        lonMin = mid;
      } else {
        value <<= 1;
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        value = (value << 1) | 1;
        latMin = mid;
      } else {
        value <<= 1;
        latMax = mid;
      }
    }
    even = !even;
    bits++;
    if (bits == 5) {
      hash.write(_base32[value]);
      bits = 0;
      value = 0;
    }
  }

  return hash.toString();
}

({String lower, String upper}) geohashBounds(
  double latitude,
  double longitude,
  double radiusMeters, {
  int precision = 5,
}) {
  final latitudeDelta = radiusMeters / 111320;
  final longitudeScale = math.cos(latitude * math.pi / 180).abs();
  final longitudeDelta =
      radiusMeters / (111320 * longitudeScale.clamp(0.01, 1));
  final minLatitude = latitude - latitudeDelta;
  final maxLatitude = latitude + latitudeDelta;
  final minLongitude = longitude - longitudeDelta;
  final maxLongitude = longitude + longitudeDelta;

  return (
    lower: encodeGeohash(minLatitude, minLongitude, precision),
    upper: encodeGeohash(maxLatitude, maxLongitude, precision),
  );
}

double distanceMeters(
  double startLatitude,
  double startLongitude,
  double endLatitude,
  double endLongitude,
) {
  const earthRadius = 6371000.0;
  final latitudeDelta = _radians(endLatitude - startLatitude);
  final longitudeDelta = _radians(endLongitude - startLongitude);
  final startLatitudeRadians = _radians(startLatitude);
  final endLatitudeRadians = _radians(endLatitude);
  final value = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(startLatitudeRadians) *
          math.cos(endLatitudeRadians) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
}

double _radians(double degrees) => degrees * math.pi / 180;
