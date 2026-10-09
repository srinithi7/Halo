import '../models/recognition_post.dart';

/// Client-side, single-level moderation check.
///
/// This exists in place of the AWS SQS → Lambda → Comprehend pipeline
/// described in the project's design doc: that pipeline needs a Firebase
/// Blaze (pay-as-you-go) plan just to deploy the Cloud Function that
/// forwards to it, which this project doesn't have. Until the project is
/// on Blaze, this is the only moderation gate a submission passes through
/// — so it runs synchronously in the app and decides [ModerationStatus]
/// immediately, instead of leaving posts stuck in `pending` forever.
///
/// Trade-off (deliberate, not an oversight): because this runs on the
/// client, a modified/rebuilt copy of the app could skip this check
/// entirely and write `moderationStatus: 'approved'` directly — Firestore
/// rules only require `senderId` to match the writer, not that
/// moderationStatus came from a trusted check. Closing that gap requires
/// a server-side check (Cloud Function or otherwise), which needs Blaze.
/// Revisit this the moment billing is enabled.
class MessageModerationResult {
  const MessageModerationResult(this.status, this.reason);

  final ModerationStatus status;

  /// Human-readable reason when [status] is [ModerationStatus.rejected];
  /// null when approved.
  final String? reason;

  bool get isApproved => status == ModerationStatus.approved;
}

/// Blocked terms, grouped by why they're blocked — explicit and
/// hand-maintained rather than a third-party wordlist package, so what's
/// blocked stays auditable in one place. Matched case-insensitively
/// against whole words/phrases.
///
/// Honest limitation: this is still lexicon matching, not sentiment
/// analysis or an NLP model — it catches messages that use one of these
/// words/phrases literally, not negativity expressed some other way, and
/// it can false-positive on a legitimate sentence that happens to contain
/// one of these words (e.g. an insult word used self-deprecatingly). A
/// real classifier (the AWS Comprehend step in the original design) is
/// the way to close that gap, and needs Blaze — see the class doc above.
const _blockedTerms = <String>[
  // Insults / put-downs
  'idiot', 'stupid', 'dumb', 'moron', 'fool', 'foolish', 'jerk',
  'useless', 'pathetic', 'worthless', 'loser', 'ugly', 'disgusting',
  'trash', 'garbage', 'incompetent', 'lazy', 'annoying', 'arrogant',
  'selfish', 'creep', 'clown', 'coward', 'liar', 'freak',

  // Hostility / dismissal directed at someone
  'hate you', 'i hate', 'shut up', 'get lost', 'go away', 'screw you',
  'piss off', 'nobody likes you', 'nobody cares',

  // Threats / self-harm
  'kill yourself', 'kys', 'kill you', 'hurt you', 'destroy you',
  'ruin you', 'go die', 'drop dead',

  // Negative emotion words — a recognition is meant to be appreciation,
  // so these are out of place regardless of who they're aimed at.
  'angry', 'furious', 'miserable', 'depressed', 'depressing',
  'terrible', 'awful', 'horrible', 'disgusted', 'disappointed',
  'hopeless', 'worst', 'hate this', 'sucks', 'suck',
];

/// Runs the message through a single rule-based pass and returns the
/// resulting [ModerationStatus] plus a reason when rejected:
///
/// 1. Empty/whitespace-only → rejected.
/// 2. Too short to be a genuine recognition (< 3 words) → rejected.
/// 3. Contains a blocked term → rejected.
/// 4. Mostly non-alphabetic "shouting"/spam (e.g. "!!!!!!!!!!") → rejected.
/// 5. Otherwise → approved immediately.
MessageModerationResult moderateMessage(String message) {
  final trimmed = message.trim();

  if (trimmed.isEmpty) {
    return const MessageModerationResult(
      ModerationStatus.rejected,
      'Message is empty.',
    );
  }

  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length < 3) {
    return const MessageModerationResult(
      ModerationStatus.rejected,
      'Please write a few words about what you appreciated.',
    );
  }

  final lower = trimmed.toLowerCase();
  for (final term in _blockedTerms) {
    final pattern = RegExp(r'\b' + RegExp.escape(term) + r'\b');
    if (pattern.hasMatch(lower)) {
      return const MessageModerationResult(
        ModerationStatus.rejected,
        'This message doesn\'t match HALO\'s tone of genuine appreciation.',
      );
    }
  }

  final letters = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '');
  if (letters.length < trimmed.length * 0.4) {
    return const MessageModerationResult(
      ModerationStatus.rejected,
      'Message looks like spam rather than a recognition.',
    );
  }

  return const MessageModerationResult(ModerationStatus.approved, null);
}
