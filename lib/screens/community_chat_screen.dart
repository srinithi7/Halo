import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/community.dart';
import '../models/community_message.dart';
import '../models/recognition_post.dart';
import '../services/community_chat_service.dart';
import '../services/community_service.dart';
import '../services/recognition_service.dart';
import '../theme/app_theme.dart';
import '../utils/message_moderation.dart';
import '../utils/relative_time.dart';

/// One entry in the merged chat timeline — either a plain [CommunityMessage]
/// or a [RecognitionPost] approved for this community, sorted together by
/// time so the whole community sees a HALO land live, in context, instead
/// of it only showing up in a separate list.
sealed class _TimelineEntry {
  DateTime get time;
}

class _MessageEntry extends _TimelineEntry {
  _MessageEntry(this.message);
  final CommunityMessage message;
  @override
  DateTime get time => message.createdAt;
}

class _HaloEntry extends _TimelineEntry {
  _HaloEntry(this.post);
  final RecognitionPost post;
  @override
  DateTime get time => post.createdAt;
}

/// Opens an in-app emoji grid (categories, tap-to-pick) — deliberately not
/// a plain TextField with the device keyboard, since that would let
/// someone type actual words as a "reaction" instead of an emoji. This is
/// HALO's one scoped exception to its no-emoji-in-UI rule.
Future<String?> _pickEmoji(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: bgSurface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
    ),
    builder: (sheetContext) => SizedBox(
      height: 320,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) =>
            Navigator.of(sheetContext).pop(emoji.emoji),
        config: const Config(
          height: 320,
          emojiViewConfig: EmojiViewConfig(backgroundColor: bgSurface2),
          categoryViewConfig: CategoryViewConfig(backgroundColor: bgSurface2),
          bottomActionBarConfig:
              BottomActionBarConfig(backgroundColor: bgSurface2),
          searchViewConfig: SearchViewConfig(backgroundColor: bgSurface2),
        ),
      ),
    ),
  );
}

/// A community's chat — named messages (see CommunityMessage) interleaved
/// live with the HALOs (recognitions) sent within this community.
class CommunityChatScreen extends StatefulWidget {
  const CommunityChatScreen({super.key, required this.community});

  final Community community;

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _halosStream;
  bool _isSending = false;

  // Set by swiping a message — see _MessageBubble's Dismissible. Shown as
  // a quoted preview above the input, cleared on send or explicit cancel.
  CommunityMessage? _replyTarget;

  @override
  void initState() {
    super.initState();
    _messagesStream = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.community.id)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
    _halosStream = FirebaseFirestore.instance
        .collection('recognitions')
        .where('groupId', isEqualTo: widget.community.id)
        .where('moderationStatus', isEqualTo: 'approved')
        .snapshots();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Same lexicon-based check as recognitions (see message_moderation.dart)
    // — chat is freeform text with the same abuse surface, so it gets the
    // same single-level gate for now rather than shipping unmoderated.
    final moderation = moderateMessage(text);
    if (!moderation.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(moderation.reason ?? 'This message was not sent.')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final name = profile.data()?['name'] as String? ?? 'A HALO user';

      await CommunityChatService.sendMessage(
        communityId: widget.community.id,
        senderId: user.uid,
        senderDisplayName: name,
        text: text,
        replyToSenderDisplayName: _replyTarget?.senderDisplayName,
        replyToText: _replyTarget?.text,
      );
      _textController.clear();
      setState(() => _replyTarget = null);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      // Chat is membership-gated at the Firestore rules level (unlike
      // browsing communities, which anyone signed in can do) — surface
      // that specifically instead of a generic "connection" message that
      // would send someone chasing a network problem that isn't real.
      final message = e.code == 'permission-denied'
          ? 'Join this community to send messages here.'
          : "Couldn't send — check your connection and try again.";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _messagesStream,
            builder: (context, messagesSnapshot) {
              if (messagesSnapshot.hasError) {
                // Chat is membership-gated in Firestore rules, but
                // browsing into a community's detail screen isn't — a
                // non-member can land here. Tell them why, with a way
                // out, rather than showing a blank/broken chat.
                return _NotAMemberState(community: widget.community);
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _halosStream,
                builder: (context, halosSnapshot) {
                  if (messagesSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      halosSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: accentGold));
                  }

                  final entries = <_TimelineEntry>[
                    for (final doc in messagesSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      _MessageEntry(CommunityMessage.fromFirestore(doc)),
                    for (final doc in halosSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      _HaloEntry(RecognitionPost.fromFirestore(doc)),
                  ]..sort((a, b) => a.time.compareTo(b.time));

                  // A failed HALOs query should never look like "this
                  // community has no recognition posts": lead with a banner
                  // and keep chat readable underneath.
                  final hasHaloError = halosSnapshot.hasError;

                  if (entries.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(spacingPadding),
                        child: Text(
                          'No messages yet. Say hello, or send the\nfirst HALO in this community.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted),
                        ),
                      ),
                    );
                  }

                  // Only follow new messages down if the reader was
                  // already near the bottom — otherwise this would yank
                  // someone back down mid-scroll every time any new
                  // message/HALO arrives, including ones from other people.
                  final wasNearBottom = !_scrollController.hasClients ||
                      _scrollController.position.maxScrollExtent -
                              _scrollController.position.pixels <
                          80;
                  if (wasNearBottom) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController
                            .jumpTo(_scrollController.position.maxScrollExtent);
                      }
                    });
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(spacingPadding),
                    itemCount: entries.length + (hasHaloError ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasHaloError && index == 0) {
                        return const _HalosUnavailableBanner();
                      }
                      final entry = entries[index - (hasHaloError ? 1 : 0)];
                      return entry is _HaloEntry
                          ? _HaloBubble(post: entry.post, myUid: myUid)
                          : _MessageBubble(
                              communityId: widget.community.id,
                              message: (entry as _MessageEntry).message,
                              isMine: entry.message.senderId == myUid,
                              myUid: myUid,
                              onSwipeReply: (m) =>
                                  setState(() => _replyTarget = m),
                            );
                    },
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Column(
            children: [
              if (_replyTarget != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: spacingSmallGap, vertical: 6),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: borderColor)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 3, height: 30, color: accentGold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replying to ${_replyTarget!.senderDisplayName}',
                              style: const TextStyle(
                                  color: accentGold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _replyTarget!.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x,
                            size: 16, color: textMuted),
                        onPressed: () => setState(() => _replyTarget = null),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(spacingSmallGap),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            hintText: 'Message this community...'),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: spacingSmallGap),
                    IconButton.filled(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: bgPrimary))
                          : const Icon(LucideIcons.send, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown in the chat timeline when the recognition feed fails to load, so a
/// dead query never masquerades as an empty community.
class _HalosUnavailableBanner extends StatelessWidget {
  const _HalosUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: spacingSmallGap),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorRedDim,
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: colorRed.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.cloudOff, size: 15, color: colorRed),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Recognition posts aren't loading right now — chat below still works.",
              style: TextStyle(color: textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.communityId,
    required this.message,
    required this.isMine,
    required this.myUid,
    required this.onSwipeReply,
  });

  final String communityId;
  final CommunityMessage message;
  final bool isMine;
  final String? myUid;
  final ValueChanged<CommunityMessage> onSwipeReply;

  Future<void> _react(BuildContext context, {String? quickEmoji}) async {
    final uid = myUid;
    if (uid == null) return;

    final currentReaction = message.reactionOf(uid);
    if (quickEmoji != null) {
      // Tapping an existing reaction chip: remove it if it's already
      // yours, otherwise quick-copy that emoji as your own reaction —
      // the same one-tap behavior WhatsApp/Instagram use.
      if (currentReaction == quickEmoji) {
        await CommunityChatService.clearReaction(communityId, message.id, uid);
      } else {
        await CommunityChatService.setReaction(
            communityId, message.id, uid, quickEmoji);
      }
      return;
    }

    final emoji = await _pickEmoji(context);
    if (emoji == null || emoji.isEmpty) return;
    await CommunityChatService.setReaction(communityId, message.id, uid, emoji);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: bgSurface2,
        title:
            const Text('Delete message?', style: TextStyle(color: textPrimary)),
        content: const Text('This removes it for everyone in the community.',
            style: TextStyle(color: textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await CommunityChatService.deleteMessage(communityId, message.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myReaction = myUid == null ? null : message.reactionOf(myUid!);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Swipe right to reply — same trick WhatsApp-style chat clones
          // use: a Dismissible that always cancels its own dismissal, so
          // the message never actually leaves the list, only the gesture
          // fires.
          Dismissible(
            key: ValueKey(message.id),
            direction: DismissDirection.startToEnd,
            confirmDismiss: (_) async {
              onSwipeReply(message);
              return false;
            },
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: const Icon(LucideIcons.reply, color: accentGold, size: 18),
            ),
            child: GestureDetector(
              onLongPress: () => _react(context),
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMine ? accentGoldDim : bgSurface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isMine ? accentGoldBorder : borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          message.senderDisplayName,
                          style: const TextStyle(
                              color: accentGold,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (message.isReply)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(
                          border: Border(
                              left: BorderSide(color: accentGold, width: 2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.replyToSenderDisplayName ?? 'A HALO user',
                              style: const TextStyle(
                                  color: accentGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              message.replyToText ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(message.text,
                              style: const TextStyle(
                                  color: textPrimary, fontSize: 14)),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _confirmDelete(context),
                            child: const Icon(LucideIcons.trash2,
                                size: 13, color: textMuted),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(relativeTime(message.createdAt),
                        style: const TextStyle(color: textMuted, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in message.groupedReactions)
                GestureDetector(
                  onTap: () => _react(context, quickEmoji: entry.key),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          entry.key == myReaction ? accentGoldDim : bgSurface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: entry.key == myReaction
                              ? accentGoldBorder
                              : borderColor),
                    ),
                    child: Text('${entry.key} ${entry.value}',
                        style:
                            const TextStyle(fontSize: 12, color: textPrimary)),
                  ),
                ),
              GestureDetector(
                onTap: () => _react(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child:
                      Icon(LucideIcons.smilePlus, size: 15, color: textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HaloBubble extends StatefulWidget {
  const _HaloBubble({required this.post, required this.myUid});
  final RecognitionPost post;
  final String? myUid;

  @override
  State<_HaloBubble> createState() => _HaloBubbleState();
}

class _HaloBubbleState extends State<_HaloBubble> {
  bool _isSending = false;

  Future<void> _toggleGlow() async {
    final uid = widget.myUid;
    if (uid == null || _isSending) return;
    setState(() => _isSending = true);
    try {
      await RecognitionService.toggleGlow(
        widget.post.postId,
        uid,
        wasGlowed: widget.post.isGlowedBy(uid),
      );
    } catch (_) {
      // Same fire-and-forget-with-guard pattern as the feed's glow button
      // — a failed toggle just leaves the count as-is, no need to alarm
      // the reader over a reaction not landing.
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final from = !post.isAnonymous && post.senderDisplayName != null
        ? post.senderDisplayName!
        : 'Someone';
    final isGlowed = widget.myUid != null && post.isGlowedBy(widget.myUid!);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: spacingSmallGap),
      padding: const EdgeInsets.all(spacingSmallGap + 4),
      decoration: BoxDecoration(
        color: accentGoldDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentGoldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.sparkle, color: accentGold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 13, color: textPrimary, height: 1.4),
                children: [
                  TextSpan(
                      text: from,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: accentGold)),
                  const TextSpan(text: ' recognized '),
                  TextSpan(
                    text: post.recipientDisplayName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: accentGold),
                  ),
                  TextSpan(text: ': "${post.message}"'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _toggleGlow,
            child: Row(
              children: [
                Icon(LucideIcons.sparkle,
                    size: 14, color: isGlowed ? accentGold : textMuted),
                const SizedBox(width: 3),
                Text('${post.glowCount}',
                    style: TextStyle(
                        fontSize: 11,
                        color: isGlowed ? accentGold : textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the chat when the viewer isn't a member — reachable
/// because browsing a community's detail screen has no membership gate,
/// only its chat does (see the Firestore rules on communities/*/messages).
class _NotAMemberState extends StatelessWidget {
  const _NotAMemberState({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(spacingPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.messagesSquare, size: 36, color: textMuted),
            const SizedBox(height: 12),
            Text(
              "Join ${community.name} to view and send messages here.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: textMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: uid == null
                  ? null
                  : () => CommunityService.join(community.id, uid),
              icon: const Icon(LucideIcons.userPlus, size: 18),
              label: const Text('Join community'),
            ),
          ],
        ),
      ),
    );
  }
}
