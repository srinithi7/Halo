import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

class UnseenHeroLocationPickerScreen extends StatefulWidget {
  const UnseenHeroLocationPickerScreen({super.key, this.initialPoint});

  final ll.LatLng? initialPoint;

  @override
  State<UnseenHeroLocationPickerScreen> createState() =>
      _UnseenHeroLocationPickerScreenState();
}

class _UnseenHeroLocationPickerScreenState
    extends State<UnseenHeroLocationPickerScreen> {
  static const _fallback = ll.LatLng(11.0168, 76.9558);

  final _mapController = MapController();
  late ll.LatLng _point;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint ?? _fallback;
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
      _mapController.move(point, 16);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not read your current location.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose an area'),
        actions: [
          IconButton(
            tooltip: 'Use current location',
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
              initialZoom: 16,
              onTap: (_, point) => setState(() => _point = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.halo.app',
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
                        color: accentGold,
                        boxShadow: [
                          BoxShadow(
                            color: accentGoldDim,
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
                  child: const Row(
                    children: [
                      Icon(
                        LucideIcons.shieldCheck,
                        color: colorGreen,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Choose a public area. HALO rounds the pin before storing it.',
                          style: TextStyle(color: textMuted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(_point),
                  icon: const Icon(LucideIcons.check, size: 18),
                  label: const Text('Use this area'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
