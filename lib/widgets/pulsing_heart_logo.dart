// lib/widgets/pulsing_heart_logo.dart
//
// PulseGuard — Phase 6: Pulsing brand logo & transit loading overlay.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable CustomPainter drawing the PulseGuard heart inside the shield.
class HeartShieldPainter extends CustomPainter {
  final Color shieldColor;
  final Color borderColor;
  final Color heartColor;
  final double borderWidth;

  const HeartShieldPainter({
    this.shieldColor = const Color(0xFFF2D5D5),
    this.borderColor = PulseColors.crimson,
    this.heartColor = PulseColors.crimson,
    this.borderWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Shield path
    final shieldPath = Path()
      ..moveTo(cx, size.height * 0.05)
      ..cubicTo(cx - size.width * 0.55, size.height * 0.0,
          cx - size.width * 0.5, size.height * 0.45,
          cx, size.height * 0.95)
      ..cubicTo(cx + size.width * 0.5, size.height * 0.45,
          cx + size.width * 0.55, size.height * 0.0,
          cx, size.height * 0.05);
    shieldPath.close();

    final shieldFill = Paint()
      ..color = shieldColor
      ..style = PaintingStyle.fill;
    final shieldBorder = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawPath(shieldPath, shieldFill);
    canvas.drawPath(shieldPath, shieldBorder);

    // Heart icon inside shield
    final heartSize = size.width * 0.38;
    final heartX = cx;
    final heartY = cy + size.height * 0.02;

    final heartPath = Path()..moveTo(heartX, heartY + heartSize * 0.25);

    // Left lobe
    heartPath.cubicTo(
      heartX - heartSize * 0.5, heartY - heartSize * 0.15,
      heartX - heartSize * 0.7, heartY - heartSize * 0.5,
      heartX - heartSize * 0.2, heartY - heartSize * 0.5,
    );
    heartPath.cubicTo(
      heartX, heartY - heartSize * 0.5,
      heartX, heartY - heartSize * 0.25,
      heartX, heartY - heartSize * 0.1,
    );

    // Right lobe
    heartPath.cubicTo(
      heartX, heartY - heartSize * 0.25,
      heartX, heartY - heartSize * 0.5,
      heartX + heartSize * 0.2, heartY - heartSize * 0.5,
    );
    heartPath.cubicTo(
      heartX + heartSize * 0.7, heartY - heartSize * 0.5,
      heartX + heartSize * 0.5, heartY - heartSize * 0.15,
      heartX, heartY + heartSize * 0.25,
    );
    heartPath.close();

    final heartPaint = Paint()
      ..color = heartColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(heartPath, heartPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A pulsing heart-shield logo widget with slow, biological rhythm.
class PulsingHeartLogo extends StatefulWidget {
  final double size;

  const PulsingHeartLogo({super.key, this.size = 120});

  @override
  State<PulsingHeartLogo> createState() => _PulsingHeartLogoState();
}

class _PulsingHeartLogoState extends State<PulsingHeartLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: const HeartShieldPainter(),
      ),
    );
  }
}

/// Fullscreen or modal transit overlay with pulsing logo and message.
class TransitLoadingOverlay extends StatelessWidget {
  final String message;

  const TransitLoadingOverlay({
    super.key,
    this.message = 'Loading biometric telemetry...',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: PulseColors.cream,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: PulseColors.crimson, width: 2),
          boxShadow: [
            BoxShadow(
              color: PulseColors.crimson.withAlpha(40),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PulsingHeartLogo(size: 90),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: PulseTextStyles.bodyMedium.copyWith(
                color: PulseColors.crimson,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
