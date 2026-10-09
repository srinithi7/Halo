import 'package:flutter_test/flutter_test.dart';
import 'package:halo/services/moderation_service.dart';

void main() {
  test('review outcome confirms once there are enough confirm votes', () {
    final outcome = ModerationService.reviewOutcomeFromVotes(
      confirm: 3,
      reject: 0,
    );

    expect(outcome.status, IncidentModerationStatus.confirmed);
    expect(outcome.confirm, 3);
    expect(outcome.reject, 0);
  });

  test('review outcome stays under review when votes are tied', () {
    final outcome = ModerationService.reviewOutcomeFromVotes(
      confirm: 1,
      reject: 1,
    );

    expect(outcome.status, IncidentModerationStatus.underReview);
    expect(outcome.confirm, 1);
    expect(outcome.reject, 1);
  });
}
