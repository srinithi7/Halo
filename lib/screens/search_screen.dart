import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../constants.dart';
import '../models/recognition_post.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Search over the communities the viewer has joined (plus General) —
/// scoped the same way as the main Feed, so Search can't be used to read
/// recognitions from communities you're not actually a member of.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // Communities are the real backing for groupId now (see
  // RecognitionSubmitScreen) — resolves a post's groupId to a display
  // name, same as the feed's chips, and (filtered to ones this viewer
  // belongs to) scopes the recognitions query below.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _communitiesStream;
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _communitiesStream =
        FirebaseFirestore.instance.collection('communities').snapshots();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Same scoping as RecognitionFeedScreen._recognitionsStream — see that
  /// comment for why this is a method rather than a stored stream, and for
  /// the whereIn 30-value cap.
  Stream<QuerySnapshot<Map<String, dynamic>>> _recognitionsStream(
      List<String> allowedGroupIds) {
    return FirebaseFirestore.instance
        .collection('recognitions')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('groupId', whereIn: allowedGroupIds.take(30).toList())
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  bool _matchesQuery(RecognitionPost post, String query) {
    if (query.isEmpty) return true;
    final haystack = [
      post.message,
      post.recipientDisplayName,
      post.areaName ?? '',
      post.category,
      ...post.normalizedHashtags,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.search, color: accentGold, size: 20),
            SizedBox(width: 8),
            Text('Search'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: spacingPadding, vertical: spacingSmallGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search groups...',
                prefixIcon:
                    Icon(LucideIcons.search, size: 18, color: accentGold),
              ),
            ),
            const SizedBox(height: spacingCardGap),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _communitiesStream,
                builder: (context, communitiesSnapshot) {
                  if (communitiesSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: accentGold));
                  }

                  final communityDocs = communitiesSnapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  final communityNames = <String, String>{
                    for (final doc in communityDocs)
                      doc.id: (doc.data()['name'] as String? ??
                          'Unnamed community'),
                  };
                  String labelFor(String groupId) =>
                      communityNames[groupId] ?? 'General';

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  final myCommunityIds = communityDocs
                      .where((doc) =>
                          (doc.data()['memberIds'] as List<dynamic>? ?? [])
                              .contains(uid))
                      .map((doc) => doc.id);
                  final allowedGroupIds =
                      {...myCommunityIds, defaultGroupId}.toList();

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _recognitionsStream(allowedGroupIds),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const _CenterMessage(
                          icon: LucideIcons.alertTriangle,
                          message:
                              'Something went wrong loading search results.',
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child:
                                CircularProgressIndicator(color: accentGold));
                      }

                      final posts = (snapshot.data?.docs ?? [])
                          .map((doc) => RecognitionPost.fromFirestore(doc))
                          .where((post) => post.isLive)
                          .where((post) => _matchesQuery(post, _query))
                          .toList();

                      if (posts.isEmpty) {
                        return const _CenterMessage(
                          icon: LucideIcons.folderSearch,
                          message: 'No recognitions yet to search.',
                        );
                      }

                      final counts = <String, int>{};
                      for (final post in posts) {
                        counts[post.groupId] = (counts[post.groupId] ?? 0) + 1;
                      }
                      final groups = counts.keys
                          .where((g) =>
                              labelFor(g).toLowerCase().contains(_query) ||
                              _query.isEmpty)
                          .toList()
                        ..sort((a, b) => labelFor(a).compareTo(labelFor(b)));

                      if (_selectedGroup != null) {
                        final groupPosts = posts
                            .where((p) => p.groupId == _selectedGroup)
                            .toList();
                        return _GroupResults(
                          group: labelFor(_selectedGroup!),
                          posts: groupPosts,
                          onBack: () => setState(() => _selectedGroup = null),
                        );
                      }

                      if (groups.isEmpty) {
                        return const _CenterMessage(
                          icon: LucideIcons.folderSearch,
                          message: 'No matching groups.',
                        );
                      }

                      return ListView.separated(
                        itemCount: groups.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: spacingSmallGap),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(LucideIcons.hash,
                                  color: accentGold),
                              title: Text(labelFor(group),
                                  style: const TextStyle(color: textPrimary)),
                              subtitle: Text(
                                '${counts[group]} recognition${counts[group] == 1 ? '' : 's'}',
                                style: const TextStyle(color: textMuted),
                              ),
                              trailing: const Icon(LucideIcons.chevronRight,
                                  color: textMuted, size: 18),
                              onTap: () =>
                                  setState(() => _selectedGroup = group),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupResults extends StatelessWidget {
  final String group;
  final List<RecognitionPost> posts;
  final VoidCallback onBack;

  const _GroupResults(
      {required this.group, required this.posts, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(LucideIcons.arrowLeft, size: 16),
          label: Text('All groups · $group'),
        ),
        const SizedBox(height: spacingSmallGap),
        Expanded(
          child: ListView.separated(
            itemCount: posts.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: spacingSmallGap),
            itemBuilder: (context, index) {
              final post = posts[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(spacingPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'To: ${post.recipientDisplayName}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                      if (!post.isAnonymous && post.senderDisplayName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'From ${post.senderDisplayName}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentGold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(post.message,
                          style:
                              const TextStyle(color: textPrimary, height: 1.4)),
                      const SizedBox(height: 6),
                      Text(
                        relativeTime(post.createdAt),
                        style: const TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  const _CenterMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: accentGold.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: textMuted)),
        ],
      ),
    );
  }
}
