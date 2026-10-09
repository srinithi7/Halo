import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Whether a `users/{uid}` profile doc already exists — used right after
/// phone sign-in to decide whether this is a first-time user who still
/// needs to provide their name.
Future<bool> hasUserProfile(String uid) async {
  if (kDebugMode) return true;
  final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.exists;
}

/// Creates this user's profile doc, keyed by uid. Used to resolve a typed
/// recipient phone number to a uid/display name when submitting a
/// recognition.
Future<void> createUserProfile({
  required String uid,
  required String phoneNumber,
  required String name,
  String? circleName,
  String? signature,
  int haloScore = 0,
  int streak = 0,
}) async {
  if (kDebugMode) return;
  await FirebaseFirestore.instance.collection('users').doc(uid).set({
    'phoneNumber': phoneNumber,
    'name': name,
    'circleName': circleName ?? 'Local Circle',
    'signature': signature ?? 'Helping quietly, noticing clearly.',
    'haloScore': haloScore,
    'streak': streak,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
