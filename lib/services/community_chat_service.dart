import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/community_message.dart';

/// Firestore service layer for community chat messages: sending, emoji
/// reactions, and deleting your own.
class CommunityChatService {
  CommunityChatService._();

  static CollectionReference<Map<String, dynamic>> _messages(
      String communityId) {
    return FirebaseFirestore.instance
        .collection('communities')
        .doc(communityId)
        .collection('messages');
  }

  static Future<void> sendMessage({
    required String communityId,
    required String senderId,
    required String senderDisplayName,
    required String text,
    String? replyToSenderDisplayName,
    String? replyToText,
  }) {
    final message = CommunityMessage(
      id: '',
      senderId: senderId,
      senderDisplayName: senderDisplayName,
      text: text,
      createdAt: DateTime.now(),
      replyToSenderDisplayName: replyToSenderDisplayName,
      replyToText: replyToText,
    );
    return _messages(communityId).add(message.toFirestore());
  }

  /// Sets [uid]'s reaction on a message to [emoji] — one emoji per uid,
  /// so picking a new one replaces any previous reaction from that person.
  /// Written as a single dotted-path field update rather than a full
  /// reactions-map read-modify-write, so two people reacting at the same
  /// moment never clobber each other.
  static Future<void> setReaction(
      String communityId, String messageId, String uid, String emoji) {
    return _messages(communityId)
        .doc(messageId)
        .update({'reactions.$uid': emoji});
  }

  static Future<void> clearReaction(
      String communityId, String messageId, String uid) {
    return _messages(communityId)
        .doc(messageId)
        .update({'reactions.$uid': FieldValue.delete()});
  }

  static Future<void> deleteMessage(String communityId, String messageId) {
    return _messages(communityId).doc(messageId).delete();
  }
}
