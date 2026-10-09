import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';

/// Layer 1 verdict: the automatic, deterministic screen run at submit time.
enum Layer1Verdict {
  /// Nothing objectionable found. Publishes immediately.
  clear,

  /// Publishes, but is tagged so Layer 2 can prioritise it.
  flagForReview,

  /// Held back from the public map pending a human decision.
  hold,

  /// Rejected outright. Does not enter the queue at all.
  reject;

  static Layer1Verdict fromValue(String? value) {
    return Layer1Verdict.values.firstWhere(
      (v) => v.name == value,
      orElse: () => Layer1Verdict.clear,
    );
  }
}

/// A single reason a report was flagged, kept machine-readable so the UI can
/// explain itself and moderation logs stay auditable.
class ModerationFlag {
  const ModerationFlag(this.code, this.detail);

  /// Stable identifier, e.g. `phone_number_in_text`.
  final String code;
  final String detail;

  Map<String, dynamic> toFirestore() => {'code': code, 'detail': detail};

  static ModerationFlag? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    if (code is! String) return null;
    return ModerationFlag(code, raw['detail'] as String? ?? '');
  }

  @override
  String toString() => 'ModerationFlag($code)';
}

/// The moderation state carried on every incident.
///
/// Two layers, deliberately separated:
///  * **Layer 1** is deterministic and runs on-device at submit time. It is a
///    cheap screen for the obvious problems — pasted phone numbers, personal
///    accusations, junk. It is not an AI judgement and does not pretend to be.
///  * **Layer 2** is community/editorial review of what Layer 1 could not
///    settle, and it is the only layer allowed to reject.
enum IncidentModerationStatus {
  /// Layer 1 found nothing. Visible to everyone.
  published,

  /// Layer 1 tagged it. Visible, but marked as unconfirmed.
  underReview,

  /// Layer 1 held it. Not visible on the map until a reviewer decides.
  held,

  /// Layer 2 confirmed it.
  confirmed,

  /// Layer 2 rejected it. Retained for audit, never shown.
  rejected;

  static IncidentModerationStatus fromValue(String? value) {
    return IncidentModerationStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => IncidentModerationStatus.published,
    );
  }

  /// Whether a report in this state should appear on the public map.
  ///
  /// `underReview` and `published` are both visible, but the UI marks the
  /// former as unconfirmed — hiding it would lose real signal, and showing it
  /// unmarked would lend it authority it has not earned.
  bool get isPubliclyVisible => switch (this) {
        IncidentModerationStatus.published ||
        IncidentModerationStatus.underReview ||
        IncidentModerationStatus.confirmed =>
          true,
        IncidentModerationStatus.held ||
        IncidentModerationStatus.rejected =>
          false,
      };

  String get label {
    switch (this) {
      case IncidentModerationStatus.published:
        return 'Published';
      case IncidentModerationStatus.underReview:
        return 'Not yet confirmed';
      case IncidentModerationStatus.held:
        return 'Held for review';
      case IncidentModerationStatus.confirmed:
        return 'Community confirmed';
      case IncidentModerationStatus.rejected:
        return 'Rejected';
    }
  }
}

/// Layer 1: the automatic screen.
///
/// This is intentionally rules-based, not a classifier. A deterministic screen
/// that a user can be told exactly why it fired is auditable and testable in
/// a way that an opaque model is not — and for a safety tool, "we can explain
/// why this was held" is a requirement, not a nicety.
class ModerationService {
  ModerationService._();

  // Deliberately coarse. This is a spam/privacy screen, not abuse detection.
  static final _phonePattern = RegExp(
    r'(?:\+?\d[\d\s\-]{7,}\d)',
  );
  static final _urlPattern = RegExp(
    r'(?:https?://|www\.)\S+',
    caseSensitive: false,
  );
  static final _emailPattern = RegExp(
    r'[\w.+-]+@[\w-]+\.[\w.-]+',
  );

  /// Words that turn a report into a personal accusation, which is both a
  /// legal risk and a reason the reporter may be targeted.
  static const _accusatoryTerms = <String>[
    'thief',
    'crook',
    'chutya',
    'bitch',
    'whore',
    'harlot',
    'prostitute',
    'pervert',
    'molester',
    'rapist',
    'trafficker',
  ];

  /// Layer 1 decision plus the reasons behind it.
  static ({Layer1Verdict verdict, List<ModerationFlag> flags}) evaluate({
    required IncidentType type,
    String? description,
  }) {
    final text = (description ?? '').trim();
    final flags = <ModerationFlag>[];

    if (text.contains(_phonePattern)) {
      flags.add(
        const ModerationFlag(
          'phone_number_in_text',
          'A phone number appears in the description, which can expose the '
              'reporter to harassment.',
        ),
      );
    }
    if (text.contains(_urlPattern) || text.contains(_emailPattern)) {
      flags.add(
        const ModerationFlag(
          'contact_detail_in_text',
          'A link or email address appears in the description.',
        ),
      );
    }
    final lower = text.toLowerCase();
    final accusatory = _accusatoryTerms.where(lower.contains).toList();
    if (accusatory.isNotEmpty) {
      flags.add(
        ModerationFlag(
          'accusatory_language',
          'Names someone as a criminal rather than describing what happened: '
              '${accusatory.take(3).join(', ')}.',
        ),
      );
    }
    if (type == IncidentType.other && text.isEmpty) {
      flags.add(
        const ModerationFlag(
          'empty_detail',
          '"Other" was chosen with no description, so there is nothing to '
              'assess.',
        ),
      );
    }

    final verdict = _verdictFor(flags);
    return (verdict: verdict, flags: flags);
  }

  /// Flags that are disqualifying on their own, regardless of what else is
  /// wrong with the report.
  ///
  /// Explicit rather than count-based, because "two problems" and "one
  /// disqualifying problem" are different rules and lumping them together
  /// makes it impossible to reason about a specific case.
  static const _holdOnAlone = {'empty_detail'};

  static Layer1Verdict _verdictFor(List<ModerationFlag> flags) {
    if (flags.isEmpty) return Layer1Verdict.clear;
    if (flags.any((flag) => _holdOnAlone.contains(flag.code))) {
      return Layer1Verdict.hold;
    }
    if (flags.length >= 2) return Layer1Verdict.hold;
    return Layer1Verdict.flagForReview;
  }

  /// The moderation fields written at submit time.
  ///
  /// A held report is still stored, never dropped: dropping it would destroy
  /// the evidence a reviewer needs, and would make a rejection unappealable.
  static Map<String, dynamic> initialStatus({
    required Layer1Verdict verdict,
    required List<ModerationFlag> flags,
    required DateTime evaluatedAt,
  }) {
    final status = switch (verdict) {
      Layer1Verdict.clear => IncidentModerationStatus.published,
      Layer1Verdict.flagForReview => IncidentModerationStatus.underReview,
      Layer1Verdict.hold ||
      Layer1Verdict.reject =>
        IncidentModerationStatus.held,
    };
    return {
      'moderationStatus': status.name,
      'layer1Verdict': verdict.name,
      'layer1Flags': [for (final flag in flags) flag.toFirestore()],
      'moderatedAt': Timestamp.fromDate(evaluatedAt),
      'layer2': const {
        'verdict': 'pending',
        'votes': 0,
        'confirm': 0,
        'reject': 0
      },
    };
  }

  /// Layer 2 tally: what a reviewer queue should act on.
  static ({IncidentModerationStatus status, int confirm, int reject})
      reviewOutcomeFromVotes({
    required int confirm,
    required int reject,
    int reviewThreshold = 3,
  }) {
    if (confirm + reject < reviewThreshold) {
      return (
        status: IncidentModerationStatus.underReview,
        confirm: confirm,
        reject: reject,
      );
    }
    // Strict majority of cast votes, with a tie staying undecided rather
    // than defaulting to the convenient answer.
    if (confirm > reject) {
      return (
        status: IncidentModerationStatus.confirmed,
        confirm: confirm,
        reject: reject,
      );
    }
    if (reject > confirm) {
      return (
        status: IncidentModerationStatus.rejected,
        confirm: confirm,
        reject: reject,
      );
    }
    return (
      status: IncidentModerationStatus.underReview,
      confirm: confirm,
      reject: reject,
    );
  }

  static ({IncidentModerationStatus status, int confirm, int reject})
      applyCommunityReview({
    required int confirm,
    required int reject,
    int reviewThreshold = 3,
  }) =>
          reviewOutcomeFromVotes(
            confirm: confirm,
            reject: reject,
            reviewThreshold: reviewThreshold,
          );

  /// Records one review vote and immediately recomputes the incident state.
  ///
  /// This is the missing write path behind the queue: a vote was being logged
  /// as a subcollection, but never persisted back to the parent incident. The
  /// decision is therefore updated in-place so the map and queue both reflect
  /// the latest moderation outcome.
  static Future<void> recordReviewVote({
    required String incidentId,
    required String reviewerId,
    required String verdict,
    String? reason,
  }) async {
    if (verdict != 'confirm' && verdict != 'reject') {
      throw StateError('Unsupported review verdict: $verdict');
    }

    final ref =
        FirebaseFirestore.instance.collection('incidents').doc(incidentId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw StateError('Incident was not found.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final layer2 =
        Map<String, dynamic>.from(data['layer2'] as Map? ?? const {});
    final currentConfirm = (layer2['confirm'] as num?)?.toInt() ?? 0;
    final currentReject = (layer2['reject'] as num?)?.toInt() ?? 0;

    final existingVotes = await ref
        .collection('moderationVotes')
        .where('reviewerId', isEqualTo: reviewerId)
        .limit(1)
        .get();
    if (existingVotes.docs.isNotEmpty) {
      throw StateError('You have already voted on this report.');
    }

    final nextConfirm = currentConfirm + (verdict == 'confirm' ? 1 : 0);
    final nextReject = currentReject + (verdict == 'reject' ? 1 : 0);
    final reviewed = reviewOutcomeFromVotes(
      confirm: nextConfirm,
      reject: nextReject,
    );

    final batch = FirebaseFirestore.instance.batch();
    batch.update(ref, {
      'moderationStatus': reviewed.status.name,
      'layer2': {
        'verdict': reviewed.status.name,
        'votes': nextConfirm + nextReject,
        'confirm': nextConfirm,
        'reject': nextReject,
      },
    });
    batch.set(
      ref.collection('moderationVotes').doc(),
      {
        'reviewerId': reviewerId,
        'verdict': verdict,
        'reason': reason ?? '',
        'castAt': Timestamp.fromDate(DateTime.now()),
      },
    );
    await batch.commit();
  }

  /// Reasons as display-ready text, for the reviewer's queue.
  static List<String> explain(List<ModerationFlag> flags) =>
      [for (final flag in flags) flag.detail];
}
