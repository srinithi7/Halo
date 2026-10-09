import 'package:cloud_firestore/cloud_firestore.dart';

/// A single text message in a community's chat
/// (`communities/{communityId}/messages/{messageId}`).
///
/// Unlike [RecognitionPost.senderId], this chat is explicitly named, not
/// anonymous — [senderDisplayName] is meant to be shown. HALO recognitions
/// interleaved into the chat timeline are rendered directly from
/// [RecognitionPost] (see CommunityChatScreen) rather than duplicated into
/// this collection, so [RecognitionPost.senderId]'s anonymity invariant is
/// untouched by this model.
class CommunityMessage {
  CommunityMessage({
    required this.id,
    required this.senderId,
    required this.senderDisplayName,
    required this.text,
    required this.createdAt,
    this.reactions = const {},
    this.replyToSenderDisplayName,
    this.replyToText,
  });

  final String id;
  final String senderId;
  final String senderDisplayName;
  final String text;
  final DateTime createdAt;

  /// Denormalized snapshot of the message being replied to (sender name +
  /// text), captured at send time rather than a live reference — a quoted
  /// reply should keep showing what was actually said even if the
  /// original is later deleted (see CommunityChatService.deleteMessage).
  /// Both null together means "not a reply".
  final String? replyToSenderDisplayName;
  final String? replyToText;

  bool get isReply => replyToText != null;

  /// One emoji per reacting uid — WhatsApp/Instagram-style: a member picks
  /// a single emoji per message, tapping a reaction they don't already
  /// have switches them to it. This is a deliberate, scoped exception to
  /// HALO's no-emoji-in-UI rule — reactions only, nowhere else.
  final Map<String, String> reactions;

  String? reactionOf(String uid) => reactions[uid];

  /// Reaction emoji grouped with their counts, most popular first — what
  /// actually renders under a message bubble.
  List<MapEntry<String, int>> get groupedReactions {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  factory CommunityMessage.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawCreatedAt = data['createdAt'];
    return CommunityMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderDisplayName: data['senderDisplayName'] as String? ?? 'A HALO user',
      text: data['text'] as String? ?? '',
      createdAt:
          rawCreatedAt is Timestamp ? rawCreatedAt.toDate() : DateTime.now(),
      reactions: (data['reactions'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          const {},
      replyToSenderDisplayName: data['replyToSenderDisplayName'] as String?,
      replyToText: data['replyToText'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderDisplayName': senderDisplayName,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'reactions': reactions,
      'replyToSenderDisplayName': replyToSenderDisplayName,
      'replyToText': replyToText,
    };
  }
}
