import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:latlong2/latlong.dart' as ll;
import '../models/community.dart';
import '../models/recognition_post.dart';
import '../theme/app_theme.dart';
import '../utils/geo.dart';
import '../utils/message_moderation.dart';
import 'unseen_hero_location_picker_screen.dart';

/// Opens [RecognitionSubmitScreen] as a modal bottom sheet — the
/// give-recognition flow triggered by the bottom nav's center button.
Future<void> showRecognitionSubmitSheet(BuildContext context,
    {required String groupId}) {
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
  final _areaController = TextEditingController();
  bool _isSubmitting = false;
  bool _revealIdentity = false;
  bool _recognizeUnseenHero = false;
  ll.LatLng? _unseenHeroLocation;
  PostVisibility _visibility = PostVisibility.public;

  // null = General (widget.groupId, the pre-communities default) — every
  // other value is a real Community.id the sender has joined, so the
  // Unsung Hero ranking on that community can find this post.
  String? _selectedCommunityId;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _myCommunitiesStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _myCommunitiesStream = FirebaseFirestore.instance
        .collection('communities')
        .where('memberIds', arrayContains: uid)
        .snapshots();
  }

  /// Requests contacts access via permission_handler rather than
  /// flutter_contacts' own bundled permission call — on some newer
  /// Android versions the latter silently returns false without ever
  /// showing the system dialog, which is what made this look like
  /// contacts couldn't be searched at all. Also routes a permanently
  /// denied permission to Settings instead of dead-ending silently.
  Future<bool> _requestContactsPermission() async {
    final status = await ph.Permission.contacts.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      _showSnack('Contacts permission is blocked — enable it in Settings.',
          isError: true);
      await ph.openAppSettings();
    } else {
      _showSnack('Contacts permission is needed to pick a contact.',
          isError: true);
    }
    return false;
  }

  /// Opens the device's own contact picker (with its own name/number
  /// search built in) rather than the app requesting broad contacts
  /// access to build a search UI itself — this only ever touches the one
  /// contact the user explicitly picks.
  Future<void> _pickFromContacts() async {
    if (!await _requestContactsPermission()) return;

    final contact = await FlutterContacts.openExternalPick();
    if (contact == null || contact.phones.isEmpty) return;

    // Keep only digits, then take the last 10 — a contact's number can be
    // stored in any format (with country code, spaces, dashes); the field
    // only ever holds the 10-digit local number, with +91 applied
    // separately at submit time.
    final digits = contact.phones.first.number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      _showSnack('That contact has no usable phone number.', isError: true);
      return;
    }
    _recipientController.text = digits.substring(digits.length - 10);
  }

  /// Builds the read-allowlist for a [PostVisibility.contacts] post: every
  /// phone number in the sender's device contacts, normalized to the same
  /// `+91<10 digits>` shape phone-auth uses, so it matches
  /// `request.auth.token.phone_number` in the Firestore rule.
  Future<List<String>> _buildContactsAllowlist() async {
    if (!await _requestContactsPermission()) return const [];

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final numbers = <String>{};
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        final digits = phone.number.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 10) {
          numbers.add('+91${digits.substring(digits.length - 10)}');
        }
      }
    }
    return numbers.toList();
  }

  /// Asks for a name when the typed phone number doesn't match a
  /// registered HALO user yet — recognizing someone who hasn't joined is
  /// allowed, but there's no profile to pull a name from, so it has to be
  /// typed instead of looked up.
  Future<String?> _promptForRecipientName(String phone) {
    final nameController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: bgSurface2,
        title: const Text("They're not on HALO yet",
            style: TextStyle(color: textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No HALO user is registered with $phone. You can still recognize '
              'them — just type their name so the recognition has one.',
              style: const TextStyle(color: textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Their name"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickUnseenHeroLocation() async {
    final point = await Navigator.of(context).push<ll.LatLng>(
      MaterialPageRoute(
        builder: (_) => UnseenHeroLocationPickerScreen(
          initialPoint: _unseenHeroLocation,
        ),
      ),
    );
    if (point != null && mounted) {
      setState(() => _unseenHeroLocation = point);
    }
  }

  Future<void> _submitRecognition() async {
    final recipientPhone = '+91${_recipientController.text.trim()}';
    final message = _messageController.text.trim();

    if (_recipientController.text.trim().isEmpty || message.isEmpty) {
      _showSnack('Please fill in both fields', isError: true);
      return;
    }
    if (_recognizeUnseenHero) {
      if (_selectedCommunityId == null) {
        _showSnack('Choose a community for an Unseen Hero.', isError: true);
        return;
      }
      if (_unseenHeroLocation == null) {
        _showSnack('Choose the public area where this happened.',
            isError: true);
        return;
      }
      if (_areaController.text.trim().length < 2) {
        _showSnack('Add a short public area name.', isError: true);
        return;
      }
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnack('You must be logged in to submit', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (recipientPhone == currentUser.phoneNumber) {
        _showSnack("You can't send a HALO to yourself.", isError: true);
        return;
      }

      final matches = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: recipientPhone)
          .limit(1)
          .get();

      // recipientId/recipientDisplayName for a registered user; for an
      // unregistered phone number, there's no uid to point at yet, so a
      // stable `phone:+91…` placeholder stands in — this is why it's
      // prefixed distinctly from a real Firestore uid, not because it
      // needs to look like one. If that number ever signs up, their
      // existing recognitions aren't retroactively linked to the new uid;
      // that reconciliation isn't built yet.
      String recipientId;
      String recipientDisplayName;

      if (matches.docs.isNotEmpty) {
        recipientId = matches.docs.first.id;
        recipientDisplayName =
            matches.docs.first.data()['name'] as String? ?? 'Someone';
      } else {
        if (_recognizeUnseenHero) {
          _showSnack(
            'Unseen Hero locations require a registered HALO profile.',
            isError: true,
          );
          return;
        }
        if (!mounted) return;
        final typedName = await _promptForRecipientName(recipientPhone);
        if (typedName == null || typedName.trim().isEmpty) return;
        recipientId = 'phone:$recipientPhone';
        recipientDisplayName = typedName.trim();
      }

      // Single-level, client-side moderation check — see
      // lib/utils/message_moderation.dart for why this replaces the
      // AWS pipeline for now (Cloud Functions need a Blaze plan this
      // project doesn't have) and the trade-off that comes with it.
      final moderation = moderateMessage(message);
      if (!moderation.isApproved) {
        _showSnack(moderation.reason ?? 'This message was not approved.',
            isError: true);
        return;
      }

      // Only fetch/attach the sender's own name when they've opted to
      // reveal it — otherwise senderDisplayName stays null, matching
      // isAnonymous, so there's nothing to leak even if some future code
      // path reads it incorrectly.
      String? senderDisplayName;
      if (_revealIdentity) {
        final senderDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        senderDisplayName =
            senderDoc.data()?['name'] as String? ?? 'A HALO user';
      }

      // Only built when needed — this is the extra permission/contacts
      // read a "Contacts" post costs over a "Public" one.
      final allowedPhoneNumbers = _visibility == PostVisibility.contacts
          ? await _buildContactsAllowlist()
          : const <String>[];

      GeoPoint? unseenHeroLocation;
      String? areaName;
      String? geohashPrefix;
      if (_recognizeUnseenHero && _unseenHeroLocation != null) {
        final latitude = coarsenLatitude(_unseenHeroLocation!.latitude);
        final longitude = coarsenLongitude(_unseenHeroLocation!.longitude);
        unseenHeroLocation = GeoPoint(latitude, longitude);
        areaName = _areaController.text.trim();
        geohashPrefix = encodeGeohash(latitude, longitude);
      }

      final post = RecognitionPost(
        postId: '', // Firestore auto-generates this on add()
        senderId: currentUser.uid, // internal only — never displayed
        recipientId: recipientId,
        recipientDisplayName: recipientDisplayName,
        message: message,
        groupId: _selectedCommunityId ?? widget.groupId,
        moderationStatus: moderation.status,
        createdAt: DateTime.now(),
        isAnonymous: !_revealIdentity,
        senderDisplayName: senderDisplayName,
        visibility: _visibility,
        allowedPhoneNumbers: allowedPhoneNumbers,
        isUnseenHeroCandidate: _recognizeUnseenHero,
        location: unseenHeroLocation,
        areaName: areaName,
        geohashPrefix: geohashPrefix,
        locationPrecision: _recognizeUnseenHero ? 'approximateArea' : null,
      );

      await FirebaseFirestore.instance
          .collection('recognitions')
          .add(post.toFirestore());

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _recognizeUnseenHero
                ? 'Submitted — the SafeWalk area appears when the hero opts in.'
                : 'Submitted — your recognition is now live in the feed.',
          ),
        ),
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
    _areaController.dispose();
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
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: const [
                Icon(LucideIcons.userCircle, size: 16, color: textMuted),
                SizedBox(width: 6),
                Text('Who are you recognizing?',
                    style: TextStyle(color: textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _recipientController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: "Recipient's phone number",
                prefixText: '+91  ',
                prefixIcon:
                    const Icon(LucideIcons.phone, size: 18, color: accentGold),
                suffixIcon: IconButton(
                  icon: const Icon(LucideIcons.bookUser,
                      size: 18, color: accentGold),
                  tooltip: 'Pick from contacts',
                  onPressed: _pickFromContacts,
                ),
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
            const SizedBox(height: 20),
            Row(
              children: const [
                Icon(LucideIcons.users, size: 16, color: textMuted),
                SizedBox(width: 6),
                Text('Community (optional)',
                    style: TextStyle(color: textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _myCommunitiesStream,
              builder: (context, snapshot) {
                final communities = (snapshot.data?.docs ?? [])
                    .map((doc) => Community.fromFirestore(doc))
                    .toList();

                if (communities.isEmpty) {
                  return const Text(
                    "You haven't joined a community yet — this will post to the general feed. "
                    'Join one from the Communities icon up top to target this recognition there.',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  );
                }

                return DropdownButtonFormField<String?>(
                  initialValue: _selectedCommunityId,
                  decoration: const InputDecoration(
                    prefixIcon:
                        Icon(LucideIcons.users, size: 18, color: accentGold),
                  ),
                  hint: const Text('General feed'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('General feed')),
                    for (final community in communities)
                      DropdownMenuItem(
                          value: community.id, child: Text(community.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedCommunityId = value),
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _recognizeUnseenHero,
              activeThumbColor: accentGold,
              onChanged: (value) =>
                  setState(() => _recognizeUnseenHero = value),
              title: const Text(
                'Recognize an Unseen Hero',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              subtitle: const Text(
                'Show an approximate public-area pin on SafeWalk after the hero opts in.',
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
            ),
            if (_recognizeUnseenHero) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorGreenDim,
                  borderRadius: BorderRadius.circular(buttonRadius),
                  border: Border.all(color: accentGoldBorder),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.shieldCheck, color: colorGreen, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Never enter a home or exact address. The pin is rounded before storage and appears only if the recipient enables Unseen Hero visibility.',
                        style: TextStyle(color: textMuted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _areaController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Public area name',
                  hintText: 'e.g. PSG Campus main gate',
                  prefixIcon:
                      Icon(LucideIcons.mapPin, size: 18, color: accentGold),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickUnseenHeroLocation,
                      icon: const Icon(LucideIcons.mapPinned, size: 18),
                      label: const Text('Choose area'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _unseenHeroLocation == null
                          ? 'No area selected'
                          : 'Area selected',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _unseenHeroLocation == null
                            ? textMuted
                            : colorGreen,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: const [
                Icon(LucideIcons.globe, size: 16, color: textMuted),
                SizedBox(width: 6),
                Text('Who can see this', style: TextStyle(color: textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<PostVisibility>(
              segments: const [
                ButtonSegment(
                  value: PostVisibility.public,
                  label: Text('Public'),
                  icon: Icon(LucideIcons.globe, size: 16),
                ),
                ButtonSegment(
                  value: PostVisibility.contacts,
                  label: Text('Contacts only'),
                  icon: Icon(LucideIcons.bookUser, size: 16),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: (selection) =>
                  setState(() => _visibility = selection.first),
            ),
            const SizedBox(height: 4),
            Text(
              _visibility == PostVisibility.contacts
                  ? "Only people in your phone's contacts (and the recipient) can see this in their feed."
                  : 'Visible to every HALO user.',
              style: const TextStyle(color: textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _revealIdentity,
              activeThumbColor: accentGold,
              onChanged: (value) => setState(() => _revealIdentity = value),
              title: const Text('Show my name to them',
                  style: TextStyle(color: textPrimary, fontSize: 14)),
              subtitle: Text(
                _revealIdentity
                    ? 'Your name will show on this post in the feed and search.'
                    : 'Sent anonymously (default).',
                style: const TextStyle(color: textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
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
