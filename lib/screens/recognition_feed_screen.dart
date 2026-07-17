import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/recognition_post.dart';
import '../services/recognition_service.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Displays live, approved recognition posts across all groups, with
/// horizontally scrollable chips to filter down to one group.
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
  // Created once rather than in build() — recreating the stream on every
  // rebuild (e.g. from the bottom nav switching tabs) would make
  // StreamBuilder drop its subscription and reset to ConnectionState.waiting
  // each time, looking like the feed never loads.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  // null = "All" chip selected.
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('recognitions')
        .where('moderationStatus', isEqualTo: 'approved')
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
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
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
          final allPosts =
              docs.map((doc) => RecognitionPost.fromFirestore(doc)).toList();

          final groups = allPosts.map((p) => p.groupId).toSet().toList()..sort();
          final posts = _selectedGroup == null
              ? allPosts
              : allPosts.where((p) => p.groupId == _selectedGroup).toList();

          return Column(
            children: [
              if (groups.isNotEmpty) _GroupChips(
                groups: groups,
                selected: _selectedGroup,
                onSelected: (group) => setState(() => _selectedGroup = group),
              ),
              Expanded(
                child: posts.isEmpty
                    ? const _StateMessage(
                        icon: LucideIcons.sparkles,
                        message: 'No approved recognitions yet.\nBe the first to send one.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: posts.length,
                        itemBuilder: (context, index) => _RecognitionCard(post: posts[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupChips extends StatelessWidget {
  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _GroupChips({required this.groups, required this.selected, required this.onSelected});

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
                label: Text(group),
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
        child: Transform.translate(offset: Offset(0, (1 - value) * 10), child: child),
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
                      border: Border.fromBorderSide(BorderSide(color: accentGoldBorder)),
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
                        Text(
                          relativeTime(post.createdAt),
                          style: const TextStyle(fontSize: 12, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                post.message,
                style: const TextStyle(color: textPrimary, height: 1.45, fontSize: 14),
              ),
              const SizedBox(height: spacingSmallGap + 2),
              Align(
                alignment: Alignment.centerRight,
                child: _GlowButton(postId: post.postId, count: post.glowCount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowButton extends StatelessWidget {
  final String postId;
  final int count;
  const _GlowButton({required this.postId, required this.count});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => RecognitionService.glowRecognition(postId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.sparkle, color: accentGold, size: 18),
            const SizedBox(width: 6),
            Text('$count', style: const TextStyle(fontSize: 12, color: accentGold)),
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
            child: Icon(icon, size: 32, color: accentGold.withValues(alpha: 0.8)),
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
