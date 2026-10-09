import 'package:cloud_firestore/cloud_firestore.dart';

/// Moderation lifecycle for a [RecognitionPost].
///
/// Every post is created as [pending] and must be moved to [approved]
/// by a moderation process before it is safe to surface in any
/// UI-facing feed or query.
enum ModerationStatus {
  pending,
  approved,
  rejected;

  /// Parses a Firestore string value back into a [ModerationStatus].
  /// Falls back to [pending] for unrecognized/missing values so that
  /// malformed data is never accidentally treated as approved.
  static ModerationStatus fromValue(String? value) {
    return ModerationStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ModerationStatus.pending,
    );
  }
}

/// Who can see a [RecognitionPost] besides its sender and recipient.
///
/// Enforced at the Firestore rules level (see firestore.rules), not just
/// hidden client-side — a [contacts]-scoped post is genuinely unreadable
/// to a phone number outside [RecognitionPost.allowedPhoneNumbers], the
/// same way [ModerationStatus.pending] posts are unreadable-as-approved.
enum PostVisibility {
  public,
  contacts;

  static PostVisibility fromValue(String? value) {
    return PostVisibility.values.firstWhere(
      (v) => v.name == value,
      orElse: () => PostVisibility.public,
    );
  }
}

/// Core data model for a single recognition ("HALO") post — anonymous by
/// default, with an opt-in identity reveal.
///
/// IMPORTANT — anonymity contract:
/// [senderId] identifies who created this post, but it exists purely for
/// backend moderation and abuse tracing (e.g. rate limiting, banning a
/// source of abusive posts, investigating reports). It is NOT part of
/// this app's public/social data model.
///
/// Any code that renders a [RecognitionPost] to a screen, feed, card, or
/// notification MUST NOT read or display [senderId] in any form, ever —
/// there is deliberately no getter, display helper, or `toString()`
/// override here that surfaces it. This is separate from and stricter
/// than [isAnonymous]/[senderDisplayName]: those two let a sender opt in
/// to revealing their name, and once revealed it's shown everywhere this
/// post appears — public feed, search, and the recipient's own "received"
/// view alike — gated only on [isAnonymous] being false. [senderId] itself
/// still must never be read/displayed regardless of that flag. If a
/// UI-facing method on this class is ever added, it must not accept or
/// return [senderId].
class RecognitionPost {
  RecognitionPost({
    required this.postId,
    required this.senderId,
    required this.recipientId,
    required this.recipientDisplayName,
    required this.message,
    required this.groupId,
    required this.createdAt,
    this.moderationStatus = ModerationStatus.pending,
    this.glowedBy = const [],
    this.isAnonymous = true,
    this.senderDisplayName,
    this.visibility = PostVisibility.public,
    this.allowedPhoneNumbers = const [],
    this.isUnseenHeroCandidate = false,
    this.location,
    this.areaName,
    this.geohashPrefix,
    this.locationPrecision,
    this.category = 'general',
    this.act,
    this.feeling,
    this.hashtags = const [],
    this.isVisitor = false,
    this.rippleTrail = const [],
    this.expiresAt,
  });

  /// Firestore document id.
  final String postId;

  /// Internal-only reference to who created this post. Used solely for
  /// moderation and abuse tracing on the backend — never render this in
  /// the UI, never include it in a feed/card/notification payload sent
  /// to other users.
  final String senderId;

  /// The recognized user's uid — resolved from the phone number typed into
  /// the submit screen. Used to query "recognitions received" for a user's
  /// Profile screen; not a display value on its own (see
  /// [recipientDisplayName]).
  final String recipientId;

  /// Denormalized display name for [recipientId], captured at submit time
  /// so the feed doesn't need a per-card user lookup. Safe to show in the
  /// UI, unlike [recipientId] itself.
  final String recipientDisplayName;

  /// The recognition content itself — what the person did.
  final String message;

  /// Id of the community/group this post belongs to, for scoping feeds.
  final String groupId;

  /// Current moderation state; gates whether this appears in public feeds.
  final ModerationStatus moderationStatus;

  /// When the post was created (used for ordering + "x ago" display).
  final DateTime createdAt;

  /// Uids of every user who has currently glowed (liked) this post — a
  /// second tap from the same user removes theirs, it doesn't add another.
  /// See RecognitionService.toggleGlow. [glowCount] is derived from this,
  /// not stored separately, so the count can never drift from membership.
  final List<String> glowedBy;

  /// Number of users who have glowed this post — just `glowedBy.length`,
  /// kept as a getter so display code doesn't need to know the storage
  /// shape changed from a raw counter to a membership list.
  int get glowCount => glowedBy.length;

  /// Whether [uid] has currently glowed this post — drives the toggle
  /// button's filled/outline state.
  bool isGlowedBy(String uid) => glowedBy.contains(uid);

  /// Whether the sender chose to stay anonymous (the default) rather than
  /// reveal their identity. When false, [senderDisplayName] is shown
  /// everywhere this post is displayed — public feed, search, and the
  /// recipient's received view alike — not just to the recipient.
  final bool isAnonymous;

  /// Denormalized sender name, only ever populated when [isAnonymous] is
  /// false. Safe to show anywhere this post is rendered once revealed.
  final String? senderDisplayName;

  /// Who besides the sender/recipient can see this post. Defaults to
  /// [PostVisibility.public] — the original, and still normal, behavior.
  final PostVisibility visibility;

  /// Snapshot of the sender's own contacts' phone numbers (E.164, `+91…`),
  /// taken at submit time — only populated when [visibility] is
  /// [PostVisibility.contacts]. This is the Firestore rules allowlist for
  /// who can read the post: a viewer whose own phone number (from their
  /// Firebase Auth phone-auth token) isn't in this list can't read the
  /// document at all, not just "it's hidden in this screen". Because
  /// anyone who *can* read the post also sees this raw list, it does leak
  /// "the sender has your number saved" to people in it — an accepted,
  /// minor trade-off, not a bug.
  final List<String> allowedPhoneNumbers;

  final bool isUnseenHeroCandidate;
  final GeoPoint? location;
  final String? areaName;
  final String? geohashPrefix;
  final String? locationPrecision;

  /// The high-level category of the recognition.
  final String category;

  /// Free-form act label, when present.
  final String? act;

  /// How the sender felt when they noticed it.
  final String? feeling;

  /// Normalized hashtags extracted from the message and/or set at send time.
  final List<String> hashtags;

  /// Whether this was a visitor-style recognition rather than a local one.
  final bool isVisitor;

  /// The ripple trail tracks people or communities who interacted with the post.
  final List<String> rippleTrail;

  /// The time after which the post should no longer be live in the main feed.
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isLive => !isExpired;

  static List<String> extractHashtags(String text) {
    final matches = RegExp(r'(?<!\w)#([A-Za-z0-9_]+)').allMatches(text);
    final tags = <String>{};
    for (final match in matches) {
      final value = match.group(1)?.toLowerCase();
      if (value != null && value.isNotEmpty) tags.add(value);
    }
    return tags.toList()..sort();
  }

  List<String> get normalizedHashtags {
    if (hashtags.isNotEmpty) return hashtags;
    return extractHashtags(message);
  }

  /// Builds a [RecognitionPost] from a Firestore document snapshot.
  ///
  /// Note: this deserializes [senderId] because the backend/moderation
  /// layer needs it — it is the *reading* of this field into UI code that
  /// must never happen, not its presence in this model.
  factory RecognitionPost.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawCreatedAt = data['createdAt'];
    final rawExpiresAt = data['expiresAt'];

    return RecognitionPost(
      postId: doc.id,
      senderId: data['senderId'] as String? ?? '',
      recipientId: data['recipientId'] as String? ?? '',
      recipientDisplayName:
          data['recipientDisplayName'] as String? ?? 'Someone',
      message: data['message'] as String? ?? '',
      groupId: data['groupId'] as String? ?? '',
      moderationStatus: ModerationStatus.fromValue(
        data['moderationStatus'] as String?,
      ),
      createdAt:
          rawCreatedAt is Timestamp ? rawCreatedAt.toDate() : DateTime.now(),
      glowedBy:
          (data['glowedBy'] as List<dynamic>?)?.cast<String>() ?? const [],
      isAnonymous: data['isAnonymous'] as bool? ?? true,
      senderDisplayName: data['senderDisplayName'] as String?,
      visibility: PostVisibility.fromValue(data['visibility'] as String?),
      allowedPhoneNumbers:
          (data['allowedPhoneNumbers'] as List<dynamic>?)?.cast<String>() ??
              const [],
      isUnseenHeroCandidate: data['isUnseenHeroCandidate'] as bool? ?? false,
      location: data['location'] as GeoPoint?,
      areaName: data['areaName'] as String?,
      geohashPrefix: data['geohashPrefix'] as String?,
      locationPrecision: data['locationPrecision'] as String?,
      category: data['category'] as String? ?? 'general',
      act: data['act'] as String?,
      feeling: data['feeling'] as String?,
      hashtags: (data['hashtags'] as List<dynamic>?)?.cast<String>() ??
          extractHashtags(data['message'] as String? ?? ''),
      isVisitor: data['isVisitor'] as bool? ?? false,
      rippleTrail:
          (data['rippleTrail'] as List<dynamic>?)?.cast<String>() ?? const [],
      expiresAt: rawExpiresAt is Timestamp ? rawExpiresAt.toDate() : null,
    );
  }

  /// Serializes this post for writing to Firestore.
  ///
  /// [senderId] is included here because this is the backend storage
  /// representation, not a UI payload — the document itself is only ever
  /// read by trusted moderation code paths that need it, and Firestore
  /// security rules should restrict direct client reads of this field.
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'senderId': senderId,
      'recipientId': recipientId,
      'recipientDisplayName': recipientDisplayName,
      'message': message,
      'groupId': groupId,
      'moderationStatus': moderationStatus.name,
      'isAnonymous': isAnonymous,
      'senderDisplayName': senderDisplayName,
      'createdAt': Timestamp.fromDate(createdAt),
      'glowedBy': glowedBy,
      'visibility': visibility.name,
      'allowedPhoneNumbers': allowedPhoneNumbers,
      'category': category,
      'act': act,
      'feeling': feeling,
      'hashtags': hashtags.isEmpty ? extractHashtags(message) : hashtags,
      'isVisitor': isVisitor,
      'rippleTrail': rippleTrail,
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
    };
    if (isUnseenHeroCandidate &&
        location != null &&
        areaName != null &&
        geohashPrefix != null) {
      data['isUnseenHeroCandidate'] = true;
      data['location'] = location;
      data['areaName'] = areaName;
      data['geohashPrefix'] = geohashPrefix;
      data['locationPrecision'] = locationPrecision ?? 'approximateArea';
    }
    return data;
  }
}
