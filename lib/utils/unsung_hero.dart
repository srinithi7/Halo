import '../models/recognition_post.dart';

/// One recipient's standing in a community's Unsung Hero ranking.
class UnsungHeroCandidate {
  const UnsungHeroCandidate({
    required this.recipientId,
    required this.recipientDisplayName,
    required this.recognitionCount,
    required this.distinctSenderCount,
    required this.totalGlows,
    required this.score,
  });

  final String recipientId;
  final String recipientDisplayName;
  final int recognitionCount;
  final int distinctSenderCount;
  final int totalGlows;
  final double score;
}

/// Minimum recognitions received before someone is even considered — one
/// post from one person isn't enough signal, and without this a single
/// recognition would dominate an otherwise-empty community.
const _minRecognitionsToQualify = 2;

/// Scores and ranks a community's members for "Unsung Hero": the person
/// whose peers consistently recognize them, but who isn't already the
/// most visible/celebrated member.
///
/// score = (recognitions received × 3) + (distinct people who recognized
/// them × 5) − (total glows received × 1)
///
/// The intuition behind each term:
///  - Recognitions received: they're actually doing recognition-worthy
///    things, not just present in the community.
///  - Distinct senders (weighted highest): broad, independent appreciation
///    across many peers is stronger evidence of quiet impact than the same
///    one or two people repeatedly praising them.
///  - Glows received (subtracted): glows are the feed's applause meter —
///    someone already racking up glows is, by definition, not unsung.
///    Subtracting it pushes the winner toward people recognized
///    substantively but not yet loudly celebrated.
///
/// [posts] must already be filtered to one community (same groupId) and
/// to [ModerationStatus.approved] — this function does no filtering of
/// its own beyond the minimum-recognitions qualifier. senderId is read
/// here only to count distinct senders, never surfaced in the returned
/// candidates — consistent with the anonymity invariant on
/// [RecognitionPost.senderId].
List<UnsungHeroCandidate> rankUnsungHeroes(List<RecognitionPost> posts) {
  final byRecipient = <String, List<RecognitionPost>>{};
  for (final post in posts) {
    byRecipient.putIfAbsent(post.recipientId, () => []).add(post);
  }

  final candidates = <UnsungHeroCandidate>[];
  byRecipient.forEach((recipientId, received) {
    if (received.length < _minRecognitionsToQualify) return;

    final distinctSenders = received.map((p) => p.senderId).toSet().length;
    final totalGlows = received.fold<int>(0, (sum, p) => sum + p.glowCount);
    final score = (received.length * 3) + (distinctSenders * 5) - totalGlows;

    candidates.add(UnsungHeroCandidate(
      recipientId: recipientId,
      recipientDisplayName: received.first.recipientDisplayName,
      recognitionCount: received.length,
      distinctSenderCount: distinctSenders,
      totalGlows: totalGlows,
      score: score.toDouble(),
    ));
  });

  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates;
}
