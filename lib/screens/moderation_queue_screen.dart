import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/incident.dart';
import '../services/moderation_service.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Layer 2 review queue.
///
/// Layer 1 is deterministic and runs at submit time. This is the part that
/// actually needs judgement, so it is deliberately a separate surface with a
/// higher bar: every vote is permanent, the tally is recomputed server-side,
/// and a report cannot reach a conclusion until enough people have looked.
///
/// An empty queue is a normal, healthy state and says so — a moderation tool
/// that always has work to do is either badly tuned or being ignored.
class ModerationQueueScreen extends StatelessWidget {
  const ModerationQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report review'),
        actions: [
          if (uid != null)
            IconButton(
              tooltip: 'Moderation rules',
              onPressed: () => _showPolicy(context),
              icon: const Icon(LucideIcons.scale, size: 19),
            ),
        ],
      ),
      body: uid == null
          ? const _SignedOutNotice()
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('incidents')
                  .where(
                    'moderationStatus',
                    whereIn: [
                      IncidentModerationStatus.underReview.name,
                      IncidentModerationStatus.held.name,
                    ],
                  )
                  .orderBy('reportedAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _QueueState(
                    icon: LucideIcons.wifiOff,
                    title: 'Could not load the review queue',
                    detail: '${snapshot.error}',
                    actionLabel: 'Retry',
                    onAction: () => Navigator.of(context).pop(),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const _QueueState(
                    icon: LucideIcons.circleCheck,
                    title: 'Nothing waiting',
                    detail: 'No reports are currently flagged for review. '
                        'That is the expected state, not a sign the queue is '
                        'broken.',
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _QueueItem(doc: docs[index], reviewerId: uid),
                );
              },
            ),
    );
  }

  static void _showPolicy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (context) => const _ModerationPolicySheet(),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.doc, required this.reviewerId});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String reviewerId;

  Incident get incident => Incident.fromFirestore(doc);

  List<ModerationFlag> get flags => [
        for (final raw in (doc.data()['layer1Flags'] as List? ?? const []))
          if (ModerationFlag.tryParse(raw) case final flag?) flag,
      ];

  Map<String, dynamic> get layer2 =>
      doc.data()['layer2'] as Map<String, dynamic>? ?? const {};

  int get confirm => (layer2['confirm'] as num?)?.toInt() ?? 0;
  int get reject => (layer2['reject'] as num?)?.toInt() ?? 0;

  Future<void> _vote(BuildContext context, String verdict) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _VoteReasonDialog(verdict: verdict),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ModerationService.recordReviewVote(
        incidentId: doc.id,
        reviewerId: reviewerId,
        verdict: verdict,
        reason: reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verdict == 'confirm'
                ? 'Confirmed. The report is now visible as community-validated.'
                : 'Rejected. The report has been removed from public visibility.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is StateError
              ? error.message
              : 'Could not record that vote.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final status = IncidentModerationStatus.fromValue(
      data['moderationStatus'] as String?,
    );
    final point = ll.LatLng(incident.latitude, incident.longitude);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status == IncidentModerationStatus.held
                      ? colorRed.withValues(alpha: 0.14)
                      : accentGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(chipRadius),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status == IncidentModerationStatus.held
                        ? colorRed
                        : accentGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _labelFor(incident.type),
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                relativeTime(incident.reportedAt),
                style: const TextStyle(color: textMuted2, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${point.latitude.toStringAsFixed(4)}, '
            '${point.longitude.toStringAsFixed(4)}'
            '${incident.locationSource == null ? '' : ' - ${incident.locationSource}'}',
            style: const TextStyle(color: textMuted2, fontSize: 11.5),
          ),
          if (incident.description != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: bgSurface3,
                borderRadius: BorderRadius.circular(chipRadius),
              ),
              child: Text(
                incident.description!,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Why Layer 1 flagged this',
              style: TextStyle(
                color: textMuted2,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            for (final flag in flags)
              Text(
                '- ${flag.detail}',
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Identity: ${incident.isFullyAnonymous ? 'anonymous (no handle stored)' : 'pseudonymous handle present, never shown to reviewers'}',
            style: const TextStyle(
              color: textMuted2,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _VoteButton(
                  icon: LucideIcons.thumbsUp,
                  label: 'Confirm',
                  count: confirm,
                  color: colorGreen,
                  onPressed: () => _vote(context, 'confirm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VoteButton(
                  icon: LucideIcons.thumbsDown,
                  label: 'Reject',
                  count: reject,
                  color: colorRed,
                  onPressed: () => _vote(context, 'reject'),
                ),
              ),
            ],
          ),
          if (confirm + reject > 0) ...[
            const SizedBox(height: 6),
            Text(
              confirm + reject >= 3
                  ? 'Decision reached by the review panel.'
                  : 'Needs ${3 - (confirm + reject)} more vote${3 - (confirm + reject) == 1 ? '' : 's'} before it changes status.',
              style: TextStyle(
                color: confirm + reject >= 3 ? accentGold : textMuted2,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _labelFor(IncidentType type) {
    switch (type) {
      case IncidentType.harassment:
        return 'Harassment';
      case IncidentType.poorLighting:
        return 'Poor lighting';
      case IncidentType.isolated:
        return 'Isolated / no one around';
      case IncidentType.drunkCrowd:
        return 'Drunk crowd';
      case IncidentType.other:
        return 'Other';
    }
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(count == 0 ? label : '$label ($count)'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}

class _VoteReasonDialog extends StatefulWidget {
  const _VoteReasonDialog({required this.verdict});

  final String verdict;

  @override
  State<_VoteReasonDialog> createState() => _VoteReasonDialogState();
}

class _VoteReasonDialogState extends State<_VoteReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirming = widget.verdict == 'confirm';
    return AlertDialog(
      backgroundColor: bgSurface2,
      title: Text(confirming ? 'Confirm this report' : 'Reject this report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            confirming
                ? 'A short reason helps the next reviewer and is kept with '
                    'your vote.'
                : 'Rejection is permanent. Say why, so the reporter is not '
                    'silently ignored.',
            style: const TextStyle(color: textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Reason (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(confirming ? 'Confirm' : 'Reject'),
        ),
      ],
    );
  }
}

class _ModerationPolicySheet extends StatelessWidget {
  const _ModerationPolicySheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How reports are moderated',
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            const _PolicyPoint(
              icon: LucideIcons.bot,
              title: 'Layer 1 - automatic, at submit time',
              body: 'A fixed rule set runs on the reporter\'s own device '
                  'before the report is written. It looks for a small number '
                  'of specific problems: contact details pasted into the text, '
                  'personal accusations instead of descriptions, and empty '
                  '"other" reports. It is deterministic on purpose - we can '
                  'tell you exactly why it acted.',
            ),
            const SizedBox(height: 12),
            const _PolicyPoint(
              icon: LucideIcons.users,
              title: 'Layer 2 - community review',
              body: 'Reports Layer 1 flags stay visible but marked "not yet '
                  'confirmed", or are held off the map entirely. People vote '
                  'to confirm or reject. Three votes are needed and a strict '
                  'majority decides; a tie stays undecided rather than '
                  'defaulting.',
            ),
            const SizedBox(height: 12),
            const _PolicyPoint(
              icon: LucideIcons.eyeOff,
              title: 'Reviewers never see who reported',
              body: 'The report does not contain an account id in either mode. '
                  'A pseudonymous handle exists for rate limiting and is not '
                  'shown in this queue or anywhere else in the app.',
            ),
            const SizedBox(height: 12),
            const _PolicyPoint(
              icon: LucideIcons.badgeCheck,
              title: 'What is not moderated',
              body: 'Layer 1 does not judge whether an incident "really '
                  'happened". It cannot - only people present can know that. '
                  'It only screens for disclosure and abuse problems.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyPoint extends StatelessWidget {
  const _PolicyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: accentGold),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueState extends StatelessWidget {
  const _QueueState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: textMuted2),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice();

  @override
  Widget build(BuildContext context) {
    return const _QueueState(
      icon: LucideIcons.logIn,
      title: 'Sign in to review reports',
      detail: 'Reviews are tied to an account so a vote cannot be cast twice '
          'or from a throwaway identity.',
    );
  }
}
