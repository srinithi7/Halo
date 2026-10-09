import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../constants.dart';
import '../models/recognition_post.dart';
import '../services/recognition_service.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';
import 'communities_screen.dart';

/// Displays live, approved recognition posts from the communities the
/// viewer has actually joined (plus the General/default feed) — not every
/// public post app-wide — with horizontally scrollable chips to filter
/// down to one of those. See RecognitionSubmitScreen for where a post's
/// community is chosen at send time.
///
/// senderId is intentionally NEVER read or rendered here — the query and
/// the widget only ever touch recipientId/recipientDisplayName, message,
/// groupId, createdAt, and glowCount.
class RecognitionFeedScreen extends StatefulWidget {
  final String groupId;

  const RecognitionFeedScreen({super.key, required this.groupId});

  @override
  State<RecognitionFeedScreen> createState() => _RecognitionFeedScreenState();
}

class _RecognitionFeedScreenState extends State<RecognitionFeedScreen> {
  // All communities, once — feeds both the id->name lookup for chips and
  // (filtered to ones this viewer belongs to) the recognitions query
  // below. Small enough at this app's scale to fetch in full rather than
  // add a second membership-only query.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _communitiesStream;

  // null = "All" chip selected.
  String? _selectedGroup;
  String? _selectedHashtag;

  @override
  void initState() {
    super.initState();
    _communitiesStream =
        FirebaseFirestore.instance.collection('communities').snapshots();
  }

  /// Recognitions scoped to [allowedGroupIds] — rebuilt whenever the
  /// communities stream emits (e.g. right after joining/leaving one),
  /// rather than held as a single `late final` stream, since the set of
  /// communities to scope to isn't known until that stream's first value.
  /// whereIn caps at 30 values; joining more communities than that isn't
  /// supported yet.
  Stream<QuerySnapshot<Map<String, dynamic>>> _recognitionsStream(
      List<String> allowedGroupIds) {
    return FirebaseFirestore.instance
        .collection('recognitions')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('groupId', whereIn: allowedGroupIds.take(30).toList())
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HALO',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.users, color: accentGold),
            tooltip: 'Communities',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CommunitiesScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _communitiesStream,
        builder: (context, communitiesSnapshot) {
          if (communitiesSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: accentGold));
          }

          final communityDocs = communitiesSnapshot.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final communityNames = <String, String>{
            for (final doc in communityDocs)
              doc.id: (doc.data()['name'] as String? ?? 'Unnamed community'),
          };

          final uid = FirebaseAuth.instance.currentUser?.uid;
          final myCommunityIds = communityDocs
              .where((doc) => (doc.data()['memberIds'] as List<dynamic>? ?? [])
                  .contains(uid))
              .map((doc) => doc.id);
          final allowedGroupIds = {...myCommunityIds, defaultGroupId}.toList();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _recognitionsStream(allowedGroupIds),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _StateMessage(
                  icon: LucideIcons.alertTriangle,
                  message: 'Something went wrong loading the feed.',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: accentGold),
                );
              }

              final docs = snapshot.data?.docs ?? [];
              final allPosts = docs
                  .map((doc) => RecognitionPost.fromFirestore(doc))
                  .where((post) => post.isLive)
                  .toList();

              final groups = allPosts.map((p) => p.groupId).toSet().toList()
                ..sort();
              final hashtags = <String>{};
              for (final post in allPosts) {
                hashtags.addAll(post.normalizedHashtags);
              }

              final filteredByGroup = _selectedGroup == null
                  ? allPosts
                  : allPosts.where((p) => p.groupId == _selectedGroup).toList();
              final posts = _selectedHashtag == null
                  ? filteredByGroup
                  : filteredByGroup
                      .where((p) =>
                          p.normalizedHashtags.contains(_selectedHashtag))
                      .toList();

              return Column(
                children: [
                  if (groups.isNotEmpty)
                    _GroupChips(
                      groups: groups,
                      communityNames: communityNames,
                      selected: _selectedGroup,
                      onSelected: (group) => setState(() {
                        _selectedGroup = group;
                        _selectedHashtag = null;
                      }),
                    ),
                  if (hashtags.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All tags'),
                            selected: _selectedHashtag == null,
                            onSelected: (_) =>
                                setState(() => _selectedHashtag = null),
                          ),
                          for (final tag in hashtags.toList()..sort())
                            ChoiceChip(
                              label: Text('#$tag'),
                              selected: _selectedHashtag == tag,
                              onSelected: (_) =>
                                  setState(() => _selectedHashtag = tag),
                            ),
                        ],
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentGoldDim,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${posts.length} live in the last 48 hours',
                      style: const TextStyle(
                        color: accentGold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: posts.isEmpty
                          ? const _StateMessage(
                              icon: LucideIcons.sparkles,
                              message:
                                  'No approved recognitions yet.\nBe the first to send one.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              itemCount: posts.length,
                              itemBuilder: (context, index) =>
                                  _RecognitionCard(post: posts[index]),
                            ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupChips extends StatelessWidget {
  final List<String> groups;
  final Map<String, String> communityNames;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _GroupChips({
    required this.groups,
    required this.communityNames,
    required this.selected,
    required this.onSelected,
  });

  String _labelFor(String groupId) => communityNames[groupId] ?? 'General';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_labelFor(group)),
                selected: selected == group,
                onSelected: (_) => onSelected(group),
              ),
            ),
        ],
      ),
    );
  }
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s._-]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class _RecognitionCard extends StatelessWidget {
  final RecognitionPost post;
  const _RecognitionCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, (1 - value) * 10), child: child),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: spacingCardGap),
        child: Padding(
          padding: const EdgeInsets.all(spacingPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentGoldDim,
                      border: Border.fromBorderSide(
                          BorderSide(color: accentGoldBorder)),
                    ),
                    child: Text(
                      _initialsFor(post.recipientDisplayName),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: accentGold,
                      ),
                    ),
                  ),
                  const SizedBox(width: spacingSmallGap + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.recipientDisplayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: textPrimary,
                          ),
                        ),
                        if (!post.isAnonymous && post.senderDisplayName != null)
                          Text(
                            'From ${post.senderDisplayName}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentGold,
                            ),
                          ),
                        Text(
                          relativeTime(post.createdAt),
                          style:
                              const TextStyle(fontSize: 12, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                post.message,
                style: const TextStyle(
                    color: textPrimary, height: 1.45, fontSize: 14),
              ),
              const SizedBox(height: spacingSmallGap + 2),
              Align(
                alignment: Alignment.centerRight,
                child: _GlowButton(
                  postId: post.postId,
                  count: post.glowCount,
                  isGlowed: post
                      .isGlowedBy(FirebaseAuth.instance.currentUser?.uid ?? ''),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String postId;
  final int count;
  final bool isGlowed;
  const _GlowButton(
      {required this.postId, required this.count, required this.isGlowed});

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  // Guards against double-counting/dropped taps: without this, rapid taps
  // fire overlapping fire-and-forget writes with no feedback, so a failed
  // one (e.g. a network blip) just vanishes silently and the toggle state
  // can end up out of sync with how many times the user actually tapped.
  bool _isSending = false;

  Future<void> _handleTap() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _isSending) return;

    setState(() => _isSending = true);
    try {
      // widget.isGlowed reflects the live stream's current state, so this
      // always toggles relative to what's on screen right now.
      await RecognitionService.toggleGlow(widget.postId, uid,
          wasGlowed: widget.isGlowed);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Couldn't send glow — check your connection and try again.")),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _isSending ? null : _handleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lucide's glyphs are outline-only (no filled/duotone variant),
            // so "filled" is expressed as a solid gold badge behind the
            // icon rather than swapping to a different glyph shape.
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isGlowed ? accentGold : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.sparkle,
                color: widget.isGlowed ? bgPrimary : textMuted,
                size: 16,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${widget.count}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: widget.isGlowed ? FontWeight.w700 : FontWeight.w400,
                color: widget.isGlowed ? accentGold : textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  const _StateMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: accentGoldDim,
            ),
            child:
                Icon(icon, size: 32, color: accentGold.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: textMuted),
          ),
        ],
      ),
    );
  }
}
