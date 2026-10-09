import 'package:cloud_firestore/cloud_firestore.dart';

enum HeroHelpRequestStatus {
  pending,
  accepted,
  declined;

  static HeroHelpRequestStatus fromValue(String? value) {
    return HeroHelpRequestStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => HeroHelpRequestStatus.pending,
    );
  }
}

class UnseenHeroSettings {
  const UnseenHeroSettings({
    required this.visibleOnSafeWalk,
    required this.acceptingHelpRequests,
    required this.sharePhoneAfterAcceptance,
    required this.updatedAt,
  });

  final bool visibleOnSafeWalk;
  final bool acceptingHelpRequests;
  final bool sharePhoneAfterAcceptance;
  final DateTime updatedAt;

  factory UnseenHeroSettings.defaults() {
    return UnseenHeroSettings(
      visibleOnSafeWalk: false,
      acceptingHelpRequests: false,
      sharePhoneAfterAcceptance: false,
      updatedAt: DateTime.now(),
    );
  }

  factory UnseenHeroSettings.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawUpdatedAt = data['updatedAt'];
    return UnseenHeroSettings(
      visibleOnSafeWalk: data['visibleOnSafeWalk'] as bool? ?? false,
      acceptingHelpRequests: data['acceptingHelpRequests'] as bool? ?? false,
      sharePhoneAfterAcceptance:
          data['sharePhoneAfterAcceptance'] as bool? ?? false,
      updatedAt:
          rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'visibleOnSafeWalk': visibleOnSafeWalk,
      'acceptingHelpRequests': acceptingHelpRequests,
      'sharePhoneAfterAcceptance': sharePhoneAfterAcceptance,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }

  UnseenHeroSettings copyWith({
    bool? visibleOnSafeWalk,
    bool? acceptingHelpRequests,
    bool? sharePhoneAfterAcceptance,
  }) {
    return UnseenHeroSettings(
      visibleOnSafeWalk: visibleOnSafeWalk ?? this.visibleOnSafeWalk,
      acceptingHelpRequests:
          acceptingHelpRequests ?? this.acceptingHelpRequests,
      sharePhoneAfterAcceptance:
          sharePhoneAfterAcceptance ?? this.sharePhoneAfterAcceptance,
      updatedAt: DateTime.now(),
    );
  }
}

class UnseenHeroPresence {
  const UnseenHeroPresence({
    required this.recognitionId,
    required this.heroId,
    required this.heroName,
    required this.communityId,
    required this.communityName,
    required this.areaName,
    required this.latitude,
    required this.longitude,
    required this.message,
    required this.recognizedAt,
    required this.helpAvailable,
    required this.sharePhoneAfterAcceptance,
    required this.visibleUntil,
  });

  final String recognitionId;
  final String heroId;
  final String heroName;
  final String communityId;
  final String communityName;
  final String areaName;
  final double latitude;
  final double longitude;
  final String message;
  final DateTime recognizedAt;
  final bool helpAvailable;
  final bool sharePhoneAfterAcceptance;
  final DateTime visibleUntil;

  factory UnseenHeroPresence.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final location = data['location'] as GeoPoint?;
    final recognizedAt = data['recognizedAt'];
    final visibleUntil = data['visibleUntil'];
    return UnseenHeroPresence(
      recognitionId: doc.id,
      heroId: data['heroId'] as String? ?? '',
      heroName: data['heroName'] as String? ?? 'A HALO hero',
      communityId: data['communityId'] as String? ?? '',
      communityName: data['communityName'] as String? ?? 'HALO community',
      areaName: data['areaName'] as String? ?? 'Nearby area',
      latitude: location?.latitude ?? 0,
      longitude: location?.longitude ?? 0,
      message: data['message'] as String? ?? '',
      recognizedAt:
          recognizedAt is Timestamp ? recognizedAt.toDate() : DateTime.now(),
      helpAvailable: data['helpAvailable'] as bool? ?? false,
      sharePhoneAfterAcceptance:
          data['sharePhoneAfterAcceptance'] as bool? ?? false,
      visibleUntil: visibleUntil is Timestamp
          ? visibleUntil.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toFirestore({
    required String geohashPrefix,
  }) {
    return {
      'heroId': heroId,
      'heroName': heroName,
      'communityId': communityId,
      'communityName': communityName,
      'areaName': areaName,
      'location': GeoPoint(latitude, longitude),
      'message': message,
      'recognizedAt': Timestamp.fromDate(recognizedAt),
      'helpAvailable': helpAvailable,
      'sharePhoneAfterAcceptance': sharePhoneAfterAcceptance,
      'visibleUntil': Timestamp.fromDate(visibleUntil),
      'geohashPrefix': geohashPrefix,
    };
  }
}

class NearbyUnseenHero {
  const NearbyUnseenHero(
      {required this.presence, required this.distanceMeters});

  final UnseenHeroPresence presence;
  final double distanceMeters;
}

class HeroHelpRequest {
  const HeroHelpRequest({
    required this.id,
    required this.heroId,
    required this.heroName,
    required this.recognitionId,
    required this.communityId,
    required this.communityName,
    required this.areaName,
    required this.requesterId,
    required this.requesterName,
    required this.message,
    required this.contactAllowed,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  final String id;
  final String heroId;
  final String heroName;
  final String recognitionId;
  final String communityId;
  final String communityName;
  final String areaName;
  final String requesterId;
  final String requesterName;
  final String message;
  final bool contactAllowed;
  final HeroHelpRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  bool get isPending => status == HeroHelpRequestStatus.pending;
  bool get isAccepted => status == HeroHelpRequestStatus.accepted;

  HeroHelpRequest copyWith({
    HeroHelpRequestStatus? status,
    DateTime? respondedAt,
  }) {
    return HeroHelpRequest(
      id: id,
      heroId: heroId,
      heroName: heroName,
      recognitionId: recognitionId,
      communityId: communityId,
      communityName: communityName,
      areaName: areaName,
      requesterId: requesterId,
      requesterName: requesterName,
      message: message,
      contactAllowed: contactAllowed,
      status: status ?? this.status,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  factory HeroHelpRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    final respondedAt = data['respondedAt'];
    return HeroHelpRequest(
      id: doc.id,
      heroId: data['heroId'] as String? ?? '',
      heroName: data['heroName'] as String? ?? 'Unseen Hero',
      recognitionId: data['recognitionId'] as String? ?? '',
      communityId: data['communityId'] as String? ?? '',
      communityName: data['communityName'] as String? ?? 'HALO community',
      areaName: data['areaName'] as String? ?? 'Nearby area',
      requesterId: data['requesterId'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? 'A HALO user',
      message: data['message'] as String? ?? '',
      contactAllowed: data['contactAllowed'] as bool? ?? false,
      status: HeroHelpRequestStatus.fromValue(data['status'] as String?),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      respondedAt: respondedAt is Timestamp ? respondedAt.toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'heroId': heroId,
      'heroName': heroName,
      'recognitionId': recognitionId,
      'communityId': communityId,
      'communityName': communityName,
      'areaName': areaName,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'message': message,
      'contactAllowed': contactAllowed,
      'status': HeroHelpRequestStatus.pending.name,
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'respondedAt': null,
    };
  }
}

class HeroContactGrant {
  const HeroContactGrant({
    required this.heroPhone,
    required this.requesterPhone,
  });

  final String heroPhone;
  final String requesterPhone;

  bool get canHeroCall => requesterPhone.isNotEmpty;
  bool get canRequesterCall => heroPhone.isNotEmpty;

  factory HeroContactGrant.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return HeroContactGrant(
      heroPhone: data['heroPhone'] as String? ?? '',
      requesterPhone: data['requesterPhone'] as String? ?? '',
    );
  }
}
