import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// A community's map footprint: a centre plus a coverage radius.
class CommunityArea {
  const CommunityArea({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final double latitude;
  final double longitude;
  final double radiusMeters;
}

/// Picks the circle a community covers, and the radius around it.
///
/// The centre is a coarse neighbourhood anchor chosen deliberately by the
/// community, never a user's live position — using your current location here
/// would quietly publish it, so the button only ever *starts* the picker near
/// you and the community still has to be centred and sized by hand.
class CommunityAreaPickerScreen extends StatefulWidget {
  const CommunityAreaPickerScreen({super.key, this.initialArea});

  final CommunityArea? initialArea;

  @override
  State<CommunityAreaPickerScreen> createState() =>
      _CommunityAreaPickerScreenState();
}

class _CommunityAreaPickerScreenState extends State<CommunityAreaPickerScreen> {
  static const _fallback = ll.LatLng(11.0168, 76.9558);
  static const _minRadius = 200.0;
  static const _maxRadius = 20000.0;

  final _mapController = MapController();
  late ll.LatLng _point;
  late double _radius;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialArea;
    _point = initial == null
        ? _fallback
        : ll.LatLng(initial.latitude, initial.longitude);
    _radius = initial?.radiusMeters ?? 1200;
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final point = ll.LatLng(position.latitude, position.longitude);
      setState(() => _point = point);
      _mapController.move(point, 14);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read your current location.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _radiusLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community area'),
        actions: [
          IconButton(
            tooltip: 'Centre near me',
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentGold,
                    ),
                  )
                : const Icon(LucideIcons.locateFixed, color: accentGold),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _point,
              initialZoom: 13,
              onTap: (_, point) => setState(() => _point = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.halo.app',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _point,
                    radius: _radius,
                    useRadiusInMeter: true,
                    color: accentPurpleDim,
                    borderColor: accentPurple,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _point,
                    width: 48,
                    height: 48,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentPurple,
                        boxShadow: [
                          BoxShadow(
                            color: accentPurpleDim,
                            blurRadius: 16,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child:
                          Icon(LucideIcons.mapPin, color: bgPrimary, size: 26),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bgSurface2,
                    borderRadius: BorderRadius.circular(cardRadius),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.circleDot,
                            color: accentPurple,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Coverage radius',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _radiusLabel(_radius),
                            style: const TextStyle(
                              color: accentPurple,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: accentPurple,
                          inactiveTrackColor: bgSurface3,
                          thumbColor: accentPurple,
                        ),
                        child: Slider(
                          value: _radius.clamp(_minRadius, _maxRadius),
                          min: _minRadius,
                          max: _maxRadius,
                          onChanged: (value) => setState(() => _radius = value),
                        ),
                      ),
                      Text(
                        'Anyone in this circle can find the community on '
                        'SafeWalk. Keep it to a neighbourhood, not a whole city.',
                        style: TextStyle(
                          color: textMuted2,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, size: 18),
                        label: const Text('No area'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(
                          CommunityArea(
                            latitude: _point.latitude,
                            longitude: _point.longitude,
                            radiusMeters: _radius,
                          ),
                        ),
                        icon: const Icon(LucideIcons.check, size: 18),
                        label: const Text('Save area'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
