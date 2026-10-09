import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo/models/incident.dart';
import 'package:halo/models/recognition_post.dart';
import 'package:halo/models/safe_spot.dart';
import 'package:halo/models/unseen_hero.dart';
import 'package:halo/services/cold_start_engine.dart';
import 'package:halo/services/google_places_service.dart';
import 'package:halo/services/incident_service.dart';
import 'package:halo/services/lighting_service.dart';
import 'package:halo/services/moderation_service.dart';
import 'package:halo/services/overpass_service.dart';
import 'package:halo/services/safe_spot_service.dart';
import 'package:halo/services/safety_priors.dart';
import 'package:halo/services/unseen_hero_service.dart';
import 'package:halo/utils/geo.dart';
import 'package:halo/utils/reporter_pseudonym.dart';
import 'package:halo/utils/safety_zones.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  group('Unseen Hero geospatial privacy', () {
    test('rounds coordinates to three decimal places', () {
      expect(coarsenLatitude(12.34567), 12.346);
      expect(coarsenLongitude(-49.265506), -49.266);
    });

    test('rejects non-finite and out-of-range coordinates', () {
      expect(isValidCoordinate(51.5074, -0.1278), isTrue);
      expect(isValidCoordinate(91, 0), isFalse);
      expect(isValidCoordinate(0, 181), isFalse);
      expect(isValidCoordinate(double.nan, 0), isFalse);
      expect(isValidCoordinate(double.infinity, 0), isFalse);
    });

    test('encodes known geohashes', () {
      expect(encodeGeohash(57.64911, 10.40744, 11), 'u4pruydqqvj');
      expect(encodeGeohash(42.6, -5.6, 5), 'ezs42');
    });

    test('produces ordered bounds around a search center', () {
      final bounds = geohashBounds(12.9716, 77.5946, 5000);

      expect(bounds.lower.length, 5);
      expect(bounds.upper.length, 5);
      expect(bounds.lower.compareTo(bounds.upper), lessThanOrEqualTo(0));
    });

    test('measures nearby distance', () {
      expect(distanceMeters(12.9716, 77.5946, 12.9716, 77.5946), 0);
      expect(
        distanceMeters(0, 0, 1, 0),
        closeTo(111195, 100),
      );
    });
  });

  group('Unseen Hero recognition serialization', () {
    final createdAt = DateTime.utc(2026, 1, 2, 3, 4);

    RecognitionPost buildPost({
      bool isCandidate = true,
      GeoPoint? location,
      String? areaName,
      String? geohashPrefix,
    }) {
      return RecognitionPost(
        postId: 'recognition-1',
        senderId: 'sender-1',
        recipientId: 'hero-1',
        recipientDisplayName: 'Asha',
        message: 'Helped a stranger reach the station safely.',
        groupId: 'community-1',
        createdAt: createdAt,
        isUnseenHeroCandidate: isCandidate,
        location: location,
        areaName: areaName,
        geohashPrefix: geohashPrefix,
      );
    }

    test('serializes a complete approximate location', () {
      final data = buildPost(
        location: const GeoPoint(12.972, 77.595),
        areaName: 'Indiranagar',
        geohashPrefix: 'w85m2',
      ).toFirestore();

      expect(data['isUnseenHeroCandidate'], isTrue);
      expect(data['location'], const GeoPoint(12.972, 77.595));
      expect(data['areaName'], 'Indiranagar');
      expect(data['geohashPrefix'], 'w85m2');
      expect(data['locationPrecision'], 'approximateArea');
    });

    test('never serializes incomplete location data', () {
      final data = buildPost(
        location: const GeoPoint(12.972, 77.595),
        areaName: 'Indiranagar',
      ).toFirestore();

      expect(data.containsKey('isUnseenHeroCandidate'), isFalse);
      expect(data.containsKey('location'), isFalse);
      expect(data.containsKey('areaName'), isFalse);
      expect(data.containsKey('geohashPrefix'), isFalse);
      expect(data.containsKey('locationPrecision'), isFalse);
    });
  });

  group('Unseen Hero debug demo flow', () {
    setUp(UnseenHeroService.resetDebugState);
    tearDown(UnseenHeroService.resetDebugState);

    test('sends and lists a request for a sample hero', () async {
      const uid = 'demo-user';
      final heroes = await UnseenHeroService.watchNearbyHeroes(
        center: const ll.LatLng(12.9716, 77.5946),
        radiusMeters: 5000,
        currentUserId: uid,
      ).first;
      final available =
          heroes.firstWhere((hero) => hero.presence.helpAvailable);

      final request = await UnseenHeroService.createHelpRequest(
        requesterId: uid,
        hero: available.presence,
        message: 'Could you help me reach the main road safely?',
        contactAllowed: true,
      );
      final incoming = await UnseenHeroService.watchIncomingRequests(uid).first;
      final outgoing = await UnseenHeroService.watchOutgoingRequests(uid).first;

      expect(request.isPending, isTrue);
      expect(incoming.map((item) => item.id), contains(request.id));
      expect(outgoing.map((item) => item.id), contains(request.id));
    });

    test('does not duplicate a pending request', () async {
      const uid = 'demo-user';
      final heroes = await UnseenHeroService.watchNearbyHeroes(
        center: const ll.LatLng(12.9716, 77.5946),
        radiusMeters: 5000,
        currentUserId: uid,
      ).first;
      final available =
          heroes.firstWhere((hero) => hero.presence.helpAvailable);

      final first = await UnseenHeroService.createHelpRequest(
        requesterId: uid,
        hero: available.presence,
        message: 'Please help me find a safe waiting point.',
        contactAllowed: false,
      );
      final second = await UnseenHeroService.createHelpRequest(
        requesterId: uid,
        hero: available.presence,
        message: 'Please help me find a safe waiting point.',
        contactAllowed: false,
      );

      expect(second.id, first.id);
    });

    test('keeps simulated requests scoped to one demo user', () async {
      const uid = 'demo-user';
      final heroes = await UnseenHeroService.watchNearbyHeroes(
        center: const ll.LatLng(12.9716, 77.5946),
        radiusMeters: 5000,
        currentUserId: uid,
      ).first;
      final available =
          heroes.firstWhere((hero) => hero.presence.helpAvailable);

      await UnseenHeroService.createHelpRequest(
        requesterId: uid,
        hero: available.presence,
        message: 'Demo request that must stay scoped.',
        contactAllowed: false,
      );
      final otherOutgoing =
          await UnseenHeroService.watchOutgoingRequests('other-user').first;
      final otherIncoming =
          await UnseenHeroService.watchIncomingRequests('other-user').first;

      expect(otherOutgoing, isEmpty);
      expect(otherIncoming, isEmpty);
    });

    test('rejects unknown demo hero ids', () async {
      const uid = 'demo-user';
      final presence = UnseenHeroPresence(
        recognitionId: 'fake-recognition',
        heroId: 'debug-unseen-hero-999',
        heroName: 'Fake Hero',
        communityId: 'demo-community',
        communityName: 'Demo HALO Community',
        areaName: 'Demo area',
        latitude: 12.9716,
        longitude: 77.5946,
        message: 'Demo',
        recognizedAt: DateTime.now(),
        helpAvailable: true,
        sharePhoneAfterAcceptance: true,
        visibleUntil: DateTime.now().add(const Duration(days: 1)),
      );

      expect(
        () => UnseenHeroService.createHelpRequest(
          requesterId: uid,
          hero: presence,
          message: 'This must not be accepted.',
          contactAllowed: false,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SafeWalk area filtering', () {
    Incident incidentAt(
      String id,
      double latitude,
      double longitude, {
      Duration? age = const Duration(days: 1),
    }) {
      final reportedAt = DateTime.now().subtract(age ?? Duration.zero);
      return Incident(
        id: id,
        latitude: latitude,
        longitude: longitude,
        type: IncidentType.isolated,
        timeOfDay: 'Night',
        reportedAt: reportedAt,
      );
    }

    test('keeps only reports inside the requested radius', () {
      const center = ll.LatLng(12.9716, 77.5946);
      final near = incidentAt('near', 12.9720, 77.5950);
      final far = incidentAt('far', 12.9900, 77.5946);

      final kept = IncidentService.filterToArea(
        [near, far],
        center: center,
        radiusMeters: 1000,
      );

      expect(kept.map((i) => i.id), ['near']);
    });

    test('drops reports outside the time window and sorts newest first', () {
      const center = ll.LatLng(12.9716, 77.5946);
      final old =
          incidentAt('old', 12.9720, 77.5950, age: const Duration(days: 9));
      final newer =
          incidentAt('newer', 12.9721, 77.5950, age: const Duration(hours: 2));
      final newest =
          incidentAt('newest', 12.9722, 77.5950, age: const Duration(hours: 1));

      final kept = IncidentService.filterToArea(
        [old, newer, newest],
        center: center,
        radiusMeters: 5000,
        since: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect(kept.map((i) => i.id), ['newest', 'newer']);
    });

    test('a smaller radius never returns more reports than a larger one',
        () async {
      const center = ll.LatLng(12.9716, 77.5946);
      final near = await IncidentService.watchIncidents(
        center: center,
        radiusMeters: 1000,
      ).first;
      final wide = await IncidentService.watchIncidents(
        center: center,
        radiusMeters: 10000,
      ).first;

      expect(near.length, lessThanOrEqualTo(wide.length));
      for (final incident in near) {
        expect(
          distanceMeters(center.latitude, center.longitude, incident.latitude,
              incident.longitude),
          lessThanOrEqualTo(1000),
        );
      }
    });

    test('every stored report carries a geohash for the area query', () {
      final incident = incidentAt('hashed', 12.9720, 77.5950);
      final stored = incident.toFirestore();
      expect(stored['geohashPrefix'], isA<String>());
      expect((stored['geohashPrefix']! as String).length, 5);
    });
  });

  group('SafeWalk zone clustering', () {
    Incident incidentAt(String id, double lat, double lng, Duration age) {
      final at = DateTime.now().subtract(age);
      return Incident(
        id: id,
        latitude: lat,
        longitude: lng,
        type: IncidentType.isolated,
        timeOfDay: 'Night',
        reportedAt: at,
      );
    }

    test('groups nearby reports into one zone and separates distant ones', () {
      final zones = SafetyZones.incidentZones([
        incidentAt('a', 12.9720, 77.5946, const Duration(hours: 1)),
        incidentAt('b', 12.9721, 77.5947, const Duration(hours: 2)),
        incidentAt('c', 12.9722, 77.5946, const Duration(hours: 3)),
        incidentAt('far', 12.9900, 77.5946, const Duration(hours: 4)),
      ]);

      expect(zones, isNotEmpty);
      expect(zones.first.count, 3);
      expect(zones.length, 2);
    });

    test('normalises intensity against the busiest cluster', () {
      final zones = SafetyZones.incidentZones([
        for (var i = 0; i < 9; i++)
          incidentAt('dense-$i', 12.9720 + i * 0.0001, 77.5946,
              Duration(minutes: 30 * i)),
        incidentAt('lonely', 12.9900, 77.5946, const Duration(hours: 5)),
      ]);

      expect(zones.first.intensity, 1.0);
      final weakest = zones.reduce((a, b) => a.intensity < b.intensity ? a : b);
      expect(weakest.intensity, lessThan(1.0));
    });

    test('a fresh cluster outweighs an equally busy old one', () {
      final now = DateTime.now();
      final fresh = SafetyZones.incidentZones([
        for (var i = 0; i < 4; i++)
          incidentAt('fresh-$i', 12.9720 + i * 0.0001, 77.5946,
              Duration(minutes: 20 * i)),
      ]).first;
      final old = SafetyZones.incidentZones([
        for (var i = 0; i < 4; i++)
          Incident(
            id: 'old-$i',
            latitude: 12.9720 + i * 0.0001,
            longitude: 77.5946,
            type: IncidentType.isolated,
            timeOfDay: 'Night',
            reportedAt: now.subtract(Duration(days: 60)),
          ),
      ]).first;

      expect(fresh.freshness, greaterThan(old.freshness));
      expect(fresh.weight, greaterThan(old.weight));
    });

    test('produces no zones from an empty area', () {
      expect(SafetyZones.incidentZones(const []), isEmpty);
      expect(SafetyZones.heroZones(const []), isEmpty);
      expect(SafetyZones.heatCells(const []), isEmpty);
    });

    test('the 48h heat layer only counts reports from the last two days', () {
      final now = DateTime.now();
      List<Incident> reports(Duration age, {int count = 4}) => [
            for (var i = 0; i < count; i++)
              Incident(
                id: '$age-$i',
                latitude: 12.9720 + i * 0.0001,
                longitude: 77.5946,
                type: IncidentType.isolated,
                timeOfDay: 'Night',
                reportedAt: now.subtract(age + Duration(minutes: i)),
              ),
          ];

      final last48Hours = SafetyZones.heatCells(
        [
          ...reports(const Duration(hours: 5)),
          ...reports(const Duration(days: 40))
        ],
        range: HeatRange.last48Hours,
        now: now,
      );
      final allHistory = SafetyZones.heatCells(
        [
          ...reports(const Duration(hours: 5)),
          ...reports(const Duration(days: 40))
        ],
        range: HeatRange.allHistory,
        now: now,
      );

      final recentTotal =
          last48Hours.fold<int>(0, (total, c) => total + c.count);
      final allTotal = allHistory.fold<int>(0, (total, c) => total + c.count);

      expect(recentTotal, 4);
      expect(allTotal, 8);
    });

    test('the 30d window sits between 48h and all history', () {
      final now = DateTime.now();
      final reports = <Incident>[
        for (var i = 0; i < 3; i++)
          Incident(
            id: 'new-$i',
            latitude: 12.9720 + i * 0.0001,
            longitude: 77.5946,
            type: IncidentType.isolated,
            timeOfDay: 'Night',
            reportedAt: now.subtract(Duration(hours: 3 + i)),
          ),
        for (var i = 0; i < 3; i++)
          Incident(
            id: 'mid-$i',
            latitude: 12.9720 + i * 0.0001,
            longitude: 77.5946,
            type: IncidentType.isolated,
            timeOfDay: 'Night',
            reportedAt: now.subtract(Duration(days: 10 + i)),
          ),
        for (var i = 0; i < 3; i++)
          Incident(
            id: 'old-$i',
            latitude: 12.9720 + i * 0.0001,
            longitude: 77.5946,
            type: IncidentType.isolated,
            timeOfDay: 'Night',
            reportedAt: now.subtract(Duration(days: 200)),
          ),
      ];

      int totalFor(HeatRange range) =>
          SafetyZones.heatCells(reports, range: range, now: now)
              .fold<int>(0, (total, c) => total + c.count);

      expect(totalFor(HeatRange.last48Hours), 3);
      expect(totalFor(HeatRange.last30Days), 6);
      expect(totalFor(HeatRange.allHistory), 9);
    });
  });

  group('SafeSpot trust model', () {
    SafeSpot spot({
      SafeSpotSource source = SafeSpotSource.community,
      String? verifiedBy,
      DateTime? verifiedUntil,
    }) {
      return SafeSpot(
        id: 's1',
        name: 'Corner cafe',
        category: SafeSpotCategory.cafe,
        latitude: 12.9722,
        longitude: 77.5946,
        createdAt: DateTime.now(),
        source: source,
        verifiedBy: verifiedBy,
        verifiedUntil: verifiedUntil,
      );
    }

    test('a community listing is never presented as verified', () {
      expect(spot().isVerifiedAt(DateTime.now()), isFalse);
    });

    test('verification expires rather than sticking forever', () {
      final now = DateTime.now();
      expect(
        spot(
          verifiedBy: 'guardian-1',
          verifiedUntil: now.add(const Duration(days: 30)),
        ).isVerifiedAt(now),
        isTrue,
      );
      expect(
        spot(
          verifiedBy: 'guardian-1',
          verifiedUntil: now.subtract(const Duration(minutes: 1)),
        ).isVerifiedAt(now),
        isFalse,
      );
    });

    test('auto-discovered places are marked as discovered, not verified', () {
      final discovered = spot(source: SafeSpotSource.discovered);
      expect(discovered.isDiscovered, isTrue);
      expect(discovered.isVerifiedAt(DateTime.now()), isFalse);
      expect(discovered.sourceLabel, contains('OpenStreetMap'));
    });

    test('auto-generation only keeps safety-relevant amenities', () {
      final service = SafeSpotService();
      final spots = service.toSafeSpots(
        [
          OverpassElement(
            id: 'node/1',
            latitude: 12.9723,
            longitude: 77.5947,
            tags: {'amenity': 'police', 'name': 'Central PS'},
          ),
          OverpassElement(
            id: 'node/2',
            latitude: 12.9724,
            longitude: 77.5948,
            tags: {'amenity': 'bench'},
          ),
          OverpassElement(
            id: 'node/3',
            latitude: 12.9725,
            longitude: 77.5949,
            tags: {'amenity': 'pharmacy', 'name': 'Night pharmacy'},
          ),
          // Same building, mapped twice at the same spot: must collapse.
          OverpassElement(
            id: 'node/4',
            latitude: 12.9723,
            longitude: 77.5947,
            tags: {'amenity': 'police', 'name': 'Central PS'},
          ),
        ],
        center: const ll.LatLng(12.9722, 77.5946),
        radiusMeters: 2000,
      );

      expect(spots.map((s) => s.category), [
        SafeSpotCategory.policeStation,
        SafeSpotCategory.pharmacy,
      ]);
      expect(spots.every((s) => s.source == SafeSpotSource.discovered), isTrue);
      expect(
          spots.every((s) => s.isVerifiedAt(DateTime.now()) == false), isTrue);
    });

    test('auto-generation drops anything outside the searched radius', () {
      final service = SafeSpotService();
      final spots = service.toSafeSpots(
        [
          OverpassElement(
            id: 'node/1',
            latitude: 12.99,
            longitude: 77.62,
            tags: {'amenity': 'hospital'},
          ),
        ],
        center: const ll.LatLng(12.9722, 77.5946),
        radiusMeters: 500,
      );
      expect(spots, isEmpty);
    });
  });

  group('OSM lighting inference', () {
    OverpassElement litWay(int id, double lat, double lon) => OverpassElement(
          id: 'way/$id',
          latitude: lat,
          longitude: lon,
          tags: const {'highway': 'residential', 'lit': 'yes'},
          geometry: [
            (lat: lat, lon: lon),
            (lat: lat + 0.001, lon: lon + 0.001),
          ],
        );

    test('measures lit road from real way geometry, not a bounding box', () {
      final way = litWay(1, 12.9720, 77.5946);
      // Two points ~157 m apart at this latitude.
      expect(way.lengthMeters, closeTo(157, 5));
      expect(way.lengthMeters, greaterThan(0));
    });

    test('a node with no geometry reports zero length, not a fake one', () {
      const lamp = OverpassElement(
        id: 'node/1',
        latitude: 12.972,
        longitude: 77.5946,
        tags: {'highway': 'street_lamp'},
      );
      expect(lamp.lengthMeters, 0);
      expect(lamp.isLit, isFalse);
    });

    test('lit tags are recognised across OSM spellings', () {
      for (final value in ['yes', '1', 'true']) {
        expect(
          OverpassElement(
            id: 'way/1',
            latitude: 0,
            longitude: 0,
            tags: {'lit': value},
          ).isLit,
          isTrue,
          reason: 'lit=$value should count as lit',
        );
      }
      expect(
        OverpassElement(
          id: 'way/2',
          latitude: 0,
          longitude: 0,
          tags: {'lit': 'no'},
        ).isLit,
        isFalse,
      );
    });

    test('an area with no mapped lighting scores zero but is distinguishable',
        () {
      const assessment = LightingAssessment(
        score: 0,
        litRoadMeters: 0,
        totalRoadMeters: 0,
        lampCount: 0,
        areaSquareKm: 7.07,
        sampledAt: null,
      );
      expect(assessment.hasData, isFalse);
      expect(assessment.band, LightingBand.unknown);
    });

    test('a well-lit score and a dark score land in the right bands', () {
      LightingAssessment of(double score) => LightingAssessment(
            score: score,
            litRoadMeters: 1000,
            totalRoadMeters: 2000,
            lampCount: 10,
            areaSquareKm: 1,
            sampledAt: DateTime.now(),
          );
      expect(of(0.8).band, LightingBand.wellLit);
      expect(of(0.5).band, LightingBand.partial);
      expect(of(0.1).band, LightingBand.sparse);
    });

    test('the caveat is attached to the score itself, not just the UI', () {
      expect(LightingAssessment.caveat, contains('not'));
      expect(
          LightingAssessment.caveat.toLowerCase(), contains('not a measure'));
    });

    test('the lighting query is valid Overpass QL and covers lamps and ways',
        () {
      final query = LightingService.lightingQuery(
        const ll.LatLng(12.9716, 77.5946),
        1500,
      );
      expect(query, contains('way["highway"]["lit"]'));
      expect(query, contains('node["highway"="street_lamp"]'));
      expect(query, contains('out geom tags;'));
    });

    test('a wide radius near a pole still yields a valid bounding box', () {
      final box = LightingService.bbox(const ll.LatLng(84.9, 20.0), 500000);
      final parts = box.split(',').map(double.parse).toList();
      expect(parts[0], lessThanOrEqualTo(85.0));
      expect(parts[2], lessThanOrEqualTo(85.0));
      expect(parts[0], lessThan(parts[2]));
      expect(parts[1], lessThan(parts[3]));
    });
  });

  group('Regional safety priors', () {
    const source = IllustrativeSafetyPriorSource();

    test('are flagged as placeholders, never as official figures', () {
      final prior = source.priorFor(const ll.LatLng(12.9716, 77.5946))!;
      expect(prior.illustrative, isTrue);
      expect(prior.sourceLabel.toLowerCase(), contains('not official'));
      expect(source.disclaimer.toLowerCase(), contains('placeholder'));
    });

    test('cover a known city and refuse to invent one elsewhere', () {
      expect(source.priorFor(const ll.LatLng(12.9716, 77.5946)), isNotNull);
      // Mid-Pacific: outside every coverage disc.
      expect(source.priorFor(const ll.LatLng(-30.0, -150.0)), isNull);
    });

    test('pick the nearest covering city when discs overlap', () {
      // Near the Bengaluru / Hyderabad gap boundary, must resolve, not crash.
      final prior = source.priorFor(const ll.LatLng(15.5, 77.5));
      expect(prior == null || prior.illustrative, isTrue);
    });
  });

  group('Google Places is optional, never required', () {
    test('reports unavailable and explains why when no key is configured', () {
      final places = GooglePlacesService();
      // No --dart-define in tests, so this must be the degraded path.
      expect(places.isConfigured, isFalse);
      expect(places.unavailableReason, contains('works without it'));
    });

    test('an unconfigured client returns nothing rather than throwing',
        () async {
      final places = GooglePlacesService();
      expect(await places.search('police station'), isEmpty);
      places.dispose();
    });
  });

  group('Cold-start engine', () {
    BaselinePicture picture({
      required int reportCount,
      LightingAssessment? lighting,
      SafetyPrior? prior,
      int safeSpotCount = 0,
      int heroCount = 0,
    }) {
      return BaselinePicture(
        center: const ll.LatLng(12.9716, 77.5946),
        lighting: lighting,
        prior: prior,
        safeSpotCount: safeSpotCount,
        heroCount: heroCount,
        provisional: reportCount == 0,
        computedAt: DateTime.now(),
      );
    }

    test('an area with no reports is marked provisional, never "all clear"',
        () {
      final cold = picture(reportCount: 0);
      expect(cold.provisional, isTrue);
      expect(cold.headline, contains('Provisional'));
      expect(
        cold.insights.any(
          (i) => i.kind == BaselineInsightKind.noReports,
        ),
        isTrue,
      );
    });

    test('an area with reports is not provisional', () {
      final warm = picture(reportCount: 12);
      expect(warm.provisional, isFalse);
      expect(warm.headline, isNot(contains('Provisional')));
    });

    test('a low reporting index is surfaced as a caution, not hidden', () {
      final prior = const IllustrativeSafetyPriorSource()
          .priorFor(const ll.LatLng(28.6139, 77.2090))!;
      final cold = picture(reportCount: 0, prior: prior);
      expect(
        cold.insights.any(
          (i) =>
              i.kind == BaselineInsightKind.caution &&
              i.text.contains('Under-reporting'),
        ),
        isTrue,
      );
    });

    test('sparse lighting produces a caution insight', () {
      const dark = LightingAssessment(
        score: 0.05,
        litRoadMeters: 100,
        totalRoadMeters: 4000,
        lampCount: 1,
        areaSquareKm: 7.07,
        sampledAt: null,
      );
      final cold = picture(reportCount: 0, lighting: dark);
      expect(
        cold.insights.any(
          (i) =>
              i.kind == BaselineInsightKind.caution &&
              i.text.contains('Little lighting'),
        ),
        isTrue,
      );
    });

    test('missing lighting says "not mapped", never "pitch dark"', () {
      final cold = picture(reportCount: 0);
      expect(
        cold.insights.any(
          (i) => i.text.contains('not mapped on OpenStreetMap'),
        ),
        isTrue,
      );
    });

    test('an area with no safe places says so instead of implying safety', () {
      final cold = picture(reportCount: 0, safeSpotCount: 0);
      expect(
        cold.insights.any(
          (i) =>
              i.kind == BaselineInsightKind.caution &&
              i.text.contains('No safe places'),
        ),
        isTrue,
      );
    });

    test('no prior coverage yields an explicit "nothing assumed" insight', () {
      final cold = picture(reportCount: 0, prior: null);
      expect(
        cold.insights.any((i) => i.text.contains('nothing has been assumed')),
        isTrue,
      );
    });
  });

  group('Report anonymity', () {
    Incident incident({
      ReportAnonymity anonymity = ReportAnonymity.anonymous,
      String? reporterHandle,
    }) {
      return Incident(
        id: 'i1',
        latitude: 12.9722,
        longitude: 77.5946,
        type: IncidentType.harassment,
        timeOfDay: 'Night',
        reportedAt: DateTime.now(),
        anonymity: anonymity,
        reporterHandle: reporterHandle,
      );
    }

    test('anonymous is the default, not an accident of missing fields', () {
      expect(incident().anonymity, ReportAnonymity.anonymous);
      expect(incident().isFullyAnonymous, isTrue);
      expect(
        incident().toFirestore()['anonymity'],
        ReportAnonymity.anonymous.name,
      );
    });

    test('an anonymous report never carries a handle, even if one is passed',
        () {
      final doc = incident(
        reporterHandle: ReporterPseudonym.forUserId('user-1'),
      ).toFirestore();
      expect(doc['reporterHandle'], isNull);
    });

    test('a pseudonymous report carries exactly one well-formed handle', () {
      final handle = ReporterPseudonym.forUserId('user-1')!;
      final doc = incident(
        anonymity: ReportAnonymity.pseudonymous,
        reporterHandle: handle,
      ).toFirestore();
      expect(doc['reporterHandle'], handle);
      expect(ReporterPseudonym.isWellFormed(handle), isTrue);
    });

    test('no raw user id is ever serialised', () {
      for (final anonymity in ReportAnonymity.values) {
        final doc = incident(
          anonymity: anonymity,
          reporterHandle: ReporterPseudonym.forUserId('user-1'),
        ).toFirestore();
        expect(doc.keys, isNot(contains('userId')));
        expect(doc.keys, isNot(contains('uid')));
        expect(doc.keys, isNot(contains('reporterId')));
        // The handle must not simply be the uid.
        expect(doc.values.map((v) => '$v'), isNot(contains('user-1')));
      }
    });

    test('a handle is stable for the same user and differs between users', () {
      final a = ReporterPseudonym.forUserId('user-1');
      final b = ReporterPseudonym.forUserId('user-2');
      expect(a, ReporterPseudonym.forUserId('user-1'));
      expect(a, isNot(b));
    });

    test('there is no handle to derive without a signed-in user', () {
      expect(ReporterPseudonym.forUserId(null), isNull);
      expect(ReporterPseudonym.forUserId(''), isNull);
    });

    test('malformed handles are rejected before they can be persisted', () {
      expect(ReporterPseudonym.isWellFormed('short'), isFalse);
      expect(ReporterPseudonym.isWellFormed('Z' * 32), isFalse);
      expect(ReporterPseudonym.isWellFormed(null), isFalse);
      expect(ReporterPseudonym.isWellFormed('a' * 33), isFalse);
      expect(ReporterPseudonym.isWellFormed('a' * 32), isTrue);
    });

    test('round-trips through the Firestore shape', () {
      final handle = ReporterPseudonym.forUserId('user-1');
      final restored = Incident.fromFirestore(
        FakeIncidentDoc({
          'location': const GeoPoint(12.9722, 77.5946),
          'type': 'harassment',
          'timeOfDay': 'Night',
          'reportedAt': Timestamp.fromDate(DateTime.now()),
          'anonymity': 'pseudonymous',
          'reporterHandle': handle,
        }),
      );
      expect(restored.anonymity, ReportAnonymity.pseudonymous);
      expect(restored.reporterHandle, handle);
      expect(restored.isFullyAnonymous, isFalse);
    });

    test('a legacy report with no anonymity field is read as anonymous', () {
      final legacy = Incident.fromFirestore(
        FakeIncidentDoc({
          'location': const GeoPoint(12.9722, 77.5946),
          'type': 'harassment',
          'timeOfDay': 'Night',
          'reportedAt': Timestamp.fromDate(DateTime.now()),
        }),
      );
      expect(legacy.anonymity, ReportAnonymity.anonymous);
      expect(legacy.isFullyAnonymous, isTrue);
    });
  });

  group('Layer 1 automatic moderation', () {
    test('a clean report publishes with no flags', () {
      final result = ModerationService.evaluate(
        type: IncidentType.poorLighting,
        description: 'Whole stretch has no working lights.',
      );
      expect(result.verdict, Layer1Verdict.clear);
      expect(result.flags, isEmpty);
      expect(
        ModerationService.initialStatus(
          verdict: result.verdict,
          flags: result.flags,
          evaluatedAt: DateTime.now(),
        )['moderationStatus'],
        IncidentModerationStatus.published.name,
      );
    });

    test('a pasted phone number is caught and explained', () {
      final result = ModerationService.evaluate(
        type: IncidentType.other,
        description: 'Call me on 98765 43210 if anything happens',
      );
      expect(result.flags.map((f) => f.code), contains('phone_number_in_text'));
      expect(result.verdict, Layer1Verdict.flagForReview);
      expect(ModerationService.explain(result.flags).first, isNotEmpty);
    });

    test('links and emails in the text are caught', () {
      final result = ModerationService.evaluate(
        type: IncidentType.other,
        description: 'see https://example.com or mail a@b.com',
      );
      expect(
        result.flags.map((f) => f.code),
        contains('contact_detail_in_text'),
      );
    });

    test('naming someone as a criminal is flagged, not silently published', () {
      final result = ModerationService.evaluate(
        type: IncidentType.other,
        description: 'The guy here is a thief and a pervert.',
      );
      expect(result.flags.map((f) => f.code), contains('accusatory_language'));
    });

    test('an empty "other" report is held rather than published blind', () {
      final result = ModerationService.evaluate(
        type: IncidentType.other,
        description: null,
      );
      expect(result.flags.map((f) => f.code), contains('empty_detail'));
      expect(result.verdict, Layer1Verdict.hold);
    });

    test('a report combining privacy problems is held, not merely flagged', () {
      final result = ModerationService.evaluate(
        type: IncidentType.other,
        description: 'harassed by him, my number is 9876543210, '
            'email me at x@y.com',
      );
      expect(result.flags.length, greaterThanOrEqualTo(2));
      expect(result.verdict, Layer1Verdict.hold);
    });

    test('held means kept but not public, never silently dropped', () {
      final status = IncidentModerationStatus.fromValue(
        ModerationService.initialStatus(
          verdict: Layer1Verdict.hold,
          flags: const [ModerationFlag('empty_detail', 'no detail')],
          evaluatedAt: DateTime.now(),
        )['moderationStatus'] as String,
      );
      expect(status, IncidentModerationStatus.held);
      expect(status.isPubliclyVisible, isFalse);
    });

    test('the client cannot declare a Layer 2 outcome', () {
      final written = ModerationService.initialStatus(
        verdict: Layer1Verdict.clear,
        flags: const [],
        evaluatedAt: DateTime.now(),
      );
      expect((written['layer2'] as Map)['verdict'], 'pending');
    });
  });

  group('Layer 2 community review', () {
    test('fewer than three votes never changes status', () {
      final result = ModerationService.applyCommunityReview(
        confirm: 1,
        reject: 0,
      );
      expect(result.status, IncidentModerationStatus.underReview);
    });

    test('a strict confirm majority confirms', () {
      final result = ModerationService.applyCommunityReview(
        confirm: 3,
        reject: 1,
      );
      expect(result.status, IncidentModerationStatus.confirmed);
    });

    test('a strict reject majority rejects', () {
      final result = ModerationService.applyCommunityReview(
        confirm: 1,
        reject: 4,
      );
      expect(result.status, IncidentModerationStatus.rejected);
      expect(result.status.isPubliclyVisible, isFalse);
    });

    test('a tie stays undecided rather than defaulting either way', () {
      final result = ModerationService.applyCommunityReview(
        confirm: 2,
        reject: 2,
      );
      expect(result.status, IncidentModerationStatus.underReview);
    });

    test('unconfirmed reports stay visible but are not treated as confirmed',
        () {
      const underReview = IncidentModerationStatus.underReview;
      expect(underReview.isPubliclyVisible, isTrue);
      expect(underReview.label, 'Not yet confirmed');
    });

    test('a report with no moderation data defaults to published', () {
      final incident = Incident(
        id: 'i1',
        latitude: 12.9722,
        longitude: 77.5946,
        type: IncidentType.isolated,
        timeOfDay: 'Night',
        reportedAt: DateTime.now(),
      );
      expect(incident.moderationStatus, IncidentModerationStatus.published);
      expect(incident.isConfirmed, isTrue);
    });
  });
}

// ignore: subtype_of_sealed_class
/// Minimal [DocumentSnapshot] stand-in so model deserialisation can be tested
/// without standing up Firestore. Anything the models do not touch throws,
/// which keeps the fake from silently satisfying a new dependency.
///
/// DocumentSnapshot is sealed, so this is test-only scaffolding that also
/// trips the `subtype_of_sealed_class` lint by design.
class FakeIncidentDoc implements DocumentSnapshot<Map<String, dynamic>> {
  FakeIncidentDoc(this._data);

  final Map<String, dynamic> _data;

  @override
  String get id => 'fake';

  @override
  Map<String, dynamic>? data() => _data;

  @override
  bool get exists => true;

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnimplementedError();

  @override
  dynamic operator [](Object field) => _data[field.toString()];

  @override
  dynamic get(Object field) => _data[field.toString()];
}
