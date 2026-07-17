import 'package:firebase_auth/firebase_auth.dart';

/// Maps a [FirebaseAuthException] from phone sign-in to copy that's safe to
/// show directly in a SnackBar.
String friendlyAuthErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-phone-number':
      return 'That phone number looks invalid.';
    case 'invalid-verification-code':
      return 'That code is incorrect. Please check and try again.';
    case 'session-expired':
      return 'This code has expired — request a new one.';
    case 'too-many-requests':
    case 'quota-exceeded':
      return 'Too many attempts. Please try again later.';
    case 'operation-not-allowed':
    case 'configuration-not-found':
      return 'Sign-in is temporarily unavailable. Please try again later.';
    default:
      return e.message ?? 'Something went wrong. Please try again.';
  }
}
