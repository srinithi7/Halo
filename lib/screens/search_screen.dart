import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/recognition_post.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Search bar over the groups/tags used across existing recognitions —
/// tapping one shows that group's approved posts below.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('recognitions')
        .where('moderationStatus', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true)
        .snapshots();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        padding: const EdgeInsets.symmetric(horizontal: spacingPadding, vertical: spacingSmallGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search groups...',
                prefixIcon: Icon(LucideIcons.search, size: 18, color: accentGold),
              ),
            ),
            const SizedBox(height: spacingCardGap),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _CenterMessage(
                      icon: LucideIcons.alertTriangle,
                      message: 'Something went wrong loading search results.',
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: accentGold));
                  }

                  final posts = (snapshot.data?.docs ?? [])
                      .map((doc) => RecognitionPost.fromFirestore(doc))
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
                      .where((g) => g.toLowerCase().contains(_query))
                      .toList()
                    ..sort();

                  if (_selectedGroup != null) {
                    final groupPosts = posts.where((p) => p.groupId == _selectedGroup).toList();
                    return _GroupResults(
                      group: _selectedGroup!,
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
                    separatorBuilder: (_, __) => const SizedBox(height: spacingSmallGap),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(LucideIcons.hash, color: accentGold),
                          title: Text(group, style: const TextStyle(color: textPrimary)),
                          subtitle: Text(
                            '${counts[group]} recognition${counts[group] == 1 ? '' : 's'}',
                            style: const TextStyle(color: textMuted),
                          ),
                          trailing: const Icon(LucideIcons.chevronRight, color: textMuted, size: 18),
                          onTap: () => setState(() => _selectedGroup = group),
                        ),
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

  const _GroupResults({required this.group, required this.posts, required this.onBack});

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
            separatorBuilder: (_, __) => const SizedBox(height: spacingSmallGap),
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
                        style: const TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(post.message, style: const TextStyle(color: textPrimary, height: 1.4)),
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
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: textMuted)),
        ],
      ),
    );
  }
}
