import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/recognition_post.dart';
import '../theme/app_theme.dart';

/// Opens [RecognitionSubmitScreen] as a modal bottom sheet — the
/// give-recognition flow triggered by the bottom nav's center button.
Future<void> showRecognitionSubmitSheet(BuildContext context, {required String groupId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: bgSurface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
    ),
    builder: (_) => RecognitionSubmitScreen(groupId: groupId),
  );
}

/// Screen where a logged-in user writes and submits an anonymous
/// recognition post about a peer/teammate, shown as a modal bottom sheet.
class RecognitionSubmitScreen extends StatefulWidget {
  final String groupId;

  const RecognitionSubmitScreen({super.key, required this.groupId});

  @override
  State<RecognitionSubmitScreen> createState() =>
      _RecognitionSubmitScreenState();
}

class _RecognitionSubmitScreenState extends State<RecognitionSubmitScreen> {
  final _recipientController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitRecognition() async {
    final recipientPhone = '+91${_recipientController.text.trim()}';
    final message = _messageController.text.trim();

    if (_recipientController.text.trim().isEmpty || message.isEmpty) {
      _showSnack('Please fill in both fields', isError: true);
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnack('You must be logged in to submit', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final matches = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: recipientPhone)
          .limit(1)
          .get();

      if (matches.docs.isEmpty) {
        _showSnack('No HALO user found with that phone number.', isError: true);
        return;
      }

      final recipient = matches.docs.first;
      if (recipient.id == currentUser.uid) {
        _showSnack("You can't send a HALO to yourself.", isError: true);
        return;
      }

      final post = RecognitionPost(
        postId: '', // Firestore auto-generates this on add()
        senderId: currentUser.uid, // internal only — never displayed
        recipientId: recipient.id,
        recipientDisplayName: recipient.data()['name'] as String? ?? 'Someone',
        message: message,
        groupId: widget.groupId,
        moderationStatus: ModerationStatus.pending,
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('recognitions')
          .add(post.toFirestore());

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted — your recognition is pending review.')),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Something went wrong: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
              color: isError ? colorRed : accentGold,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: spacingPadding + 4,
        right: spacingPadding + 4,
        top: spacingPadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + spacingPadding + 4,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(LucideIcons.heartHandshake, color: accentGold, size: 20),
                SizedBox(width: 8),
                Text(
                  'Send Recognition',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: const [
                Icon(LucideIcons.userCircle, size: 16, color: textMuted),
                SizedBox(width: 6),
                Text('Who are you recognizing?', style: TextStyle(color: textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _recipientController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Recipient's phone number",
                prefixText: '+91  ',
                prefixIcon: Icon(LucideIcons.phone, size: 18, color: accentGold),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: const [
                Icon(LucideIcons.messageSquare, size: 16, color: textMuted),
                SizedBox(width: 6),
                Text('Your message', style: TextStyle(color: textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Share something you appreciate about them...',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitRecognition,
              icon: _isSubmitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: bgPrimary,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: Text(_isSubmitting ? 'Sending...' : 'Submit'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(LucideIcons.shieldCheck, size: 13, color: textMuted),
                SizedBox(width: 5),
                Text(
                  'Your identity stays private to other users',
                  style: TextStyle(fontSize: 11, color: textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
