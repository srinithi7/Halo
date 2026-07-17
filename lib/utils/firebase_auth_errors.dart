import 'package:firebase_auth/firebase_auth.dart';

/// Maps a [FirebaseAuthException] from sign-in or sign-up to copy that's
/// safe to show directly in a SnackBar.
String friendlyAuthErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'That email address looks invalid.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'email-already-in-use':
      return 'An account already exists for that email.';
    case 'weak-password':
      return 'Password is too weak — use at least 6 characters.';
    default:
      return e.message ?? 'Something went wrong. Please try again.';
  }
}
