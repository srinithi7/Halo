import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore service layer for [RecognitionPost] mutations that don't
/// belong on the model itself.
class RecognitionService {
  RecognitionService._();

  static const _recognitions = 'recognitions';

  static Future<void> recordInteraction({
    required String postId,
    required String uid,
    required String action,
  }) async {
    final ref =
        FirebaseFirestore.instance.collection(_recognitions).doc(postId);
    final update = <String, dynamic>{
      'rippleTrail': FieldValue.arrayUnion([uid]),
      'reachCount': FieldValue.increment(1),
    };

    switch (action) {
      case 'pass':
        update['passes'] = FieldValue.arrayUnion([uid]);
        break;
      case 'add':
        update['adds'] = FieldValue.arrayUnion([uid]);
        break;
      case 'share':
        update['shares'] = FieldValue.arrayUnion([uid]);
        break;
      default:
        break;
    }

    await ref.update(update);
  }

  /// Toggles [uid]'s glow on a post: adds it if they haven't glowed yet,
  /// removes it if they have. [wasGlowed] is the caller's current
  /// (already-known, from the live stream) state — this decides which
  /// direction to toggle rather than re-reading the document first, so a
  /// tap always flips relative to what's on screen instead of racing a
  /// fresh read against other concurrent taps.
  static Future<void> toggleGlow(String postId, String uid,
      {required bool wasGlowed}) {
    return FirebaseFirestore.instance
        .collection(_recognitions)
        .doc(postId)
        .update({
      'glowedBy': wasGlowed
          ? FieldValue.arrayRemove([uid])
          : FieldValue.arrayUnion([uid]),
    });
  }
}
