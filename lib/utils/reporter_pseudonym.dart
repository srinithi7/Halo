import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Turns a user id into a stable, non-reversible handle for incident reports.
///
/// ## What this is, and what it is not
///
/// This is **pseudonymisation, not anonymity**. A hash of a user id is stable
/// and linkable, so it is a *different privacy posture* from storing nothing
/// — not the same one. Concretely, with a handle present:
///
///  * one person's spam can be rate-limited and deduplicated;
///  * that person can recognise their own reports;
///  * and, in principle, the holder of the [pepper] could confirm that two
///    reports came from the same account.
///
/// What it deliberately does **not** do, ever:
///
///  * the raw user id is never written to an incident document, so there is
///    nothing on the report to de-anonymise even with full database access;
///  * the handle is not shown to other users anywhere in the UI;
///  * the handle is not derived from anything the reporter typed.
///
/// Because the pepper is a build-time constant, a leaked database alone is
/// not enough to test candidate uids against the handle. That protection
/// disappears if the pepper is a well-known value, so it must be set per
/// deployment.
class ReporterPseudonym {
  const ReporterPseudonym._();

  /// Salt mixed into every handle. Supplied at build time:
  /// `--dart-define=REPORTER_PSEUDONYM_PEPPER=...`
  ///
  /// A build with no pepper still works, but handles from that build become
  /// brute-forceable by anyone holding the database, since uids are low
  /// entropy. [isPeppered] lets the UI warn about that.
  static const pepper = String.fromEnvironment('REPORTER_PSEUDONYM_PEPPER');

  static bool get isPeppered => pepper.isNotEmpty;

  static const _length = 32;

  /// A short, stable handle for [userId], or null when there is no signed-in
  /// user to derive one from.
  static String? forUserId(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final digest = sha256.convert(utf8.encode('$pepper::$userId'));
    return digest.toString().substring(0, _length);
  }

  /// Stable handle for a debug/demo identity, so simulated reports behave
  /// exactly like real ones in the debug build.
  static String forDebugUser(String label) => forUserId('debug::$label') ?? '';

  /// Shape check used by both the model and the Firestore rules, so a
  /// malformed or truncated handle can never be persisted.
  static bool isWellFormed(String? handle) {
    if (handle == null) return false;
    if (handle.length != _length) return false;
    for (var i = 0; i < handle.length; i++) {
      final code = handle.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39;
      final isLowerHex = code >= 0x61 && code <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }
}
