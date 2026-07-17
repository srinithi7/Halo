import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/incident.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

const _fallbackCenter = ll.LatLng(0, 0);

Color _colorForType(IncidentType type) {
  switch (type) {
    case IncidentType.harassment:
      return colorRed;
    case IncidentType.poorLighting:
      return const Color(0xFFE0A93D);
    case IncidentType.isolated:
      return colorBlue;
    case IncidentType.drunkCrowd:
      return accentPurple;
    case IncidentType.other:
      return textMuted;
  }
}

IconData _iconForType(IncidentType type) {
  switch (type) {
    case IncidentType.harassment:
      return LucideIcons.shieldAlert;
    case IncidentType.poorLighting:
      return LucideIcons.lightbulbOff;
    case IncidentType.isolated:
      return LucideIcons.userX;
    case IncidentType.drunkCrowd:
      return LucideIcons.users;
    case IncidentType.other:
      return LucideIcons.circleAlert;
  }
}

String _labelForType(IncidentType type) {
  switch (type) {
    case IncidentType.harassment:
      return 'Harassment';
    case IncidentType.poorLighting:
      return 'Poor lighting';
    case IncidentType.isolated:
      return 'Isolated area';
    case IncidentType.drunkCrowd:
      return 'Drunk crowd';
    case IncidentType.other:
      return 'Other';
  }
}

/// Community safety map. Reports are fully anonymous — no identity of any
/// kind is attached to an incident, unlike recognition posts.
class SafeWalkScreen extends StatefulWidget {
  const SafeWalkScreen({super.key});

  @override
  State<SafeWalkScreen> createState() => _SafeWalkScreenState();
}

class _SafeWalkScreenState extends State<SafeWalkScreen> {
  final _mapController = MapController();
  ll.LatLng _center = _fallbackCenter;
  bool _locating = true;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _incidentsStream;

  @override
  void initState() {
    super.initState();
    _incidentsStream = FirebaseFirestore.instance
        .collection('incidents')
        .orderBy('reportedAt', descending: true)
        .snapshots();
    _centerOnCurrentLocation();
  }

  Future<void> _centerOnCurrentLocation() async {
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
      setState(() => _center = ll.LatLng(position.latitude, position.longitude));
      _mapController.move(_center, 15);
    } catch (_) {
      // No usable location — map just stays at the fallback center.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _reportAt(ll.LatLng point) async {
    final type = await showModalBottomSheet<IncidentType>(
      context: context,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (_) => const _ReportSheet(),
    );

    if (type == null || !mounted) return;

    try {
      final now = DateTime.now();
      final incident = Incident(
        id: '',
        latitude: point.latitude,
        longitude: point.longitude,
        type: type,
        timeOfDay: timeOfDayLabel(now),
        reportedAt: now,
      );
      await FirebaseFirestore.instance.collection('incidents').add(incident.toFirestore());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted. Thank you for helping keep this area safe.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit report: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.mapPin, color: accentGold, size: 20),
            SizedBox(width: 8),
            Text('SafeWalk'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _incidentsStream,
        builder: (context, snapshot) {
          final incidents = (snapshot.data?.docs ?? [])
              .map((doc) => Incident.fromFirestore(doc))
              .toList();

          return Column(
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _center,
                        initialZoom: 13,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.halo.app',
                        ),
                        MarkerLayer(
                          markers: [
                            for (final incident in incidents)
                              Marker(
                                point: ll.LatLng(incident.latitude, incident.longitude),
                                width: 34,
                                height: 34,
                                child: Icon(
                                  _iconForType(incident.type),
                                  color: _colorForType(incident.type),
                                  size: 26,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (_locating)
                      const Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(child: CircularProgressIndicator(color: accentGold)),
                      ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: ElevatedButton.icon(
                        onPressed: () => _reportAt(_mapController.camera.center),
                        icon: const Icon(LucideIcons.mapPinPlus, size: 18),
                        label: const Text('Report this location'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(spacingPadding, spacingSmallGap, spacingPadding, 4),
                child: Row(
                  children: const [
                    Icon(LucideIcons.clock, size: 14, color: textMuted),
                    SizedBox(width: 6),
                    Text('Recent in your area', style: TextStyle(color: textMuted, fontSize: 13)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: incidents.isEmpty
                    ? const Center(
                        child: Text(
                          'No reports yet.',
                          style: TextStyle(color: textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: spacingPadding, vertical: 4),
                        itemCount: incidents.length,
                        itemBuilder: (context, index) {
                          final incident = incidents[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: spacingSmallGap),
                            child: ListTile(
                              leading: Icon(_iconForType(incident.type), color: _colorForType(incident.type)),
                              title: Text(
                                _labelForType(incident.type),
                                style: const TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${incident.timeOfDay} · ${relativeTime(incident.reportedAt)}',
                                style: const TextStyle(color: textMuted, fontSize: 12),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.mapPinPlus, color: accentGold, size: 18),
              SizedBox(width: 8),
              Text(
                'What did you notice here?',
                style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: spacingSmallGap,
            runSpacing: spacingSmallGap,
            children: [
              for (final type in IncidentType.values)
                ActionChip(
                  avatar: Icon(_iconForType(type), size: 16, color: _colorForType(type)),
                  label: Text(_labelForType(type)),
                  onPressed: () => Navigator.of(context).pop(type),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
