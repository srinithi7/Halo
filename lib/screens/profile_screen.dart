import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/recognition_post.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';
import 'phone_login_screen.dart';

/// Shows recognitions the signed-in user has *received* — never sent, to
/// keep the anonymity contract intact (a sent-items view would let a user
/// cross-reference their own posts against the feed and start inferring
/// senderId patterns for others, which is exactly what that invariant
/// exists to prevent). No personality titles, no memory box — just a
/// clean summary.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _receivedStream;
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _profileFuture;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _receivedStream = FirebaseFirestore.instance
        .collection('recognitions')
        .where('recipientId', isEqualTo: uid)
        .where('moderationStatus', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true)
        .snapshots();
    _profileFuture = FirebaseFirestore.instance.collection('users').doc(uid).get();
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.userCircle, color: accentGold, size: 20),
            SizedBox(width: 8),
            Text('Profile'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: textMuted),
            tooltip: 'Log out',
            onPressed: _signOut,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _profileFuture,
        builder: (context, profileSnapshot) {
          final name = profileSnapshot.data?.data()?['name'] as String? ?? '';

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _receivedStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _CenterMessage(
                  icon: LucideIcons.alertTriangle,
                  message: 'Something went wrong loading your profile.',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: accentGold));
              }

              final docs = snapshot.data?.docs ?? [];
              final posts = docs.map((doc) => RecognitionPost.fromFirestore(doc)).toList();
              final totalGlows = posts.fold<int>(0, (total, p) => total + p.glowCount);

              return ListView(
                padding: const EdgeInsets.all(spacingPadding),
                children: [
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentGoldDim,
                            border: Border.fromBorderSide(BorderSide(color: accentGoldBorder)),
                          ),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: accentGold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          name.isNotEmpty ? name : 'HALO user',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          user.phoneNumber ?? '',
                          style: const TextStyle(fontSize: 13, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(value: '${posts.length}', label: 'Received'),
                      ),
                      const SizedBox(width: spacingCardGap),
                      Expanded(
                        child: _StatCard(value: '$totalGlows', label: 'Glows received'),
                      ),
                    ],
                  ),
                  const SizedBox(height: spacingCardGap + 8),
                  if (posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'Nothing yet — recognitions sent to you will show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted),
                        ),
                      ),
                    )
                  else
                    for (final post in posts) _ReceivedCard(post: post),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: accentGold),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ReceivedCard extends StatelessWidget {
  final RecognitionPost post;
  const _ReceivedCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: spacingSmallGap + 4),
      child: Padding(
        padding: const EdgeInsets.all(spacingPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.message,
              style: const TextStyle(color: textPrimary, height: 1.4, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  relativeTime(post.createdAt),
                  style: const TextStyle(fontSize: 12, color: textMuted),
                ),
                const Spacer(),
                const Icon(LucideIcons.sparkle, size: 14, color: accentGold),
                const SizedBox(width: 4),
                Text(
                  '${post.glowCount}',
                  style: const TextStyle(fontSize: 12, color: accentGold),
                ),
              ],
            ),
          ],
        ),
      ),
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
