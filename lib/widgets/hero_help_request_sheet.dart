import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/unseen_hero.dart';
import '../services/unseen_hero_service.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

Future<void> showUnseenHeroDetails(
  BuildContext context,
  NearbyUnseenHero hero,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: bgSurface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
    ),
    builder: (_) => _UnseenHeroDetails(hero: hero),
  );
}

class _UnseenHeroDetails extends StatelessWidget {
  const _UnseenHeroDetails({required this.hero});

  final NearbyUnseenHero hero;

  @override
  Widget build(BuildContext context) {
    final presence = hero.presence;
    final distance = hero.distanceMeters >= 1000
        ? '${(hero.distanceMeters / 1000).toStringAsFixed(1)} km away'
        : '${hero.distanceMeters.round()} m away';

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentGoldDim,
                    border: Border.fromBorderSide(
                      BorderSide(color: accentGoldBorder),
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.crown,
                    color: accentGold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presence.heroName,
                        style: const TextStyle(
                          color: textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$distance · ${presence.communityName}',
                        style: const TextStyle(color: textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoRow(
              icon: LucideIcons.mapPin,
              label: 'Approximate area',
              value: presence.areaName,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: LucideIcons.sparkle,
              label: 'Why they are an Unseen Hero',
              value: presence.message,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: LucideIcons.clock,
              label: 'Recognized',
              value: relativeTime(presence.recognizedAt),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: presence.helpAvailable ? colorGreenDim : bgSurface3,
                borderRadius: BorderRadius.circular(buttonRadius),
                border: Border.all(
                  color:
                      presence.helpAvailable ? accentGoldBorder : borderColor,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    presence.helpAvailable
                        ? LucideIcons.circleCheck
                        : LucideIcons.circlePause,
                    color: presence.helpAvailable ? colorGreen : textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      presence.helpAvailable
                          ? 'Available for private help requests'
                          : 'Not accepting help requests right now',
                      style: TextStyle(
                        color: presence.helpAvailable ? colorGreen : textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.shieldCheck, color: colorGreen, size: 17),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This is an approximate recognition pin, not live tracking. Contact details are shared only after the hero accepts.',
                    style: TextStyle(color: textMuted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: presence.helpAvailable
                  ? () => _openRequestSheet(context, hero)
                  : null,
              icon: const Icon(LucideIcons.handHeart, size: 18),
              label: const Text('Ask for help'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRequestSheet(BuildContext context, NearbyUnseenHero hero) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (_) => _HelpRequestForm(hero: hero),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accentGold, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: textMuted, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HelpRequestForm extends StatefulWidget {
  const _HelpRequestForm({required this.hero});

  final NearbyUnseenHero hero;

  @override
  State<_HelpRequestForm> createState() => _HelpRequestFormState();
}

class _HelpRequestFormState extends State<_HelpRequestForm> {
  final _messageController = TextEditingController();
  bool _contactAllowed = false;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_messageController.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a little more detail for the hero.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await UnseenHeroService.createHelpRequest(
        requesterId: uid,
        hero: widget.hero.presence,
        message: _messageController.text,
        contactAllowed: _contactAllowed,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Request sent privately. Contact unlocks after acceptance.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Private help request',
              style: TextStyle(
                color: textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'To ${widget.hero.presence.heroName} · ${widget.hero.presence.areaName}',
              style: const TextStyle(color: textMuted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _messageController,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What help do you need?',
                alignLabelWithHint: true,
                hintText: 'Share only what is safe and necessary...',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _contactAllowed,
              activeThumbColor: accentGold,
              onChanged: (value) => setState(() => _contactAllowed = value),
              title: const Text(
                'Share my phone number',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              subtitle: const Text(
                'The hero can call you only after accepting. Leave off to stay in-app only.',
                style: TextStyle(color: textMuted, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: bgPrimary,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: Text(_sending ? 'Sending...' : 'Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
