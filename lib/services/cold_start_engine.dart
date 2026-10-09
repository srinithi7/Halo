import 'dart:async';

import 'package:latlong2/latlong.dart' as ll;

import 'lighting_service.dart';
import 'safety_priors.dart';

/// The picture of an area that has no reports in it yet.
///
/// This exists to solve a specific, honest problem: a brand-new city renders
/// as a blank map, and a blank map reads as "all clear" when it actually
/// means "nobody has told us anything". The baseline says which of those it
/// is.
///
/// Everything in [BaselinePicture] is an **estimate from proxies**. It is
/// never a report, never an incident, and never presented as lived
/// experience. The whole object is [provisional] when the area has no
/// community data, and that flag must gate how it is rendered.
class BaselinePicture {
  const BaselinePicture({
    required this.center,
    required this.lighting,
    required this.prior,
    required this.safeSpotCount,
    required this.heroCount,
    required this.provisional,
    required this.computedAt,
  });

  final ll.LatLng center;
  final LightingAssessment? lighting;
  final SafetyPrior? prior;
  final int safeSpotCount;
  final int heroCount;

  /// True when this is built from proxies alone, with no community reports in
  /// the area. The UI must say so.
  final bool provisional;

  final DateTime computedAt;

  /// Lines of honest, actionable text about what HALO actually knows here.
  List<BaselineInsight> get insights {
    final result = <BaselineInsight>[];

    if (!provisional) {
      result.add(
        const BaselineInsight(
          BaselineInsightKind.communityData,
          'Community reports exist in this area, so this picture is built on '
          'real reports first.',
        ),
      );
    } else {
      result.add(
        const BaselineInsight(
          BaselineInsightKind.noReports,
          'No reports here yet. An empty map does not mean a safe street - it '
          'usually means nobody has reported yet.',
        ),
      );
    }

    final light = lighting;
    if (light == null || !light.hasData) {
      result.add(
        const BaselineInsight(
          BaselineInsightKind.unknown,
          'Street lighting for this area is not mapped on OpenStreetMap, so '
          'we cannot estimate it either way.',
        ),
      );
    } else {
      result.add(
        BaselineInsight(
          light.band == LightingBand.sparse
              ? BaselineInsightKind.caution
              : BaselineInsightKind.informational,
          '${light.bandLabel}. ${LightingAssessment.caveat}',
        ),
      );
    }

    if (safeSpotCount > 0) {
      result.add(
        BaselineInsight(
          BaselineInsightKind.positive,
          '$safeSpotCount known place${safeSpotCount == 1 ? '' : 's'} nearby '
          'to head to if you need to be somewhere with people in it.',
        ),
      );
    } else {
      result.add(
        const BaselineInsight(
          BaselineInsightKind.caution,
          'No safe places are mapped here yet. Adding one is the single most '
          'useful thing you can do for the next person.',
        ),
      );
    }

    if (heroCount > 0) {
      result.add(
        BaselineInsight(
          BaselineInsightKind.positive,
          '$heroCount Unseen Hero${heroCount == 1 ? '' : 's'} nearby and open '
          'to being contacted.',
        ),
      );
    }

    final cityPrior = prior;
    if (cityPrior != null) {
      result.add(
        BaselineInsight(
          cityPrior.relativeReportingIndex < 0.4
              ? BaselineInsightKind.caution
              : BaselineInsightKind.informational,
          'Under-reporting in ${cityPrior.city} is likely, so treat a quiet '
          'map here as missing information rather than good news.',
        ),
      );
    } else {
      result.add(
        const BaselineInsight(
          BaselineInsightKind.unknown,
          'No regional prior covers this area, so nothing has been assumed '
          'about it.',
        ),
      );
    }

    return result;
  }

  /// The single most important caveat, for places with limited room.
  String get headline {
    if (!provisional) return 'Based on reports and local data';
    return 'Provisional estimate - no reports here yet';
  }
}

enum BaselineInsightKind {
  positive,
  caution,
  informational,
  noReports,
  communityData,
  unknown
}

class BaselineInsight {
  const BaselineInsight(this.kind, this.text);

  final BaselineInsightKind kind;
  final String text;
}

/// Builds a [BaselinePicture] from whatever data exists, and is explicit when
/// nothing does.
class ColdStartEngine {
  ColdStartEngine({
    LightingService? lighting,
    SafetyPriorSource? priors,
  })  : _lighting = lighting ?? LightingService(),
        _priors = priors ?? const IllustrativeSafetyPriorSource();

  final LightingService _lighting;
  final SafetyPriorSource _priors;

  SafetyPriorSource get priors => _priors;

  /// Assembles the picture for an area.
  ///
  /// [reportCount] and the spot/hero counts come from the live streams. A
  /// lighting failure is swallowed deliberately: a missing lighting estimate
  /// must degrade the answer, never prevent it.
  Future<BaselinePicture> build({
    required ll.LatLng center,
    required int reportCount,
    required int safeSpotCount,
    required int heroCount,
    double radiusMeters = 1500,
  }) async {
    LightingAssessment? lighting;
    try {
      lighting = await _lighting.assess(
        center: center,
        radiusMeters: radiusMeters,
      );
    } catch (_) {
      lighting = null;
    }

    return BaselinePicture(
      center: center,
      lighting: lighting,
      prior: _priors.priorFor(center),
      safeSpotCount: safeSpotCount,
      heroCount: heroCount,
      provisional: reportCount == 0,
      computedAt: DateTime.now(),
    );
  }

  void dispose() => _lighting.dispose();
}
