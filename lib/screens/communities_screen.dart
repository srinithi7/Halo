import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/community.dart';
import '../models/recognition_post.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/seed_demo_data.dart';
import '../utils/unsung_hero.dart';
import 'community_area_picker_screen.dart';
import 'community_chat_screen.dart';

/// Browse, join, and create communities — the membership-backed container
/// recognitions are now submitted into (see RecognitionSubmitScreen),
/// replacing the old free-text hashtag/groupId placeholder. Tapping a
/// community opens its Unsung Hero ranking.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('communities')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _seedDemoData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: bgSurface2,
        title:
            const Text('Seed demo data?', style: TextStyle(color: textPrimary)),
        content: const Text(
          'Adds 20 mock users across 3 communities (Design Team, Engineering, '
          'Customer Support) with recognitions already in place so each one has '
          'an Unsung Hero to show. Safe to run more than once — it skips if '
          'already seeded.',
          style: TextStyle(color: textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Seed'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await seedDemoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Demo data seeded — open a community to see it.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seeding failed: $e')),
      );
    }
  }

  Future<void> _editCommunity(Community community) async {
    final nameController = TextEditingController(text: community.name);
    final descController = TextEditingController(text: community.description);
    final initialArea = community.footprint;
    var area = initialArea == null
        ? null
        : CommunityArea(
            latitude: initialArea.point.latitude,
            longitude: initialArea.point.longitude,
            radiusMeters: initialArea.radius,
          );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit community',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: textPrimary),
              ),
              const SizedBox(height: 10),
              _AreaRow(
                area: area,
                onPick: () async {
                  final picked = await _pickArea(initial: area);
                  if (picked != null) setSheetState(() => area = picked);
                },
                onClear: () => setSheetState(() => area = null),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;
    if (nameController.text.trim().isNotEmpty) {
      await CommunityService.updateDetails(
        community.id,
        name: nameController.text.trim(),
        description: descController.text.trim(),
      );
    }
    final areaChanged = area?.latitude != initialArea?.point.latitude ||
        area?.longitude != initialArea?.point.longitude ||
        area?.radiusMeters != initialArea?.radius;
    if (areaChanged) {
      await CommunityService.updateArea(
        community.id,
        latitude: area?.latitude,
        longitude: area?.longitude,
        radiusMeters: area?.radiusMeters,
      );
    }
  }

  String _radiusLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  Future<CommunityArea?> _pickArea({CommunityArea? initial}) async {
    return Navigator.of(context).push<CommunityArea>(
      MaterialPageRoute(
        builder: (_) => CommunityAreaPickerScreen(initialArea: initial),
      ),
    );
  }

  Future<void> _createCommunity() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    var area = await _pickArea();
    if (!mounted) return;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New community',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: textPrimary),
              ),
              const SizedBox(height: 10),
              _AreaRow(
                area: area,
                onPick: () async {
                  final picked = await _pickArea(initial: area);
                  if (picked != null) setSheetState(() => area = picked);
                },
                onClear: () => setSheetState(() => area = null),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'e.g. Design Team'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: Text(
                  area == null ? 'Create without an area' : 'Create',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (created != true || nameController.text.trim().isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await CommunityService.create(
      name: nameController.text.trim(),
      description: descController.text.trim(),
      creatorUid: uid,
      latitude: area?.latitude,
      longitude: area?.longitude,
      radiusMeters: area?.radiusMeters,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.users, color: accentGold, size: 20),
            SizedBox(width: 8),
            Text('Communities'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.sprout, color: accentGold),
            tooltip: 'Seed demo data',
            onPressed: _seedDemoData,
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus, color: accentGold),
            tooltip: 'New community',
            onPressed: _createCommunity,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Something went wrong loading communities.',
                  style: TextStyle(color: textMuted)),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: accentGold));
          }

          final communities = (snapshot.data?.docs ?? [])
              .map((doc) => Community.fromFirestore(doc))
              .toList();

          if (communities.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(spacingPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.usersRound,
                        size: 40, color: textMuted),
                    const SizedBox(height: 12),
                    const Text(
                      'No communities yet. Start one to give and\ntrack recognition within your own group.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textMuted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _createCommunity,
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: const Text('Create a community'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(spacingPadding),
            itemCount: communities.length,
            itemBuilder: (context, index) {
              final community = communities[index];
              final isMember = community.hasMember(uid);
              final footprint = community.footprint;
              final members = community.memberIds.length;
              final lines = <String>[
                if (community.description.isNotEmpty) community.description,
                '$members member${members == 1 ? '' : 's'}'
                    '${footprint == null ? '' : ' · ${_radiusLabel(footprint.radius)} area on map'}',
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: spacingCardGap),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(spacingSmallGap + 4),
                  title: Text(community.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: textPrimary)),
                  subtitle: Text(
                    lines.join('\n'),
                    style: const TextStyle(color: textMuted, fontSize: 12),
                  ),
                  isThreeLine: community.description.isNotEmpty,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (community.createdBy == uid)
                        IconButton(
                          icon: const Icon(LucideIcons.pencil,
                              size: 18, color: textMuted),
                          tooltip: 'Rename',
                          onPressed: () => _editCommunity(community),
                        ),
                      TextButton(
                        onPressed: () => isMember
                            ? CommunityService.leave(community.id, uid)
                            : CommunityService.join(community.id, uid),
                        child: Text(isMember ? 'Leave' : 'Join'),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            CommunityDetailScreen(community: community)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.area,
    required this.onPick,
    required this.onClear,
  });

  final CommunityArea? area;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final current = area;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgSurface3,
        borderRadius: BorderRadius.circular(buttonRadius),
        border: Border.all(
          color: current == null ? borderColor : accentPurple,
        ),
      ),
      child: Row(
        children: [
          Icon(
            current == null ? LucideIcons.mapPinOff : LucideIcons.circleDot,
            color: current == null ? textMuted : accentPurple,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current == null ? 'No map area' : 'Map area set',
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  current == null
                      ? 'Community stays a name-based group'
                      : '${current.latitude.toStringAsFixed(3)}, '
                          '${current.longitude.toStringAsFixed(3)} · '
                          '${current.radiusMeters.round()} m radius',
                  style: const TextStyle(color: textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (current != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
          TextButton(onPressed: onPick, child: const Text('Choose')),
        ],
      ),
    );
  }
}

/// A community's home: its chat (with HALOs interleaved live) and its
/// Unsung Hero ranking, as two tabs.
class CommunityDetailScreen extends StatelessWidget {
  const CommunityDetailScreen({super.key, required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(community.name),
          bottom: const TabBar(
            tabs: [
              Tab(
                  icon: Icon(LucideIcons.messagesSquare, size: 18),
                  text: 'Chat'),
              Tab(icon: Icon(LucideIcons.crown, size: 18), text: 'Unsung Hero'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            CommunityChatScreen(community: community),
            _UnsungHeroTab(community: community),
          ],
        ),
      ),
    );
  }
}

/// One community's Unsung Hero ranking, computed client-side from its
/// approved recognitions — see lib/utils/unsung_hero.dart for the scoring
/// rationale. Recomputed live as the underlying recognitions stream
/// updates, same pattern as the main feed.
class _UnsungHeroTab extends StatelessWidget {
  const _UnsungHeroTab({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('recognitions')
        .where('groupId', isEqualTo: community.id)
        .where('moderationStatus', isEqualTo: 'approved')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Something went wrong loading this community.',
                style: TextStyle(color: textMuted)),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: accentGold));
        }

        final posts = (snapshot.data?.docs ?? [])
            .map((doc) => RecognitionPost.fromFirestore(doc))
            .toList();
        final ranking = rankUnsungHeroes(posts);

        if (ranking.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(spacingPadding),
              child: Text(
                'Not enough recognitions yet to name an Unsung Hero here —\n'
                'someone needs at least 2 approved recognitions to qualify.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textMuted),
              ),
            ),
          );
        }

        final hero = ranking.first;
        final runnersUp = ranking.skip(1).take(4).toList();

        return ListView(
          padding: const EdgeInsets.all(spacingPadding),
          children: [
            _UnsungHeroCard(candidate: hero),
            if (runnersUp.isNotEmpty) ...[
              const SizedBox(height: spacingCardGap + 4),
              const Text('Also standing out',
                  style: TextStyle(
                      color: textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: spacingSmallGap),
              for (final candidate in runnersUp)
                _RunnerUpTile(candidate: candidate),
            ],
          ],
        );
      },
    );
  }
}

class _UnsungHeroCard extends StatelessWidget {
  const _UnsungHeroCard({required this.candidate});
  final UnsungHeroCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: accentGoldDim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: const BorderSide(color: accentGoldBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(spacingPadding + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(LucideIcons.crown, color: accentGold, size: 20),
                SizedBox(width: 8),
                Text('Unsung Hero',
                    style: TextStyle(
                        color: accentGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              candidate.recipientDisplayName,
              style: const TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _StatChip(
                    label: 'Recognitions',
                    value: '${candidate.recognitionCount}'),
                _StatChip(
                    label: 'People', value: '${candidate.distinctSenderCount}'),
                _StatChip(label: 'Glows', value: '${candidate.totalGlows}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        Text(label, style: const TextStyle(color: textMuted, fontSize: 11)),
      ],
    );
  }
}

class _RunnerUpTile extends StatelessWidget {
  const _RunnerUpTile({required this.candidate});
  final UnsungHeroCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: spacingSmallGap),
      child: ListTile(
        dense: true,
        leading: const Icon(LucideIcons.award, color: textMuted, size: 18),
        title: Text(candidate.recipientDisplayName,
            style: const TextStyle(color: textPrimary)),
        trailing: Text(
          '${candidate.recognitionCount} recognitions · ${candidate.distinctSenderCount} people',
          style: const TextStyle(color: textMuted, fontSize: 11),
        ),
      ),
    );
  }
}
