import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/community.dart';
import '../models/incident.dart';
import '../models/safe_spot.dart';
import '../models/unseen_hero.dart';
import '../services/cold_start_engine.dart';
import '../services/moderation_service.dart';
import '../services/google_places_service.dart';
import '../services/incident_service.dart';
import '../services/place_search_service.dart';
import '../services/safe_spot_service.dart';
import '../services/sentiment_service.dart';
import '../services/unseen_hero_service.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

import '../utils/safety_zones.dart';
import '../widgets/hero_help_request_sheet.dart';
import '../widgets/place_search_sheet.dart';
import '../widgets/safety_intelligence_sheet.dart';
import 'discover_safe_spots_screen.dart';
import 'moderation_queue_screen.dart';

const _fallbackCenter = ll.LatLng(12.9716, 77.5946);

/// Which SafeWalk layers are drawn. [all] shows every layer at once.
enum SafeWalkFilter { all, incidents, halos, safeSpots }

extension on SafeWalkFilter {
  String get label {
    switch (this) {
      case SafeWalkFilter.all:
        return 'All';
      case SafeWalkFilter.incidents:
        return 'Incidents';
      case SafeWalkFilter.halos:
        return 'HALOs';
      case SafeWalkFilter.safeSpots:
        return 'Safe Spots';
    }
  }

  bool get showIncidents =>
      this == SafeWalkFilter.all || this == SafeWalkFilter.incidents;

  bool get showHalos =>
      this == SafeWalkFilter.all || this == SafeWalkFilter.halos;

  bool get showSafeSpots =>
      this == SafeWalkFilter.all || this == SafeWalkFilter.safeSpots;
}

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

class _SafeWalkScreenState extends State<SafeWalkScreen>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  late final AnimationController _zonePulse;
  ll.LatLng _center = _fallbackCenter;
  ll.LatLng? _currentLocation;
  bool _locating = true;
  bool _locationFailed = false;
  bool _tilesUnavailable = false;
  static const _heroRadiusMeters = 5000.0;
  static const _areaRadiusOptions = <double>[1000, 2000, 5000, 10000];
  Stream<List<NearbyUnseenHero>>? _heroesStream;
  ll.LatLng? _heroSearchCenter;
  String? _heroSearchCenterLabel;

  ll.LatLng _areaCenter = _fallbackCenter;
  double _areaRadiusMeters = 5000;
  Stream<List<Incident>>? _incidentsStream;
  Timer? _areaDebounce;
  List<Community> _communities = const [];
  List<SafeSpot> _safeSpots = const [];
  StreamSubscription<List<Community>>? _communitiesSub;
  StreamSubscription<List<SafeSpot>>? _safeSpotsSub;
  SafeWalkFilter _filter = SafeWalkFilter.all;
  bool _showHeat = true;
  HeatRange _heatRange = HeatRange.allHistory;
  List<Incident> _historicalIncidents = const [];
  StreamSubscription<List<Incident>>? _historySub;
  final ColdStartEngine _coldStart = ColdStartEngine();
  final GooglePlacesService _places = GooglePlacesService();

  List<Community> get _communitiesWithFootprint =>
      _communities.where((c) => c.footprint != null).toList();

  @override
  void initState() {
    super.initState();
    _zonePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _refreshIncidents(_fallbackCenter);
    _centerOnCurrentLocation();
  }

  @override
  void dispose() {
    _zonePulse.dispose();
    _areaDebounce?.cancel();
    _communitiesSub?.cancel();
    _safeSpotsSub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  void _refreshIncidents(ll.LatLng center) {
    _areaCenter = center;
    _incidentsStream = IncidentService.watchIncidents(
      center: center,
      radiusMeters: _areaRadiusMeters,
    );
    _watchLayers(center);
  }

  /// Every map layer is scoped to exactly the same centre and radius as the
  /// incident list, so nothing is ever drawn outside the "your area" filter.
  void _watchLayers(ll.LatLng center) {
    _communitiesSub?.cancel();
    _safeSpotsSub?.cancel();
    _historySub?.cancel();
    _communitiesSub = SafeSpotService.watchCommunitiesWithArea(
      center: center,
      radiusMeters: _areaRadiusMeters,
    ).listen((communities) {
      if (!mounted) return;
      setState(() => _communities = communities);
    });
    _safeSpotsSub = SafeSpotService.watchSafeSpots(
      center: center,
      radiusMeters: _areaRadiusMeters,
    ).listen((spots) {
      if (!mounted) return;
      setState(() => _safeSpots = spots);
    });
    _historySub = IncidentService.watchHistoricalIncidents(
      center: center,
      radiusMeters: _areaRadiusMeters,
    ).listen((incidents) {
      if (!mounted) return;
      setState(() => _historicalIncidents = incidents);
    });
  }

  void _setAreaRadius(double meters) {
    if (meters == _areaRadiusMeters) return;
    setState(() {
      _areaRadiusMeters = meters;
      _incidentsStream = IncidentService.watchIncidents(
        center: _areaCenter,
        radiusMeters: meters,
      );
    });
    _watchLayers(_areaCenter);
  }

  void _scheduleIncidentRefresh() {
    _areaDebounce?.cancel();
    _areaDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final cameraCenter = _mapController.camera.center;
      setState(() => _refreshIncidents(cameraCenter));
    });
  }

  Future<void> _centerOnCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationFailed = true);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locationFailed = true);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _center = ll.LatLng(position.latitude, position.longitude);
        _currentLocation = _center;
        _locationFailed = false;
        _refreshIncidents(_center);
      });
      _mapController.move(_center, 15);
      _findHeroesNear(_center);
    } catch (_) {
      if (mounted) setState(() => _locationFailed = true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _showSosSheet() async {
    final alertDemo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (_) => _SosSheet(
        onDemoAlert: () => Navigator.of(context).pop(true),
      ),
    );
    if (alertDemo != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo SOS sent to nearby sample Unseen Heroes.'),
      ),
    );
  }

  List<PlaceResult> _localPlaceResults() {
    final results = <PlaceResult>[];
    for (final community in _communities) {
      final center = community.center;
      if (center == null) continue;
      results.add(
        PlaceResult(
          id: community.id,
          title: community.name,
          subtitle: community.description,
          latitude: center.latitude,
          longitude: center.longitude,
          kind: PlaceResultKind.community,
        ),
      );
    }
    for (final spot in _safeSpots) {
      results.add(
        PlaceResult(
          id: spot.id,
          title: spot.name,
          subtitle: spot.categoryLabel,
          latitude: spot.latitude,
          longitude: spot.longitude,
          kind: PlaceResultKind.safeSpot,
        ),
      );
    }
    return results;
  }

  Future<void> _openPlaceSearch() async {
    final result = await showModalBottomSheet<PlaceResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (_) => PlaceSearchSheet(
        localResults: _localPlaceResults,
        bias: PlaceResult(
          id: 'bias',
          title: '',
          subtitle: '',
          latitude: _center.latitude,
          longitude: _center.longitude,
          kind: PlaceResultKind.place,
        ),
        onSelect: (picked) => Navigator.of(context).pop(picked),
      ),
    );
    if (result == null || !mounted) return;
    final point = result.point;
    setState(() {
      _center = point;
      _refreshIncidents(point);
    });
    _mapController.move(point, 15);
    _findHeroesNear(point);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Showing SafeWalk around ${result.title}.')),
    );
  }

  void _findHeroesNear(ll.LatLng point) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _heroSearchCenter = point;
      _heroesStream = UnseenHeroService.watchNearbyHeroes(
        center: point,
        radiusMeters: _heroRadiusMeters,
        currentUserId: uid,
      );
      _heroSearchCenterLabel =
          '${point.latitude.toStringAsFixed(2)}, ${point.longitude.toStringAsFixed(2)}';
    });
  }

  void _showIncident(Incident incident) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForType(incident.type),
                    color: _colorForType(incident.type),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _labelForType(incident.type),
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MetaPill(
                    icon: LucideIcons.clock,
                    label: incident.timeOfDay,
                  ),
                  const SizedBox(width: 8),
                  _MetaPill(
                    icon: LucideIcons.timer,
                    label: relativeTime(incident.reportedAt),
                  ),
                  const SizedBox(width: 8),
                  _MetaPill(
                    icon: incident.isConfirmed
                        ? LucideIcons.badgeCheck
                        : LucideIcons.circleHelp,
                    label: incident.moderationStatus.label,
                  ),
                  const SizedBox(width: 8),
                  _MetaPill(
                    icon: incident.locationSource == 'gps'
                        ? LucideIcons.locateFixed
                        : LucideIcons.mapPin,
                    label: incident.locationSource == 'gps'
                        ? 'At my location'
                        : 'Picked on the map',
                  ),
                ],
              ),
              if (!incident.isConfirmed) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(chipRadius),
                    border: Border.all(
                      color: accentGold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Not yet confirmed. Someone in the community is checking '
                    'this report, or it was automatically flagged. It is shown '
                    'here because a first-hand report is still worth reading - '
                    'just not as established fact.',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              if (incident.description != null &&
                  incident.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  incident.description!,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Anonymous report. Only an approximate area is stored, and it '
                'is never linked to an account.',
                style: TextStyle(
                  color: textMuted2,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSafeSpot(SafeSpot spot) {
    final verified = spot.isVerifiedAt(DateTime.now());
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    verified
                        ? LucideIcons.shieldCheck
                        : LucideIcons.shieldQuestion,
                    color: verified ? colorGreen : textMuted,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      spot.name,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(
                    icon: LucideIcons.mapPin,
                    label: spot.categoryLabel,
                  ),
                  if (spot.openHours != null)
                    _MetaPill(
                      icon: LucideIcons.clock,
                      label: spot.openHours!,
                    ),
                  _MetaPill(
                    icon: verified ? LucideIcons.badgeCheck : LucideIcons.info,
                    label: verified ? 'Verified' : 'Community listed',
                  ),
                ],
              ),
              if (spot.address != null) ...[
                const SizedBox(height: 12),
                Text(
                  spot.address!,
                  style: const TextStyle(color: textMuted, fontSize: 13),
                ),
              ],
              if (spot.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  spot.description!,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Provenance is always spelled out. An auto-discovered place is
              // useful, but a user must never read "safe" as "someone checked
              // this and it held up".
              Text(
                spot.sourceLabel,
                style: TextStyle(
                  color: spot.isDiscovered ? textMuted2 : textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (verified) ...[
                const SizedBox(height: 4),
                Text(
                  'Verified until ${_shortDate(spot.verifiedUntil!)}',
                  style: const TextStyle(color: colorGreen, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _vouchForSafeSpot(spot),
                        icon: const Icon(
                          LucideIcons.thumbsUp,
                          size: 15,
                        ),
                        label: Text(
                          spot.vouches == 0
                              ? 'I know this place'
                              : 'Vouched (${spot.vouches})',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorGreen,
                          side: BorderSide(
                            color: colorGreen.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'A vouch is one person saying the place is real and staffed. '
                  'It is not a safety guarantee, and it does not verify the '
                  'listing.',
                  style: TextStyle(color: textMuted2, fontSize: 11.5),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openDiscovery();
                  },
                  icon: const Icon(LucideIcons.mapPinned, size: 16),
                  label: const Text('Find places to add near here'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _vouchForSafeSpot(SafeSpot spot) async {
    try {
      await SafeSpotService().vouchSafeSpot(
        spot.id,
        currentVouches: spot.vouches,
      );
      if (!mounted) return;
      setState(() {
        _safeSpots = [
          for (final existing in _safeSpots)
            if (existing.id == spot.id)
              SafeSpot(
                id: existing.id,
                name: existing.name,
                category: existing.category,
                latitude: existing.latitude,
                longitude: existing.longitude,
                createdAt: existing.createdAt,
                description: existing.description,
                address: existing.address,
                openHours: existing.openHours,
                verifiedBy: existing.verifiedBy,
                verifiedUntil: existing.verifiedUntil,
                source: existing.source,
                addedBy: existing.addedBy,
                vouches: existing.vouches + 1,
                geohashPrefix: existing.geohashPrefix,
              )
            else
              existing,
        ];
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Thanks - you vouched for ${spot.name}.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not record that vouch. Sign in and try again.'),
        ),
      );
    }
  }

  Future<void> _openSafetyIntelligence({
    required int reportCount,
    required int heroCount,
  }) async {
    final center = _mapController.camera.center;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checking what we know about this area...')),
    );
    final picture = await _coldStart.build(
      center: center,
      reportCount: reportCount,
      safeSpotCount: _safeSpots.length,
      heroCount: heroCount,
    );
    if (!mounted) return;
    await SafetyIntelligenceSheet.show(
      context,
      picture: picture,
      placesAvailable: _places.isConfigured,
      onAddSafeSpot: () {
        Navigator.of(context).pop();
        _openDiscovery();
      },
    );
  }

  void _openDiscovery() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoverSafeSpotsScreen(
          center: _mapController.camera.center,
          radiusMeters: _areaRadiusMeters,
        ),
      ),
    );
  }

  static String _shortDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  void _showCommunity(Community community) {
    final footprint = community.footprint;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.users,
                    color: accentPurple,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      community.name,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (community.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  community.description,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _MetaPill(
                    icon: LucideIcons.users,
                    label: '${community.memberIds.length} members',
                  ),
                  const SizedBox(width: 8),
                  if (footprint != null)
                    _MetaPill(
                      icon: LucideIcons.circleDot,
                      label: '${_distanceLabel(footprint.radius)} area',
                    ),
                ],
              ),
              if (footprint != null) ...[
                const SizedBox(height: 8),
                Text(
                  'This community covers the purple circle on the map. '
                  'Its area is a community boundary, not a tracked location.',
                  style: TextStyle(
                    color: textMuted2,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _center = footprint?.point ?? _center;
                  _refreshIncidents(_center);
                  _mapController.move(_center, 14);
                },
                icon: const Icon(LucideIcons.locate, size: 18),
                label: Text(
                  footprint == null ? 'Close' : 'Centre map on this area',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHero(NearbyUnseenHero hero) {
    showUnseenHeroDetails(context, hero);
  }

  String _distanceLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  /// Pulse envelope for a zone: 1.0 at rest, swelling to ~1.18 and fading as
  /// the controller runs forward. Weighted by cluster strength so a quiet
  /// zone barely moves and a busy one is impossible to miss.
  double _zoneScale(double weight) {
    final swell = 1 + 0.18 * _zonePulse.value * weight;
    return swell;
  }

  /// Opens the report flow, defaulting to the reporter's own position.
  ///
  /// The old behaviour used whatever point was passed in — a map tap or the
  /// current centre — which meant a report about *your* street could be filed
  /// against a point the map happened to be showing. For "I was followed" or
  /// "this stretch is unlit", that is not a small detail: it puts the report
  /// somewhere the user never was. So the sheet now defaults to the real GPS
  /// fix, and the alternative is an explicit, labelled choice.
  Future<void> _startReport({ll.LatLng? at}) async {
    final fix = _currentLocation;
    if (fix != null) {
      await _reportAt(fix, locationSource: 'gps', tappedPoint: at);
      return;
    }

    if (at != null) {
      // No fix: ask before falling back, so the user is never silently
      // downgraded to reporting a place they are not standing in.
      final choice = await _askReportLocation(at);
      if (choice == null || !mounted) return;
      if (choice.useGps) {
        setState(() => _locating = true);
        await _centerOnCurrentLocation();
        if (!mounted) return;
        final fresh = _currentLocation;
        if (fresh != null) {
          await _reportAt(fresh, locationSource: 'gps', tappedPoint: at);
          return;
        }
      }
      await _reportAt(at, locationSource: 'mapPoint');
      return;
    }

    await _reportAt(
      _mapController.camera.center,
      locationSource: 'crosshair',
    );
  }

  Future<({bool useGps})?> _askReportLocation(ll.LatLng tapped) {
    return showDialog<({bool useGps})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: bgSurface2,
        title: const Text('Where did this happen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HALO could not get a location fix, so this report would be '
              'filed against a point on the map rather than where you are.\n\n'
              'That is right for flagging a place someone else described, and '
              'wrong for something that happened to you.',
              style: TextStyle(
                color: textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                LucideIcons.locateFixed,
                color: colorBlue,
                size: 20,
              ),
              title: const Text('Get my location'),
              subtitle: const Text('Recommended'),
              onTap: () => Navigator.of(dialogContext).pop((useGps: true)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                LucideIcons.mapPin,
                color: textMuted,
                size: 20,
              ),
              title: const Text('Use the point I tapped'),
              subtitle: Text(
                '${tapped.latitude.toStringAsFixed(4)}, '
                '${tapped.longitude.toStringAsFixed(4)}',
              ),
              onTap: () => Navigator.of(dialogContext).pop((useGps: false)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportAt(
    ll.LatLng point, {
    String locationSource = 'mapPoint',
    ll.LatLng? tappedPoint,
  }) async {
    final selection = await showModalBottomSheet<_ReportSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (_) => _ReportSheet(
        locationSource: locationSource,
        location: point,
        tappedPoint: tappedPoint,
      ),
    );

    if (selection == null || !mounted) return;

    try {
      await IncidentService.submitIncident(
        latitude: selection.location.latitude,
        longitude: selection.location.longitude,
        type: selection.type,
        description: selection.description,
        anonymity: selection.anonymity,
        userId: FirebaseAuth.instance.currentUser?.uid,
        locationSource: selection.effectiveLocationSource,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selection.anonymity == ReportAnonymity.anonymous
                ? 'Report submitted anonymously. Thank you for helping keep '
                    'this area safe.'
                : 'Report submitted with a private handle. Thank you for '
                    'helping keep this area safe.',
          ),
        ),
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
      body: StreamBuilder<List<Incident>>(
        stream: _incidentsStream,
        builder: (context, incidentSnapshot) {
          final incidents = incidentSnapshot.data ?? const <Incident>[];

          return StreamBuilder<List<NearbyUnseenHero>>(
            stream: _heroesStream,
            initialData: const <NearbyUnseenHero>[],
            builder: (context, heroSnapshot) {
              final heroes = heroSnapshot.data ?? const <NearbyUnseenHero>[];
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
                            minZoom: 5,
                            maxZoom: 18,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all,
                            ),
                            onTap: (tapPosition, point) =>
                                _startReport(at: point),
                            onPositionChanged: (camera, hasGesture) {
                              if (hasGesture) _scheduleIncidentRefresh();
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.halo.app',
                              errorTileCallback: (_, __, ___) {
                                if (mounted && !_tilesUnavailable) {
                                  setState(() => _tilesUnavailable = true);
                                }
                              },
                            ),
                            if (_filter.showIncidents && _showHeat)
                              _HeatLayer(
                                incidents: _historicalIncidents,
                                range: _heatRange,
                              ),
                            if (_filter.showIncidents)
                              AnimatedBuilder(
                                animation: _zonePulse,
                                builder: (context, _) {
                                  final zones = SafetyZones.incidentZones(
                                    incidents,
                                  );
                                  if (zones.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return CircleLayer(
                                    circles: [
                                      for (final zone in zones)
                                        CircleMarker(
                                          point: zone.center,
                                          radius: zone.radiusMeters *
                                              _zoneScale(zone.weight),
                                          useRadiusInMeter: true,
                                          color: colorRed.withValues(
                                            alpha: 0.10 +
                                                0.14 *
                                                    _zonePulse.value *
                                                    zone.weight,
                                          ),
                                          borderColor: colorRed.withValues(
                                            alpha: 0.25 + 0.35 * zone.weight,
                                          ),
                                          borderStrokeWidth: 1.2,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            if (_filter.showSafeSpots && _safeSpots.isNotEmpty)
                              CircleLayer(
                                circles: [
                                  for (final spot in _safeSpots)
                                    CircleMarker(
                                      point: ll.LatLng(
                                          spot.latitude, spot.longitude),
                                      radius: spot.isVerifiedAt(DateTime.now())
                                          ? 110
                                          : 70,
                                      useRadiusInMeter: true,
                                      color: colorGreen.withValues(alpha: 0.10),
                                      borderColor: colorGreen.withValues(
                                        alpha: spot.isVerifiedAt(DateTime.now())
                                            ? 0.45
                                            : 0.2,
                                      ),
                                      borderStrokeWidth: 1.2,
                                    ),
                                ],
                              ),
                            if (_filter.showHalos)
                              AnimatedBuilder(
                                animation: _zonePulse,
                                builder: (context, _) {
                                  final zones = SafetyZones.heroZones(heroes);
                                  if (zones.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return CircleLayer(
                                    circles: [
                                      for (final zone in zones)
                                        CircleMarker(
                                          point: zone.center,
                                          radius: zone.radiusMeters *
                                              _zoneScale(zone.weight),
                                          useRadiusInMeter: true,
                                          color: accentGold.withValues(
                                            alpha: 0.08 +
                                                0.10 *
                                                    _zonePulse.value *
                                                    zone.weight,
                                          ),
                                          borderColor: accentGold.withValues(
                                            alpha: 0.18 + 0.3 * zone.weight,
                                          ),
                                          borderStrokeWidth: 1.2,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            if (_filter.showHalos &&
                                _communitiesWithFootprint.isNotEmpty)
                              CircleLayer(
                                circles: [
                                  for (final community
                                      in _communitiesWithFootprint)
                                    CircleMarker(
                                      point: community.footprint!.point,
                                      radius: community.footprint!.radius,
                                      useRadiusInMeter: true,
                                      color: accentPurpleDim,
                                      borderColor: accentPurple,
                                      borderStrokeWidth: 1.5,
                                    ),
                                ],
                              ),
                            if (_filter.showHalos)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: _areaCenter,
                                    radius: _areaRadiusMeters,
                                    useRadiusInMeter: true,
                                    color: accentGoldDim,
                                    borderColor: accentGold,
                                    borderStrokeWidth: 1,
                                  ),
                                ],
                              ),
                            if (_heroSearchCenter != null)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: _heroSearchCenter!,
                                    radius: _heroRadiusMeters,
                                    useRadiusInMeter: true,
                                    color: accentGoldDim,
                                    borderColor: accentGold,
                                    borderStrokeWidth: 1,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                if (_filter.showHalos &&
                                    _currentLocation != null)
                                  Marker(
                                    point: _currentLocation!,
                                    width: 30,
                                    height: 30,
                                    alignment: Alignment.center,
                                    child: const _CurrentLocationDot(),
                                  ),
                                if (_filter.showHalos)
                                  for (final community
                                      in _communitiesWithFootprint)
                                    Marker(
                                      point: community.footprint!.point,
                                      width: 132,
                                      height: 44,
                                      alignment: Alignment.topCenter,
                                      child: GestureDetector(
                                        onTap: () => _showCommunity(community),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bgSurface3,
                                            borderRadius: BorderRadius.circular(
                                                chipRadius),
                                            border: Border.all(
                                              color: accentPurple,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                LucideIcons.users,
                                                color: accentPurple,
                                                size: 13,
                                              ),
                                              const SizedBox(width: 5),
                                              Flexible(
                                                child: Text(
                                                  community.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: textPrimary,
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                if (_filter.showIncidents)
                                  for (final incident in incidents)
                                    Marker(
                                      point: ll.LatLng(
                                        incident.latitude,
                                        incident.longitude,
                                      ),
                                      width: 34,
                                      height: 34,
                                      child: GestureDetector(
                                        onTap: () => _showIncident(incident),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          clipBehavior: Clip.none,
                                          children: [
                                            Icon(
                                              _iconForType(incident.type),
                                              color:
                                                  _colorForType(incident.type),
                                              size: 26,
                                            ),
                                            // An unconfirmed report is
                                            // visibly different from a
                                            // confirmed one, rather than
                                            // quietly counted the same.
                                            if (!incident.isConfirmed)
                                              const Positioned(
                                                right: -3,
                                                top: -3,
                                                child: Icon(
                                                  LucideIcons.circleHelp,
                                                  size: 11,
                                                  color: textMuted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                if (_filter.showSafeSpots)
                                  for (final spot in _safeSpots)
                                    Marker(
                                      point: ll.LatLng(
                                        spot.latitude,
                                        spot.longitude,
                                      ),
                                      width: 38,
                                      height: 38,
                                      child: GestureDetector(
                                        onTap: () => _showSafeSpot(spot),
                                        child: _SafeSpotPin(
                                          spot: spot,
                                        ),
                                      ),
                                    ),
                                if (_filter.showHalos)
                                  for (final hero in heroes)
                                    Marker(
                                      point: ll.LatLng(
                                        hero.presence.latitude,
                                        hero.presence.longitude,
                                      ),
                                      width: 44,
                                      height: 44,
                                      child: GestureDetector(
                                        onTap: () => _showHero(hero),
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: bgSurface3,
                                            border: Border.all(
                                              color: accentGold,
                                              width: 2,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x66000000),
                                                blurRadius: 8,
                                                offset: Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            LucideIcons.crown,
                                            color: accentGold,
                                            size: 21,
                                          ),
                                        ),
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
                            child: Center(
                              child: CircularProgressIndicator(
                                color: accentGold,
                              ),
                            ),
                          ),
                        if (_tilesUnavailable)
                          Positioned(
                            top: 64,
                            left: 16,
                            right: 16,
                            child: Material(
                              color: colorRedDim,
                              borderRadius: BorderRadius.circular(buttonRadius),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.wifiOff,
                                      color: colorRed,
                                      size: 17,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Map tiles unavailable. Check the phone internet connection.',
                                        style: TextStyle(
                                          color: colorRed,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        PaintingBinding.instance.imageCache
                                            .clearLiveImages();
                                        setState(
                                            () => _tilesUnavailable = false);
                                      },
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _RoundMapButton(
                            icon: LucideIcons.locateFixed,
                            busy: _locating,
                            onTap: () {
                              setState(() => _locating = true);
                              _centerOnCurrentLocation();
                            },
                          ),
                        ),
                        Positioned(
                          top: 62,
                          left: 12,
                          right: 12,
                          child: _LayerFilterBar(
                            value: _filter,
                            onChanged: (next) => setState(() => _filter = next),
                          ),
                        ),
                        Positioned(
                          top: 108,
                          left: 12,
                          child: _SearchMapButton(
                            onTap: _openPlaceSearch,
                          ),
                        ),
                        if (_locationFailed)
                          Positioned(
                            top: 108,
                            right: 12,
                            child: _LocationFailedPill(
                              onTap: () {
                                setState(() => _locating = true);
                                _centerOnCurrentLocation();
                              },
                            ),
                          ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: bgSurface3,
                                  foregroundColor: accentGold,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                ),
                                onPressed: () => _findHeroesNear(
                                  _mapController.camera.center,
                                ),
                                icon: heroSnapshot.connectionState ==
                                            ConnectionState.waiting &&
                                        _heroesStream != null
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: accentGold,
                                        ),
                                      )
                                    : const Icon(LucideIcons.radar, size: 17),
                                label: const Text('Find heroes'),
                              ),
                              const SizedBox(height: 8),
                              Material(
                                color: bgSurface3,
                                borderRadius: BorderRadius.circular(chipRadius),
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(chipRadius),
                                  onTap: () => _openSafetyIntelligence(
                                    reportCount: _historicalIncidents.length,
                                    heroCount: heroes.length,
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.radar,
                                          size: 14,
                                          color: colorBlue,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Area intel',
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_heroesStream != null && heroes.isNotEmpty)
                          Positioned(
                            top: 16,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: bgSurface3,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: accentGoldBorder),
                              ),
                              child: Text(
                                '${heroes.length} within 5 km',
                                style: const TextStyle(
                                  color: accentGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 40,
                          right: 16,
                          child: _RoundMapButton(
                            icon: LucideIcons.scale,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ModerationQueueScreen(),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 96,
                          left: 12,
                          child: _HeatLegend(
                            showHeat: _showHeat,
                            range: _heatRange,
                            onToggle: () =>
                                setState(() => _showHeat = !_showHeat),
                            onRangeChanged: (next) =>
                                setState(() => _heatRange = next),
                          ),
                        ),
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorRed,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _showSosSheet,
                                  icon: const Icon(
                                    LucideIcons.siren,
                                    size: 20,
                                  ),
                                  label: const Text('SOS'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: () => _startReport(),
                                  icon: const Icon(
                                    LucideIcons.mapPinPlus,
                                    size: 18,
                                  ),
                                  label: const Text('Report this location'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (kDebugMode)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingPadding,
                        vertical: 9,
                      ),
                      color: accentGoldDim,
                      child: const Row(
                        children: [
                          Icon(
                            LucideIcons.sparkles,
                            color: accentGold,
                            size: 17,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Teacher demo: sample heroes and safety reports are active. Help requests stay on this device.',
                              style: TextStyle(
                                color: accentGold,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (heroSnapshot.hasError)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingPadding,
                        vertical: 10,
                      ),
                      color: colorRedDim,
                      child: const Text(
                        'Unseen Hero search is unavailable. Community reports still work.',
                        style: TextStyle(color: colorRed, fontSize: 11.5),
                      ),
                    )
                  else if (heroes.isNotEmpty)
                    _buildHeroStrip(heroes)
                  else if (_heroesStream != null &&
                      heroSnapshot.connectionState != ConnectionState.waiting)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingPadding,
                        vertical: 12,
                      ),
                      child: Text(
                        _heroSearchCenterLabel == null
                            ? 'No opted-in Unseen Heroes found nearby.'
                            : 'No opted-in Unseen Heroes within 5 km of $_heroSearchCenterLabel.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      spacingPadding,
                      spacingSmallGap,
                      spacingPadding,
                      4,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.clock,
                          size: 14,
                          color: textMuted,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Recent in your area',
                          style: TextStyle(
                            color: textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${incidents.length} within ${_distanceLabel(_areaRadiusMeters)}',
                          style: const TextStyle(
                            color: textMuted2,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingPadding,
                      ),
                      children: [
                        for (final option in _areaRadiusOptions) ...[
                          _AreaChip(
                            label: _distanceLabel(option),
                            selected: option == _areaRadiusMeters,
                            onTap: () => _setAreaRadius(option),
                          ),
                          const SizedBox(width: spacingSmallGap),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _IncidentListPanel(
                      snapshot: incidentSnapshot,
                      incidents: incidents,
                      radiusLabel: _distanceLabel(_areaRadiusMeters),
                      loading: _incidentsStream == null ||
                          incidentSnapshot.connectionState ==
                              ConnectionState.waiting,
                      onRetry: () =>
                          _refreshIncidents(_mapController.camera.center),
                      onOpenIntelligence: () => _openSafetyIntelligence(
                        reportCount: _historicalIncidents.length,
                        heroCount: 0,
                      ),
                      onOpenIncident: (incident) => _showIncident(incident),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHeroStrip(List<NearbyUnseenHero> heroes) {
    return Container(
      height: 142,
      color: bgSurface3,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacingPadding),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.crown,
                  color: accentGold,
                  size: 16,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Unseen Heroes near this area',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Within 5 km',
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 10.5,
                    decoration: TextDecoration.underline,
                    decorationColor: textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: spacingPadding),
              itemCount: heroes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final hero = heroes[index];
                return SizedBox(
                  width: 190,
                  child: Card(
                    color: bgSurface2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(buttonRadius),
                      onTap: () => _showHero(hero),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: accentGoldDim,
                              ),
                              child: const Icon(
                                LucideIcons.crown,
                                color: accentGold,
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hero.presence.heroName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _distanceLabel(hero.distanceMeters),
                                    style: const TextStyle(
                                      color: accentGold,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    hero.presence.areaName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textMuted,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

/// The user's own position on the map: a blue accuracy halo with a solid
/// centre dot. Deliberately shown only once a real fix is available, so the
/// fallback map centre is never mistaken for "you are here".
/// Density heat layer: coarse cells over the report history, drawn as
/// stacked translucent circles so dense areas read hot without hiding the
/// individual pins underneath.
class _HeatLayer extends StatelessWidget {
  const _HeatLayer({required this.incidents, required this.range});

  final List<Incident> incidents;
  final HeatRange range;

  @override
  Widget build(BuildContext context) {
    final cells = SafetyZones.heatCells(incidents, range: range);
    if (cells.isEmpty) return const SizedBox.shrink();
    return CircleLayer(
      circles: [
        for (final cell in cells)
          CircleMarker(
            point: cell.center,
            radius: cell.radiusMeters,
            useRadiusInMeter: true,
            color: _heatColor(cell.intensity).withValues(
              alpha: 0.10 + 0.24 * cell.intensity,
            ),
          ),
      ],
    );
  }

  /// Cool amber for sparse history through to deep red for the worst cell,
  /// so the layer reads as intensity even in greyscale-ish contexts.
  static Color _heatColor(double intensity) {
    if (intensity < 0.5) {
      return Color.lerp(const Color(0xFFD4A843), colorRed, intensity * 2)!;
    }
    return Color.lerp(
        colorRed, const Color(0xFF7A1622), (intensity - 0.5) * 2)!;
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({
    required this.showHeat,
    required this.range,
    required this.onToggle,
    required this.onRangeChanged,
  });

  final bool showHeat;
  final HeatRange range;
  final VoidCallback onToggle;
  final ValueChanged<HeatRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgSurface3,
      borderRadius: BorderRadius.circular(chipRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(chipRadius),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showHeat ? LucideIcons.flame : LucideIcons.circleSlash,
                      size: 14,
                      color: showHeat ? colorRed : textMuted2,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Heat',
                      style: TextStyle(
                        color: showHeat ? textPrimary : textMuted2,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showHeat)
              for (final option in HeatRange.values)
                InkWell(
                  borderRadius: BorderRadius.circular(chipRadius),
                  onTap: () => onRangeChanged(option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: option == range ? accentGold : textMuted2,
                        fontSize: 11,
                        fontWeight:
                            option == range ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LayerFilterBar extends StatelessWidget {
  const _LayerFilterBar({required this.value, required this.onChanged});

  final SafeWalkFilter value;
  final ValueChanged<SafeWalkFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final filter in SafeWalkFilter.values) ...[
            _LayerChip(
              label: filter.label,
              selected: filter == value,
              onTap: () => onChanged(filter),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accentGold : bgSurface3,
      borderRadius: BorderRadius.circular(chipRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(chipRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? bgPrimary : textMuted,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SafeSpotPin extends StatelessWidget {
  const _SafeSpotPin({required this.spot});

  final SafeSpot spot;

  IconData get _icon {
    switch (spot.category) {
      case SafeSpotCategory.policeStation:
        return LucideIcons.shield;
      case SafeSpotCategory.hospital:
        return LucideIcons.heartPulse;
      case SafeSpotCategory.pharmacy:
        return LucideIcons.pill;
      case SafeSpotCategory.cafe:
        return LucideIcons.coffee;
      case SafeSpotCategory.shop:
        return LucideIcons.store;
      case SafeSpotCategory.library:
        return LucideIcons.bookOpen;
      case SafeSpotCategory.communityCentre:
        return LucideIcons.users;
      case SafeSpotCategory.transitStop:
        return LucideIcons.bus;
      case SafeSpotCategory.other:
        return LucideIcons.mapPin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = spot.isVerifiedAt(DateTime.now());
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorGreenDim,
        border: Border.all(
          color: verified ? colorGreen : textMuted,
          width: verified ? 2 : 1.2,
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(
        _icon,
        color: verified ? colorGreen : textMuted,
        size: 18,
      ),
    );
  }
}

class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorBlue.withValues(alpha: 0.18),
        border: Border.all(color: colorBlue, width: 1),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorBlue,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgSurface3,
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgSurface3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentGold,
                    ),
                  )
                : Icon(icon, color: accentGold, size: 20),
          ),
        ),
      ),
    );
  }
}

class _LocationFailedPill extends StatelessWidget {
  const _LocationFailedPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgSurface3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.locate, color: accentGold, size: 15),
              SizedBox(width: 6),
              Text(
                'Location off - tap to retry',
                style: TextStyle(
                  color: accentGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchMapButton extends StatelessWidget {
  const _SearchMapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgSurface3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.search, color: textPrimary, size: 16),
              SizedBox(width: 6),
              Text(
                'Search place',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accentGoldBorder : bgSurface3,
      borderRadius: BorderRadius.circular(chipRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(chipRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? accentGold : textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SosSheet extends StatelessWidget {
  const _SosSheet({required this.onDemoAlert});

  final VoidCallback onDemoAlert;

  Future<void> _callEmergency(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: '112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Call 112 for immediate emergency help.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.siren, color: colorRed, size: 26),
                SizedBox(width: 10),
                Text(
                  'Emergency help',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'HALO does not contact emergency services automatically. If you are in immediate danger, call your local emergency number now.',
              style: TextStyle(color: textMuted, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _callEmergency(context),
              icon: const Icon(LucideIcons.phoneCall, size: 20),
              label: const Text('Call 112'),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onDemoAlert,
                icon: const Icon(LucideIcons.radar, size: 18),
                label: const Text('Send demo alert to nearby heroes'),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Your exact location is never attached automatically. You choose what to share.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textMuted2, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result of the report sheet: the chosen category, plus free-text detail
/// when — and only when — [type] is [IncidentType.other].
class _ReportSelection {
  const _ReportSelection(
    this.type,
    this.description, {
    required this.location,
    required this.originalLocation,
    this.anonymity = ReportAnonymity.anonymous,
    this.locationSource = 'mapPoint',
  });

  final IncidentType type;
  final String? description;

  /// The coordinates this report is actually filed against. Carried on the
  /// selection rather than closed over, because the reporter may have swapped
  /// the GPS fix for their tapped point while the sheet was open.
  final ll.LatLng location;

  /// What the flow resolved before the reporter could edit it, so a corrected
  /// fix can be labelled honestly instead of still claiming to be "at my
  /// location".
  final ll.LatLng originalLocation;

  final ReportAnonymity anonymity;
  final String locationSource;

  /// Where the reported coordinates really came from.
  ///
  /// A hand-corrected fix is reported as `gpsCorrected`, not `gps`: it is
  /// still "a position I am near", but it is no longer the raw fix, and a
  /// reader deserves to know the difference.
  String get effectiveLocationSource {
    if (locationSource != 'gps') return locationSource;
    return location == originalLocation ? 'gps' : 'gpsCorrected';
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.locationSource,
    required this.location,
    this.tappedPoint,
  });

  /// How the coordinates attached to this report were obtained.
  final String locationSource;

  /// The coordinates this report will actually be filed against.
  final ll.LatLng location;

  /// The point the user tapped, when one exists. Offered as a swap target so
  /// correcting the location does not mean backing out and re-tapping.
  final ll.LatLng? tappedPoint;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _descriptionController = TextEditingController();
  // null = no category picked yet; once IncidentType.other is picked, stay
  // on this sheet showing a text field instead of popping immediately like
  // the fixed categories do.
  bool _describingOther = false;

  /// Anonymity is a decision the reporter makes explicitly, on the record,
  /// before they type anything — not an inference from what we happen to
  /// store. Default is the safer option.
  bool _anonymous = true;

  /// The point the report will be filed against. Starts at whatever the flow
  /// resolved, and can be swapped to the tapped point if the reporter realises
  /// the fix was wrong. Mutable here so correcting a bad GPS fix does not
  /// require backing out and starting over.
  late ll.LatLng _location = widget.location;

  /// Experimental tone-check state. Debug-only, on-demand, advisory — the
  /// whole feature is dead in release builds and never blocks submission.
  SentimentAssessment? _toneAssessment;
  bool _toneChecking = false;

  Future<void> _runToneCheck() async {
    final text = _descriptionController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _toneChecking = true;
      _toneAssessment = null;
    });
    final assessment = await SentimentService.assess(text);
    if (!mounted) return;
    setState(() {
      _toneChecking = false;
      _toneAssessment = assessment;
    });
  }

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_validate);
  }

  @override
  void dispose() {
    _descriptionController
      ..removeListener(_validate)
      ..dispose();
    super.dispose();
  }

  void _validate() => setState(() {});

  /// Live Layer 1 preview, so the reporter is told *before* submitting that
  /// their text will be held for review. Being surprised by moderation after
  /// submitting is the worst possible time to learn about it.
  List<ModerationFlag> get _layer1Flags => ModerationService.evaluate(
        type: IncidentType.other,
        description: _descriptionController.text,
      ).flags;

  void _pickType(IncidentType type) {
    if (type == IncidentType.other) {
      setState(() => _describingOther = true);
      return;
    }
    Navigator.of(context).pop(
      _ReportSelection(
        type,
        null,
        anonymity: _anonymous
            ? ReportAnonymity.anonymous
            : ReportAnonymity.pseudonymous,
        locationSource: widget.locationSource,
        location: _location,
        originalLocation: widget.location,
      ),
    );
  }

  void _submitOther() {
    final text = _descriptionController.text.trim();
    Navigator.of(context).pop(
      _ReportSelection(
        IncidentType.other,
        text.isEmpty ? null : text,
        anonymity: _anonymous
            ? ReportAnonymity.anonymous
            : ReportAnonymity.pseudonymous,
        locationSource: widget.locationSource,
        location: _location,
        originalLocation: widget.location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
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
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ReportLocationCard(
              location: _location,
              source: widget.locationSource,
              alternative: widget.tappedPoint,
              onUseAlternative: () => setState(() {
                _location = widget.tappedPoint!;
              }),
            ),
            const SizedBox(height: 12),
            const _AnonymityNotice(),
            const SizedBox(height: 10),
            _AnonymityToggle(
              anonymous: _anonymous,
              onChanged: (value) => setState(() => _anonymous = value),
            ),
            const SizedBox(height: 14),
            if (!_describingOther)
              Wrap(
                spacing: spacingSmallGap,
                runSpacing: spacingSmallGap,
                children: [
                  for (final type in IncidentType.values)
                    ActionChip(
                      avatar: Icon(_iconForType(type),
                          size: 16, color: _colorForType(type)),
                      label: Text(_labelForType(type)),
                      onPressed: () => _pickType(type),
                    ),
                ],
              )
            else ...[
              TextField(
                controller: _descriptionController,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe what you noticed...',
                ),
              ),
              if (_layer1Flags.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Layer1Preview(flags: _layer1Flags),
              ],
              if (SentimentService.isConfigured) ...[
                const SizedBox(height: 10),
                _ToneCheckCard(
                  checking: _toneChecking,
                  assessment: _toneAssessment,
                  onCheck: _runToneCheck,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _describingOther = false),
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _submitOther,
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The community reports list, with honest states for every branch.
///
/// The four cases are kept visually distinct on purpose. A failed query and
/// an area with no reports look almost identical if you collapse them into
/// "no data", and the difference matters: one is a broken connection, the
/// other is a real (if easily misread) fact about the neighbourhood.
class _IncidentListPanel extends StatelessWidget {
  const _IncidentListPanel({
    required this.snapshot,
    required this.incidents,
    required this.radiusLabel,
    required this.loading,
    required this.onRetry,
    required this.onOpenIntelligence,
    required this.onOpenIncident,
  });

  final AsyncSnapshot<List<Incident>> snapshot;
  final List<Incident> incidents;
  final String radiusLabel;
  final bool loading;
  final VoidCallback onRetry;
  final VoidCallback onOpenIntelligence;
  final void Function(Incident) onOpenIncident;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return _ListState(
        icon: LucideIcons.wifiOff,
        color: colorRed,
        title: 'Could not load community reports',
        // Say what actually failed, without leaking a raw exception into
        // the UI — a stack trace is not an explanation to a user.
        detail: 'Check your connection, then try again. Everything else on '
            'the map still works.',
        actionLabel: 'Retry',
        onAction: onRetry,
        secondaryLabel: 'Why does this matter?',
        onSecondary: onOpenIntelligence,
      );
    }

    if (loading && incidents.isEmpty) {
      return const _IncidentListSkeleton();
    }

    if (incidents.isEmpty) {
      return _ListState(
        icon: LucideIcons.mapPinOff,
        color: textMuted2,
        title: 'No reports within $radiusLabel',
        detail: 'That is not the same as "safe". Reports only exist where '
            'people felt able to send one.',
        actionLabel: 'What we know about this area',
        onAction: onOpenIntelligence,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: spacingPadding,
        vertical: 4,
      ),
      itemCount: incidents.length,
      itemBuilder: (context, index) {
        final incident = incidents[index];
        final hasDescription =
            incident.description != null && incident.description!.isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: spacingSmallGap),
          child: ListTile(
            leading: Icon(
              _iconForType(incident.type),
              color: _colorForType(incident.type),
            ),
            title: Text(
              _labelForType(incident.type),
              style: const TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              hasDescription
                  ? '${incident.description}\n${incident.timeOfDay} · '
                      '${relativeTime(incident.reportedAt)}'
                  : '${incident.timeOfDay} · '
                      '${relativeTime(incident.reportedAt)}',
              style: const TextStyle(
                color: textMuted,
                fontSize: 12,
              ),
            ),
            trailing: incident.isConfirmed
                ? null
                : const Icon(
                    LucideIcons.circleHelp,
                    size: 15,
                    color: textMuted2,
                  ),
            isThreeLine: hasDescription,
            onTap: () => onOpenIncident(incident),
          ),
        );
      },
    );
  }
}

/// Placeholder rows shown while the first page loads.
///
/// Skeletons rather than a bare spinner, so the list does not jump when data
/// arrives, and so it is obvious that content is coming rather than that the
/// area is empty.
class _IncidentListSkeleton extends StatelessWidget {
  const _IncidentListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: spacingPadding,
        vertical: 4,
      ),
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        height: 62,
        margin: const EdgeInsets.only(bottom: spacingSmallGap),
        decoration: BoxDecoration(
          color: bgSurface,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: bgSurface3,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 10,
                    width: 110.0 - index * 12,
                    decoration: BoxDecoration(
                      color: bgSurface3,
                      borderRadius: BorderRadius.circular(chipRadius),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 8,
                    width: 150.0 - index * 18,
                    decoration: BoxDecoration(
                      color: bgSurface3,
                      borderRadius: BorderRadius.circular(chipRadius),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared empty/error/attention state for a list panel.
class _ListState extends StatelessWidget {
  const _ListState({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows exactly where the report will be filed, and lets it be corrected.
///
/// The location is never implicit. A report pinned to the wrong coordinates
/// is worse than no report at all: it puts a warning on a street where
/// nothing happened, and erases the one that did.
class _ReportLocationCard extends StatelessWidget {
  const _ReportLocationCard({
    required this.location,
    required this.source,
    this.alternative,
    this.onUseAlternative,
  });

  final ll.LatLng location;
  final String source;
  final ll.LatLng? alternative;
  final VoidCallback? onUseAlternative;

  @override
  Widget build(BuildContext context) {
    final fromGps = source == 'gps';
    final color = fromGps ? colorGreen : accentGold;
    final label = switch (source) {
      'gps' => 'Your current location',
      'crosshair' => 'Centre of the map',
      _ => 'Point you picked on the map',
    };

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fromGps ? LucideIcons.locateFixed : LucideIcons.mapPin,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${location.latitude.toStringAsFixed(5)}, '
            '${location.longitude.toStringAsFixed(5)}',
            style: const TextStyle(
              color: textMuted,
              fontSize: 11.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (!fromGps) ...[
            const SizedBox(height: 6),
            const Text(
              'This is a place being described, not a place you are standing '
              'in. Readers will see it marked that way.',
              style: TextStyle(
                color: textMuted2,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
          if (alternative != null && onUseAlternative != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onUseAlternative,
              icon: const Icon(LucideIcons.locateFixed, size: 14),
              label: const Text('Wrong spot? Use the point I tapped'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The explicit anonymity notice.
///
/// It states three concrete things — what is stored, what is not, and who can
/// read it — because a vague "your report is anonymous" is not consent, and
/// gets people hurt when it turns out to be untrue in some way they did not
/// expect.
class _AnonymityNotice extends StatelessWidget {
  const _AnonymityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colorBlue.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: colorBlue.withValues(alpha: 0.28)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.eyeOff, size: 15, color: colorBlue),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your name, phone number and account are never attached to a '
              'report. Nobody using HALO can see who reported anything.\n\n'
              'Your location is stored at the precision you choose below, and '
              'the time is rounded to the hour.\n\n'
              'Reports are reviewed before they appear. If you include your own '
              'name, phone number or someone else\'s name in the description, '
              'the report will be held or rejected.',
              style: TextStyle(
                color: textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The anonymity control. On by default, and turning it off says plainly what
/// changes rather than just presenting a switch.
class _AnonymityToggle extends StatelessWidget {
  const _AnonymityToggle({required this.anonymous, required this.onChanged});

  final bool anonymous;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgSurface3,
      borderRadius: BorderRadius.circular(chipRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(chipRadius),
        onTap: () => onChanged(!anonymous),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                anonymous ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 17,
                color: anonymous ? colorGreen : accentGold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anonymous
                          ? 'Reporting anonymously'
                          : 'Reporting with a private handle',
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      anonymous
                          ? 'Nothing that links back to you is stored. We still '
                              'keep the report on record.'
                          : 'A one-way handle is stored so repeated reports '
                              'from one account can be rate-limited, and so '
                              'you can recognise your own. Your account id is '
                              'still never written to the report, and the '
                              'handle is never shown to anyone.',
                      style: const TextStyle(
                        color: textMuted2,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Switch.adaptive(
                value: anonymous,
                onChanged: onChanged,
                activeThumbColor: colorGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live Layer 1 feedback, shown before submission so moderation is never a
/// surprise.
class _Layer1Preview extends StatelessWidget {
  const _Layer1Preview({required this.flags});

  final List<ModerationFlag> flags;

  @override
  Widget build(BuildContext context) {
    final willHold = flags.length > 1;
    final color = willHold ? colorRed : accentGold;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                willHold ? LucideIcons.circleAlert : LucideIcons.triangleAlert,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  willHold
                      ? 'This will be held for review before it appears'
                      : 'This will be marked as not yet confirmed',
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final flag in flags)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '- ${flag.detail}',
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// On-demand experimental tone check backed by the optional debug-only
/// sentiment service. Shown only when SentimentService.isConfigured. The
/// label is displayed with the model's own caveat and borders labelled as
/// "experimental" — deliberately never styled like a verdict, because a
/// Multinomial NB trained on airline tweets is not a judge of a safety
/// report.
class _ToneCheckCard extends StatelessWidget {
  const _ToneCheckCard({
    required this.checking,
    required this.assessment,
    required this.onCheck,
  });

  final bool checking;
  final SentimentAssessment? assessment;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final result = assessment;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x14A78BFA),
        borderRadius: BorderRadius.circular(chipRadius),
        border:
            Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.flaskConical,
                  size: 15, color: Color(0xFFA78BFA)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tone check (experimental)',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (checking)
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: onCheck,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Analyze'),
                ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 6),
            if (result.available)
              Text(
                'Reads as ${result.label} (${(result.confidence * 100).round()}%)',
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              Text(
                result.reason ?? 'Tone check unavailable.',
                style: const TextStyle(color: textMuted, fontSize: 11.5),
              ),
            if (result.caveat != null) ...[
              const SizedBox(height: 4),
              Text(
                result.caveat!,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
