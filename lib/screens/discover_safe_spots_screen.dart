import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/safe_spot.dart';
import '../services/safe_spot_service.dart';
import '../theme/app_theme.dart';

/// Browse auto-discovered places near [center] and nominate one as a Safe
/// Spot.
///
/// Discovery exists so a new user in a new city sees somewhere to go rather
/// than an empty map, but nothing is saved until a human explicitly nominates
/// it — auto-generation seeds the *list*, never the database.
class DiscoverSafeSpotsScreen extends StatefulWidget {
  const DiscoverSafeSpotsScreen({
    super.key,
    required this.center,
    this.radiusMeters = 2000,
  });

  final ll.LatLng center;
  final double radiusMeters;

  @override
  State<DiscoverSafeSpotsScreen> createState() =>
      _DiscoverSafeSpotsScreenState();
}

class _DiscoverSafeSpotsScreenState extends State<DiscoverSafeSpotsScreen> {
  final _service = SafeSpotService();
  final _searchController = TextEditingController();

  List<SafeSpot> _results = const [];
  List<SafeSpot> _discovered = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_discover());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final elements = await _service.query(
        SafeSpotService.discoveryQuery(widget.center, widget.radiusMeters),
      );
      if (!mounted) return;
      setState(() {
        _discovered = _service.toSafeSpots(
          elements,
          center: widget.center,
          radiusMeters: widget.radiusMeters,
        );
        _loading = false;
        _applyFilter();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not reach the OpenStreetMap lookup service. Showing places HALO already knows about.';
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _results = query.isEmpty
          ? _discovered
          : [
              for (final spot in _discovered)
                if (spot.name.toLowerCase().contains(query) ||
                    spot.categoryLabel.toLowerCase().contains(query))
                  spot,
            ];
    });
  }

  Future<void> _nominate(SafeSpot spot) async {
    setState(() => _saving = true);
    try {
      await _service.createSafeSpot(
        name: spot.name,
        category: spot.category,
        latitude: spot.latitude,
        longitude: spot.longitude,
        openHours: spot.openHours,
        source: SafeSpotSource.discovered,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${spot.name} added as a Safe Spot.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that Safe Spot.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a Safe Spot')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _applyFilter(),
              decoration: InputDecoration(
                hintText: 'Search nearby places',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(chipRadius),
                ),
              ),
            ),
          ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(chipRadius),
                border: Border.all(
                  color: colorRed.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.triangleAlert,
                    size: 16,
                    color: colorRed,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _discover,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 190,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'dev.halo.safewalk',
                ),
                MarkerLayer(
                  markers: [
                    for (final spot in _results)
                      Marker(
                        point: ll.LatLng(spot.latitude, spot.longitude),
                        width: 26,
                        height: 26,
                        child: const Icon(
                          LucideIcons.mapPin,
                          size: 22,
                          color: colorGreen,
                        ),
                      ),
                    Marker(
                      point: widget.center,
                      width: 18,
                      height: 18,
                      child: const Icon(
                        LucideIcons.navigation,
                        size: 16,
                        color: colorBlue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(
                        child: Text(
                          'No places found here yet.',
                          style: TextStyle(color: textMuted2),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final spot = _results[index];
                          return ListTile(
                            leading: const Icon(
                              LucideIcons.mapPin,
                              size: 18,
                              color: colorGreen,
                            ),
                            title: Text(spot.name),
                            subtitle: Text(
                              [
                                spot.categoryLabel,
                                if (spot.openHours != null) spot.openHours!,
                              ].join(' - '),
                              style: const TextStyle(
                                color: textMuted2,
                                fontSize: 12,
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: _saving ? null : () => _nominate(spot),
                              child: const Text('Add'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
