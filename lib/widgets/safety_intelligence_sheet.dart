import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/cold_start_engine.dart';

import '../services/lighting_service.dart';
import '../services/safety_priors.dart';
import '../theme/app_theme.dart';

/// Shows what HALO actually knows about an area, including the awkward parts.
///
/// The design rule for this sheet: never let a computed number imply a claim
/// it cannot support. Every estimate carries its caveat inline, and a
/// provisional picture says "provisional" in its heading, not in fine print.
class SafetyIntelligenceSheet extends StatelessWidget {
  const SafetyIntelligenceSheet({
    super.key,
    required this.picture,
    required this.placesAvailable,
    this.onAddSafeSpot,
  });

  final BaselinePicture picture;
  final bool placesAvailable;
  final VoidCallback? onAddSafeSpot;

  static Future<void> show(
    BuildContext context, {
    required BaselinePicture picture,
    required bool placesAvailable,
    VoidCallback? onAddSafeSpot,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
      ),
      builder: (_) => SafetyIntelligenceSheet(
        picture: picture,
        placesAvailable: placesAvailable,
        onAddSafeSpot: onAddSafeSpot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lighting = picture.lighting;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.radar,
                    size: 20,
                    color: colorBlue,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'What we know about this area',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ProvisionalBanner(provisional: picture.provisional),
              const SizedBox(height: 16),
              if (lighting != null && lighting.hasData) ...[
                _SectionLabel('Street lighting (estimated)'),
                _LightingGauge(assessment: lighting),
                const SizedBox(height: 16),
              ],
              _SectionLabel('Signals'),
              for (final insight in picture.insights) ...[
                _InsightRow(insight: insight),
                const SizedBox(height: 8),
              ],
              if (picture.prior != null) ...[
                const SizedBox(height: 8),
                _PriorDisclosure(prior: picture.prior!),
              ],
              const SizedBox(height: 16),
              _DataSourceRow(
                placesAvailable: placesAvailable,
                prior: picture.prior,
              ),
              if (onAddSafeSpot != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAddSafeSpot,
                    icon: const Icon(LucideIcons.mapPinned, size: 17),
                    label: const Text('Add a safe place here'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvisionalBanner extends StatelessWidget {
  const _ProvisionalBanner({required this.provisional});

  final bool provisional;

  @override
  Widget build(BuildContext context) {
    final color = provisional ? accentGold : colorGreen;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(
            provisional ? LucideIcons.flaskConical : LucideIcons.badgeCheck,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              provisional
                  ? 'Provisional. Nothing below comes from a person who '
                      'lives here - it is inferred from maps and coarse city '
                      'statistics.'
                  : 'Community reports are available here, so this picture '
                      'leans on real experiences first.',
              style: const TextStyle(
                color: textMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: textMuted2,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LightingGauge extends StatelessWidget {
  const _LightingGauge({required this.assessment});

  final LightingAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final color = switch (assessment.band) {
      LightingBand.wellLit => colorGreen,
      LightingBand.partial => accentGold,
      LightingBand.sparse => colorRed,
      LightingBand.unknown => textMuted2,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${(assessment.score * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                assessment.bandLabel,
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(chipRadius),
          child: LinearProgressIndicator(
            value: assessment.score,
            minHeight: 7,
            backgroundColor: bgSurface3,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(assessment.litRoadMeters / 1000).toStringAsFixed(1)} km of '
          'mapped lit road out of '
          '${(assessment.totalRoadMeters / 1000).toStringAsFixed(1)} km, '
          '${assessment.lampCount} street lamps mapped across '
          '${assessment.areaSquareKm.toStringAsFixed(1)} km2.',
          style: const TextStyle(
            color: textMuted2,
            fontSize: 11.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          LightingAssessment.caveat,
          style: TextStyle(
            color: textMuted2,
            fontSize: 11.5,
            height: 1.35,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});

  final BaselineInsight insight;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (insight.kind) {
      BaselineInsightKind.positive => (LucideIcons.circleCheck, colorGreen),
      BaselineInsightKind.caution => (LucideIcons.triangleAlert, accentGold),
      BaselineInsightKind.noReports => (LucideIcons.circleHelp, accentGold),
      BaselineInsightKind.communityData => (LucideIcons.users, colorGreen),
      BaselineInsightKind.informational => (LucideIcons.info, colorBlue),
      BaselineInsightKind.unknown => (LucideIcons.circleHelp, textMuted2),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            insight.text,
            style: const TextStyle(
              color: textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _PriorDisclosure extends StatelessWidget {
  const _PriorDisclosure({required this.prior});

  final SafetyPrior prior;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgSurface3,
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.fileWarning,
                size: 14,
                color: textMuted2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'City-level prior: ${prior.city}',
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            prior.sourceLabel,
            style: const TextStyle(
              color: textMuted2,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataSourceRow extends StatelessWidget {
  const _DataSourceRow({required this.placesAvailable, required this.prior});

  final bool placesAvailable;
  final SafetyPrior? prior;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DATA SOURCES',
          style: TextStyle(
            color: textMuted2,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        _SourceChip(
          icon: LucideIcons.map,
          label: 'OpenStreetMap - lighting and places',
        ),
        const SizedBox(height: 6),
        _SourceChip(
          icon: placesAvailable ? LucideIcons.mapPin : LucideIcons.mapPinOff,
          label: placesAvailable
              ? 'Google Places - business detail'
              : 'Google Places - off, no API key configured',
          muted: !placesAvailable,
        ),
        ...?_whenPrior(prior),
      ],
    );
  }

  List<Widget>? _whenPrior(SafetyPrior? prior) {
    if (prior == null) return null;
    return [
      const SizedBox(height: 6),
      _SourceChip(
        icon: prior.illustrative
            ? LucideIcons.flaskConical
            : LucideIcons.database,
        label: prior.illustrative
            ? 'Regional prior - placeholder, not official'
            : 'Regional prior - ${prior.sourceLabel}',
        muted: prior.illustrative,
      ),
    ];
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? textMuted2 : textMuted;
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
