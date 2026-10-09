import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Optional, debug-only advisory sentiment check backed by a local FastAPI
/// service (see ml/server.py) running a MultinomialNB + TF-IDF model.
///
/// Three deliberate constraints:
///  1. It is dead code in release builds — `kDebugMode` gates everything, so
///     a production APK never sends report text anywhere.
///  2. It is advisory only. The result is shown with the model's own caveat
///     and never influences approval or visibility.
///  3. It never blocks the report write. If the API is unreachable the check
///     just does not appear; a dead dev server must never delay a safety
///     report.
class SentimentService {
  SentimentService._();

  /// Enable with `--dart-define=SENTIMENT_API=http://<host>:8000`. An empty
  /// value means the feature is off and unavailableReason explains why.
  static const _endpoint = String.fromEnvironment('SENTIMENT_API');

  static bool get isConfigured => kDebugMode && _endpoint.isNotEmpty;

  static String get unavailableReason {
    if (!kDebugMode) {
      return 'Only available in debug builds, so report text never leaves the '
          'device in release versions.';
    }
    if (_endpoint.isEmpty) {
      return 'No API configured. Rebuild with '
          '--dart-define=SENTIMENT_API=http://<your-pc>:8000';
    }
    return 'Not currently reachable.';
  }

  static Future<SentimentAssessment> assess(String text) async {
    if (!isConfigured) {
      return SentimentAssessment.unavailable(
        reason: unavailableReason,
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse('$_endpoint/sentiment'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        return SentimentAssessment.unavailable(
          reason: 'The tone-check API replied ${response.statusCode}.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final probs = (body['probabilities'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
      return SentimentAssessment(
        label: body['label'] as String,
        confidence: (body['confidence'] as num).toDouble(),
        probabilities: probs,
        caveat: body['caveat'] as String,
      );
    } catch (_) {
      return SentimentAssessment.unavailable(
        reason: 'Could not reach the tone-check API.',
      );
    }
  }
}

class SentimentAssessment {
  const SentimentAssessment({
    required this.label,
    required this.confidence,
    required this.probabilities,
    required this.caveat,
    this.reason,
  }) : available = true;

  const SentimentAssessment.unavailable({required this.reason})
      : label = null,
        confidence = 0,
        probabilities = const {},
        caveat = null,
        available = false;

  final bool available;
  final String? label;
  final double confidence;
  final Map<String, double> probabilities;
  final String? caveat;
  final String? reason;
}
