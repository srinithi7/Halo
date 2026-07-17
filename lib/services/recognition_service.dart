import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore service layer for [RecognitionPost] mutations that don't
/// belong on the model itself.
class RecognitionService {
  RecognitionService._();

  /// Increments a post's glowCount by 1. Increment-only — there's no
  /// un-glow, and no record of who glowed a given post.
  static Future<void> glowRecognition(String postId) {
    return FirebaseFirestore.instance
        .collection('recognitions')
        .doc(postId)
        .update({'glowCount': FieldValue.increment(1)});
  }
}
