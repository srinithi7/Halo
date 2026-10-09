import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// HALO's mark: a ring of 8 muted gold dots around a larger glowing center
/// dot, drawn with CustomPainter (no image/emoji asset). Optionally paired
/// with the "HALO" wordmark in Sora ExtraBold.
class HaloLogo extends StatelessWidget {
  const HaloLogo({super.key, this.size = 64, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _HaloLogoPainter()),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.18),
          Text(
            'HALO',
            style: GoogleFonts.sora(
              fontSize: size * 0.34,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: 2,
            ),
          ),
        ],
      ],
    );
  }
}

class _HaloLogoPainter extends CustomPainter {
  static const _dotCount = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.width / 2 * 0.72;
    final dotRadius = size.width * 0.045;
    final centerDotRadius = size.width * 0.09;

    final dotPaint = Paint()..color = accentGold.withValues(alpha: 0.55);
    for (var i = 0; i < _dotCount; i++) {
      final angle = (2 * math.pi / _dotCount) * i - math.pi / 2;
      final dotCenter =
          center + Offset(math.cos(angle), math.sin(angle)) * ringRadius;
      canvas.drawCircle(dotCenter, dotRadius, dotPaint);
    }

    final glowPaint = Paint()
      ..color = accentGold.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, centerDotRadius * 1.8, glowPaint);

    canvas.drawCircle(center, centerDotRadius, Paint()..color = accentGold);
  }

  @override
  bool shouldRepaint(covariant _HaloLogoPainter oldDelegate) => false;
}
