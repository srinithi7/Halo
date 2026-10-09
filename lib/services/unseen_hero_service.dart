import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/unseen_hero.dart';
import '../utils/geo.dart';

class UnseenHeroService {
  UnseenHeroService._();

  static const _settings = 'settings';
  static const _presenceCollection = 'unseenHeroLocations';
  static const _requestCollection = 'heroHelpRequests';
  static const _contactGrantCollection = 'helpContactGrants';
  static const _debugHeroIds = {
    'debug-unseen-hero-0',
    'debug-unseen-hero-1',
    'debug-unseen-hero-2',
  };
  static _DebugUnseenHeroStore? _debugStore;

  static _DebugUnseenHeroStore get _debug {
    return _debugStore ??= _DebugUnseenHeroStore();
  }

  static bool _isDebugHeroId(String heroId) => _debugHeroIds.contains(heroId);

  static DocumentReference<Map<String, dynamic>> _settingsRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('unseenHeroSettings')
        .doc(_settings);
  }

  static CollectionReference<Map<String, dynamic>> _presences() {
    return FirebaseFirestore.instance.collection(_presenceCollection);
  }

  static CollectionReference<Map<String, dynamic>> _requests() {
    return FirebaseFirestore.instance.collection(_requestCollection);
  }

  static Future<UnseenHeroSettings> getSettings(String uid) async {
    if (kDebugMode) return _debug.settingsFor(uid);
    final snapshot = await _settingsRef(uid).get();
    return snapshot.exists
        ? UnseenHeroSettings.fromFirestore(snapshot)
        : UnseenHeroSettings.defaults();
  }

  static Future<void> saveSettings(
    String uid,
    UnseenHeroSettings settings,
  ) async {
    final normalized = settings.copyWith(
      acceptingHelpRequests:
          settings.visibleOnSafeWalk ? settings.acceptingHelpRequests : false,
      sharePhoneAfterAcceptance: settings.visibleOnSafeWalk
          ? settings.sharePhoneAfterAcceptance
          : false,
    );
    if (kDebugMode) {
      _debug.saveSettings(uid, normalized);
      return;
    }
    await _settingsRef(uid).set(normalized.toFirestore());
  }

  static Stream<List<NearbyUnseenHero>> watchNearbyHeroes({
    required ll.LatLng center,
    required double radiusMeters,
    required String currentUserId,
  }) async* {
    final bounds = geohashBounds(
      center.latitude,
      center.longitude,
      radiusMeters,
    );

    if (kDebugMode) {
      yield _debugNearbyHeroes(center, radiusMeters, currentUserId);
      return;
    }

    try {
      await for (final snapshot in _presences()
          .where('geohashPrefix', isGreaterThanOrEqualTo: bounds.lower)
          .where('geohashPrefix', isLessThanOrEqualTo: bounds.upper)
          .snapshots()) {
        final now = DateTime.now();
        final heroes = <NearbyUnseenHero>[];
        for (final doc in snapshot.docs) {
          final presence = UnseenHeroPresence.fromFirestore(doc);
          if (presence.heroId == currentUserId ||
              !presence.visibleUntil.isAfter(now)) {
            continue;
          }
          final distance = distanceMeters(
            center.latitude,
            center.longitude,
            presence.latitude,
            presence.longitude,
          );
          if (distance <= radiusMeters) {
            heroes.add(
              NearbyUnseenHero(
                presence: presence,
                distanceMeters: distance,
              ),
            );
          }
        }
        heroes.sort((a, b) {
          if (a.presence.helpAvailable != b.presence.helpAvailable) {
            return a.presence.helpAvailable ? -1 : 1;
          }
          return a.distanceMeters.compareTo(b.distanceMeters);
        });
        yield heroes;
      }
    } catch (_) {
      rethrow;
    }
  }

  static List<NearbyUnseenHero> _debugNearbyHeroes(
    ll.LatLng center,
    double radiusMeters,
    String currentUserId,
  ) {
    final now = DateTime.now();
    const samples = [
      (
        'Demo Asha',
        'Helped a stranded student find the right bus stop.',
        true,
      ),
      (
        'Demo Ravi',
        'Checked on an elderly neighbour during the power outage.',
        false,
      ),
      (
        'Demo Meera',
        'Returned a lost wallet and stayed until its owner arrived.',
        true,
      ),
    ];
    final heroes = <NearbyUnseenHero>[];

    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      final heroId = 'debug-unseen-hero-$index';
      if (heroId == currentUserId) continue;
      final latitude = center.latitude + (index - 1) * 0.0025;
      final longitude = center.longitude + (1 - index) * 0.0018;
      final presence = UnseenHeroPresence(
        recognitionId: 'debug-recognition-$index',
        heroId: heroId,
        heroName: sample.$1,
        communityId: 'debug-community',
        communityName: 'Demo HALO Community',
        areaName: 'Demo area near your search',
        latitude: latitude,
        longitude: longitude,
        message: sample.$2,
        recognizedAt: now.subtract(const Duration(hours: 2)),
        helpAvailable: sample.$3,
        sharePhoneAfterAcceptance: sample.$3,
        visibleUntil: now.add(const Duration(days: 30)),
      );
      final distance = distanceMeters(
        center.latitude,
        center.longitude,
        latitude,
        longitude,
      );
      if (distance <= radiusMeters) {
        heroes.add(
          NearbyUnseenHero(presence: presence, distanceMeters: distance),
        );
      }
    }

    heroes.sort((a, b) {
      if (a.presence.helpAvailable != b.presence.helpAvailable) {
        return a.presence.helpAvailable ? -1 : 1;
      }
      return a.distanceMeters.compareTo(b.distanceMeters);
    });
    return heroes;
  }

  static Future<HeroHelpRequest> createHelpRequest({
    required String requesterId,
    required UnseenHeroPresence hero,
    required String message,
    required bool contactAllowed,
  }) async {
    final trimmed = message.trim();
    if (trimmed.length < 5 || trimmed.length > 500) {
      throw StateError('Write between 5 and 500 characters.');
    }
    if (requesterId == hero.heroId) {
      throw StateError('You cannot send a request to yourself.');
    }
    if (!hero.helpAvailable) {
      throw StateError('This Unseen Hero is not accepting requests right now.');
    }
    if (kDebugMode && hero.heroId.startsWith('debug-unseen-hero-')) {
      if (!_isDebugHeroId(hero.heroId)) {
        throw StateError('Unknown demo Unseen Hero.');
      }
      return _debug.createRequest(
        requesterId: requesterId,
        hero: hero,
        message: trimmed,
        contactAllowed: contactAllowed,
      );
    }

    final firestore = FirebaseFirestore.instance;
    final requesterProfile =
        await firestore.collection('users').doc(requesterId).get();
    final requesterName =
        requesterProfile.data()?['name'] as String? ?? 'A HALO user';
    final duplicate = await _requests()
        .where('requesterId', isEqualTo: requesterId)
        .where('heroId', isEqualTo: hero.heroId)
        .where('recognitionId', isEqualTo: hero.recognitionId)
        .where('status', isEqualTo: HeroHelpRequestStatus.pending.name)
        .limit(1)
        .get();
    if (duplicate.docs.isNotEmpty) {
      return HeroHelpRequest.fromFirestore(duplicate.docs.first);
    }

    final request = HeroHelpRequest(
      id: '',
      heroId: hero.heroId,
      heroName: hero.heroName,
      recognitionId: hero.recognitionId,
      communityId: hero.communityId,
      communityName: hero.communityName,
      areaName: hero.areaName,
      requesterId: requesterId,
      requesterName: requesterName,
      message: trimmed,
      contactAllowed: contactAllowed,
      status: HeroHelpRequestStatus.pending,
      createdAt: DateTime.now(),
    );
    final ref = await _requests().add(request.toFirestore());
    return HeroHelpRequest.fromFirestore(
      await ref.get(),
    );
  }

  static Stream<List<HeroHelpRequest>> watchIncomingRequests(String uid) {
    if (kDebugMode) return _debug.watchRequests(uid, incoming: true);
    return _requests()
        .where('heroId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(HeroHelpRequest.fromFirestore)
            .toList(growable: false));
  }

  static Stream<List<HeroHelpRequest>> watchOutgoingRequests(String uid) {
    if (kDebugMode) return _debug.watchRequests(uid, incoming: false);
    return _requests()
        .where('requesterId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(HeroHelpRequest.fromFirestore)
            .toList(growable: false));
  }

  static Future<void> respondToHelpRequest({
    required String heroId,
    required HeroHelpRequest request,
    required HeroHelpRequestStatus status,
  }) async {
    if (request.heroId != heroId || !request.isPending) {
      throw StateError('This request can no longer be changed.');
    }
    if (status != HeroHelpRequestStatus.accepted &&
        status != HeroHelpRequestStatus.declined) {
      throw StateError('Unsupported request response.');
    }
    if (kDebugMode && _isDebugHeroId(heroId)) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw StateError('Sign in to respond to a demo request.');
      }
      _debug.respondToRequest(
        currentUserId: currentUser.uid,
        heroId: heroId,
        request: request,
        status: status,
      );
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final requestRef = _requests().doc(request.id);
    final update = <String, dynamic>{
      'status': status.name,
      'respondedAt': Timestamp.fromDate(DateTime.now()),
    };

    if (status == HeroHelpRequestStatus.declined) {
      await requestRef.update(update);
      return;
    }

    final heroProfile = await firestore.collection('users').doc(heroId).get();
    final heroSettings = await _settingsRef(heroId).get();
    final requesterProfile =
        await firestore.collection('users').doc(request.requesterId).get();
    final heroSharesPhone = heroSettings.exists &&
        heroSettings.data()?['sharePhoneAfterAcceptance'] == true;
    final heroPhone = heroSharesPhone
        ? (heroProfile.data()?['phoneNumber'] as String?) ?? ''
        : '';
    final requesterPhone = request.contactAllowed
        ? (requesterProfile.data()?['phoneNumber'] as String?) ?? ''
        : '';
    final batch = firestore.batch();
    batch.set(
      firestore.collection(_contactGrantCollection).doc(request.id),
      {
        'requestId': request.id,
        'heroId': heroId,
        'requesterId': request.requesterId,
        'heroPhone': heroPhone,
        'requesterPhone': requesterPhone,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      },
    );
    batch.update(requestRef, update);
    await batch.commit();
  }

  static Future<HeroContactGrant?> getContactGrant(String requestId) async {
    if (kDebugMode) return _debug.contactGrantFor(requestId);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_contactGrantCollection)
          .doc(requestId)
          .get();
      if (!snapshot.exists) return null;
      return HeroContactGrant.fromFirestore(snapshot);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  @visibleForTesting
  static void resetDebugState() {
    _debugStore?.dispose();
    _debugStore = null;
  }
}

class _DebugRequestEntry {
  _DebugRequestEntry({required this.request, required this.simulatorUid});

  HeroHelpRequest request;
  final String simulatorUid;
}

class _DebugUnseenHeroStore {
  final Map<String, _DebugRequestEntry> _requests = {};
  final Map<String, HeroContactGrant> _grants = {};
  final Map<String, UnseenHeroSettings> _settings = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _sequence = 0;

  UnseenHeroSettings settingsFor(String uid) {
    return _settings.putIfAbsent(uid, UnseenHeroSettings.defaults);
  }

  void saveSettings(String uid, UnseenHeroSettings settings) {
    _settings[uid] = settings;
  }

  HeroHelpRequest createRequest({
    required String requesterId,
    required UnseenHeroPresence hero,
    required String message,
    required bool contactAllowed,
  }) {
    for (final entry in _requests.values) {
      final request = entry.request;
      if (entry.simulatorUid == requesterId &&
          request.heroId == hero.heroId &&
          request.recognitionId == hero.recognitionId &&
          request.isPending) {
        return request;
      }
    }

    final authName = _safeAuthValue((user) => user.displayName);
    final request = HeroHelpRequest(
      id: 'debug-help-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      heroId: hero.heroId,
      heroName: hero.heroName,
      recognitionId: hero.recognitionId,
      communityId: hero.communityId,
      communityName: hero.communityName,
      areaName: hero.areaName,
      requesterId: requesterId,
      requesterName: authName ?? 'Demo Requester',
      message: message,
      contactAllowed: contactAllowed,
      status: HeroHelpRequestStatus.pending,
      createdAt: DateTime.now(),
    );
    _requests[request.id] = _DebugRequestEntry(
      request: request,
      simulatorUid: requesterId,
    );
    _emit();
    return request;
  }

  Stream<List<HeroHelpRequest>> watchRequests(
    String uid, {
    required bool incoming,
  }) async* {
    yield _requestsFor(uid, incoming: incoming);
    await for (final _ in _changes.stream) {
      yield _requestsFor(uid, incoming: incoming);
    }
  }

  List<HeroHelpRequest> _requestsFor(
    String uid, {
    required bool incoming,
  }) {
    final requests = _requests.values
        .where((entry) {
          if (incoming) {
            return entry.request.heroId == uid ||
                (entry.simulatorUid == uid &&
                    UnseenHeroService._isDebugHeroId(entry.request.heroId));
          }
          return entry.request.requesterId == uid;
        })
        .map((entry) => entry.request)
        .toList();
    requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(requests);
  }

  void respondToRequest({
    required String currentUserId,
    required String heroId,
    required HeroHelpRequest request,
    required HeroHelpRequestStatus status,
  }) {
    final entry = _requests[request.id];
    if (entry == null ||
        entry.simulatorUid != currentUserId ||
        entry.request.heroId != heroId ||
        !entry.request.isPending) {
      throw StateError('This demo request can no longer be changed.');
    }

    final updated = entry.request.copyWith(
      status: status,
      respondedAt: DateTime.now(),
    );
    if (status == HeroHelpRequestStatus.accepted) {
      final heroSharesPhone = heroId != 'debug-unseen-hero-1';
      final authPhone = _safeAuthValue((user) => user.phoneNumber);
      _grants[request.id] = HeroContactGrant(
        heroPhone: heroSharesPhone
            ? '+91 90000 0000${heroId.codeUnitAt(heroId.length - 1) - 48}'
            : '',
        requesterPhone: request.contactAllowed ? authPhone ?? '' : '',
      );
    }
    entry.request = updated;
    _emit();
  }

  HeroContactGrant? contactGrantFor(String requestId) {
    final entry = _requests[requestId];
    if (entry == null) return null;
    final currentUserId = _safeAuthValue((user) => user.uid);
    if (currentUserId != entry.simulatorUid) return null;
    return _grants[requestId];
  }

  T? _safeAuthValue<T>(T? Function(User user) read) {
    try {
      return read(FirebaseAuth.instance.currentUser!);
    } catch (_) {
      return null;
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _changes.close();
    _requests.clear();
    _grants.clear();
    _settings.clear();
  }
}
