import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/recognition_post.dart';

/// MVP screen for submitting a new [RecognitionPost].
///
/// Requires a signed-in user (via [FirebaseAuth]) — the current user's uid
/// is used as `senderId` purely for internal moderation/abuse tracing, and
/// is never displayed anywhere on this screen or passed to any widget that
/// renders to other users.
class RecognitionSubmitScreen extends StatefulWidget {
  const RecognitionSubmitScreen({super.key, required this.groupId});

  /// The community/group this recognition post belongs to.
  final String groupId;

  @override
  State<RecognitionSubmitScreen> createState() =>
      _RecognitionSubmitScreenState();
}

class _RecognitionSubmitScreenState extends State<RecognitionSubmitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();

  // Placeholder recipient list — swap for a real member/contact lookup later.
  static const List<String> _recipientOptions = [
    'Anonymous neighbor',
    'Recipient A',
    'Recipient B',
    'Recipient C',
  ];

  String? _selectedRecipientId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to submit a HALO.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final post = RecognitionPost(
      postId: '', // Firestore assigns this on write.
      senderId: currentUser.uid,
      recipientId: _selectedRecipientId!,
      message: _messageController.text.trim(),
      groupId: widget.groupId,
      moderationStatus: ModerationStatus.pending,
      createdAt: DateTime.now(),
    );

    try {
      await FirebaseFirestore.instance
          .collection('recognitions')
          .add(post.toFirestore());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted! Your HALO is pending review.')),
      );
      _messageController.clear();
      setState(() => _selectedRecipientId = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit HALO: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Give a HALO')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Recognize someone in your community.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _selectedRecipientId,
                decoration: const InputDecoration(
                  labelText: 'Recipient',
                  border: OutlineInputBorder(),
                ),
                items: _recipientOptions
                    .map(
                      (name) => DropdownMenuItem(value: name, child: Text(name)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedRecipientId = value),
                validator: (value) =>
                    value == null ? 'Please select a recipient' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'What did they do?',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Please write a message'
                    : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
