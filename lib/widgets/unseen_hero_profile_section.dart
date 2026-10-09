import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/unseen_hero.dart';
import '../services/unseen_hero_service.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

class UnseenHeroProfileSection extends StatefulWidget {
  const UnseenHeroProfileSection({super.key, required this.uid});

  final String uid;

  @override
  State<UnseenHeroProfileSection> createState() =>
      _UnseenHeroProfileSectionState();
}

class _UnseenHeroProfileSectionState extends State<UnseenHeroProfileSection> {
  late Future<UnseenHeroSettings> _settingsFuture;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _settingsFuture = UnseenHeroService.getSettings(widget.uid);
    });
  }

  Future<void> _save(UnseenHeroSettings settings) async {
    setState(() => _settingsFuture = Future.value(settings));
    try {
      await UnseenHeroService.saveSettings(widget.uid, settings);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update visibility: $error')),
      );
      _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<UnseenHeroSettings>(
          future: _settingsFuture,
          builder: (context, snapshot) {
            final settings = snapshot.data ?? UnseenHeroSettings.defaults();
            return Card(
              color: accentGoldDim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.crown,
                          color: accentGold,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nearby Unseen Hero',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Control whether approved recognitions appear on SafeWalk.',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: settings.visibleOnSafeWalk,
                          activeThumbColor: accentGold,
                          onChanged: (value) => _save(
                            settings.copyWith(
                              visibleOnSafeWalk: value,
                              acceptingHelpRequests: value
                                  ? settings.acceptingHelpRequests
                                  : false,
                              sharePhoneAfterAcceptance: value
                                  ? settings.sharePhoneAfterAcceptance
                                  : false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (settings.visibleOnSafeWalk) ...[
                      const Divider(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.acceptingHelpRequests,
                        activeThumbColor: accentGold,
                        onChanged: (value) => _save(
                          settings.copyWith(
                            acceptingHelpRequests: value,
                            sharePhoneAfterAcceptance: value
                                ? settings.sharePhoneAfterAcceptance
                                : false,
                          ),
                        ),
                        title: const Text(
                          'Accept private help requests',
                          style: TextStyle(color: textPrimary, fontSize: 13.5),
                        ),
                        subtitle: const Text(
                          'People see that you are available; your phone stays private.',
                          style: TextStyle(color: textMuted, fontSize: 11.5),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.sharePhoneAfterAcceptance,
                        activeThumbColor: accentGold,
                        onChanged: settings.acceptingHelpRequests
                            ? (value) => _save(
                                  settings.copyWith(
                                    sharePhoneAfterAcceptance: value,
                                  ),
                                )
                            : null,
                        title: const Text(
                          'Share phone after acceptance',
                          style: TextStyle(color: textPrimary, fontSize: 13.5),
                        ),
                        subtitle: const Text(
                          'A requester can call only after you accept their request.',
                          style: TextStyle(color: textMuted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: spacingCardGap),
        _RequestsCard(uid: widget.uid),
      ],
    );
  }
}

class _RequestsCard extends StatelessWidget {
  const _RequestsCard({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.handHeart,
                  color: accentGold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Help requests',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Requests you receive',
              style: TextStyle(
                color: textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<HeroHelpRequest>>(
              stream: UnseenHeroService.watchIncomingRequests(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Could not load incoming requests.',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  );
                }
                final requests = snapshot.data ?? const <HeroHelpRequest>[];
                if (requests.isEmpty) {
                  return const Text(
                    'No requests yet.',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  );
                }
                return Column(
                  children: [
                    for (final request in requests.take(5))
                      _IncomingRequestTile(request: request),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            const Text(
              'Requests you sent',
              style: TextStyle(
                color: textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<HeroHelpRequest>>(
              stream: UnseenHeroService.watchOutgoingRequests(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Could not load sent requests.',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  );
                }
                final requests = snapshot.data ?? const <HeroHelpRequest>[];
                if (requests.isEmpty) {
                  return const Text(
                    'You have not asked any nearby hero for help.',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  );
                }
                return Column(
                  children: [
                    for (final request in requests.take(5))
                      _OutgoingRequestTile(request: request),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingRequestTile extends StatefulWidget {
  const _IncomingRequestTile({required this.request});

  final HeroHelpRequest request;

  @override
  State<_IncomingRequestTile> createState() => _IncomingRequestTileState();
}

class _IncomingRequestTileState extends State<_IncomingRequestTile> {
  bool _sending = false;

  Future<void> _respond(HeroHelpRequestStatus status) async {
    setState(() => _sending = true);
    try {
      await UnseenHeroService.respondToHelpRequest(
        heroId: widget.request.heroId,
        request: widget.request,
        status: status,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(buttonRadius),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.requesterName,
            style: const TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            request.message,
            style: const TextStyle(color: textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            '${request.areaName} · ${relativeTime(request.createdAt)}',
            style: const TextStyle(color: textMuted2, fontSize: 10.5),
          ),
          if (request.isPending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () => _respond(HeroHelpRequestStatus.declined),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _sending
                        ? null
                        : () => _respond(HeroHelpRequestStatus.accepted),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ] else if (request.isAccepted)
            _AcceptedContact(request: request, outgoing: false),
        ],
      ),
    );
  }
}

class _OutgoingRequestTile extends StatelessWidget {
  const _OutgoingRequestTile({required this.request});

  final HeroHelpRequest request;

  @override
  Widget build(BuildContext context) {
    final label = request.isPending
        ? 'Waiting for response'
        : request.isAccepted
            ? 'Accepted'
            : 'Declined';
    final color = request.isPending
        ? textMuted
        : request.isAccepted
            ? colorGreen
            : colorRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(buttonRadius),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.heroName,
                  style: const TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            request.message,
            style: const TextStyle(color: textMuted, fontSize: 12.5),
          ),
          if (request.isAccepted)
            _AcceptedContact(request: request, outgoing: true),
        ],
      ),
    );
  }
}

class _AcceptedContact extends StatelessWidget {
  const _AcceptedContact({required this.request, required this.outgoing});

  final HeroHelpRequest request;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HeroContactGrant?>(
      future: UnseenHeroService.getContactGrant(request.id),
      builder: (context, snapshot) {
        final grant = snapshot.data;
        final phone = outgoing ? grant?.heroPhone : grant?.requesterPhone;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Preparing private contact...',
              style: TextStyle(color: textMuted, fontSize: 11),
            ),
          );
        }
        if (phone == null || phone.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'The other person chose in-app-only contact.',
              style: TextStyle(color: textMuted, fontSize: 11),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _call(context, phone),
              icon: const Icon(LucideIcons.phone, size: 16),
              label: Text(outgoing ? 'Call hero' : 'Call requester'),
            ),
          ),
        );
      },
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri) && await launchUrl(uri)) return;
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Number copied: $phone')),
    );
  }
}
