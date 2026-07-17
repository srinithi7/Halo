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

/// Core data model for a single anonymous recognition ("HALO") post.
///
/// IMPORTANT — anonymity contract:
/// [senderId] identifies who created this post, but it exists purely for
/// backend moderation and abuse tracing (e.g. rate limiting, banning a
/// source of abusive posts, investigating reports). It is NOT part of
/// this app's public/social data model.
///
/// Any code that renders a [RecognitionPost] to a screen, feed, card, or
/// notification MUST NOT read or display [senderId] in any form. There is
/// deliberately no getter, display helper, or `toString()` override here
/// that surfaces it — treat it the same as a credential, not a display
/// field. If a UI-facing method on this class is ever added, it must not
/// accept or return [senderId].
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
    this.glowCount = 0,
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

  /// Number of times users have "glowed" (tapped appreciation on) this
  /// post. Increment-only — see RecognitionService.glowRecognition.
  final int glowCount;

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

    return RecognitionPost(
      postId: doc.id,
      senderId: data['senderId'] as String? ?? '',
      recipientId: data['recipientId'] as String? ?? '',
      recipientDisplayName: data['recipientDisplayName'] as String? ?? 'Someone',
      message: data['message'] as String? ?? '',
      groupId: data['groupId'] as String? ?? '',
      moderationStatus: ModerationStatus.fromValue(
        data['moderationStatus'] as String?,
      ),
      createdAt: rawCreatedAt is Timestamp
          ? rawCreatedAt.toDate()
          : DateTime.now(),
      glowCount: (data['glowCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Serializes this post for writing to Firestore.
  ///
  /// [senderId] is included here because this is the backend storage
  /// representation, not a UI payload — the document itself is only ever
  /// read by trusted moderation code paths that need it, and Firestore
  /// security rules should restrict direct client reads of this field.
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'recipientId': recipientId,
      'recipientDisplayName': recipientDisplayName,
      'message': message,
      'groupId': groupId,
      'moderationStatus': moderationStatus.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'glowCount': glowCount,
    };
  }
}
