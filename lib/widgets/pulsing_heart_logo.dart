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

/// A pulsing heart-shield logo widget with authentic biological heartbeat rhythm.
class PulsingHeartLogo extends StatefulWidget {
  final double size;

  const PulsingHeartLogo({super.key, this.size = 120});

  @override
  State<PulsingHeartLogo> createState() => _PulsingHeartLogoState();
}

class _PulsingHeartLogoState extends State<PulsingHeartLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAlphaAnimation;

  @override
  void initState() {
    super.initState();
    // Authentic cardiac cycle (~1250ms = resting ~50-60 BPM biological rhythm)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();

    // Cardiac lub-dub dual contraction sequence
    _scaleAnimation = TweenSequence<double>([
      // 1. "Lub" primary systolic beat (quick expansion)
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.13)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 12,
      ),
      // 2. Systolic rebound
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.13, end: 0.98)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 12,
      ),
      // 3. "Dub" secondary pulse (dicrotic wave)
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.98, end: 1.07)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 10,
      ),
      // 4. Secondary recoil back to baseline
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.07, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 10,
      ),
      // 5. Diastolic resting pause between heartbeats
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 56,
      ),
    ]).animate(_controller);

    // Synchronized ambient cardiac aura
    _glowAlphaAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 10, end: 65)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 65, end: 15)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 15, end: 40)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 40, end: 8)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(8),
        weight: 56,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _scaleAnimation.value;
        final alpha = _glowAlphaAnimation.value.toInt().clamp(0, 255);
        final blur = (28.0 * (scale - 0.95)).clamp(4.0, 32.0);

        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: PulseColors.crimson.withAlpha(alpha),
                  blurRadius: blur,
                  spreadRadius: (scale > 1.0) ? (scale - 1.0) * 10.0 : 0.0,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Image.asset(
        'assets/images/pulseguard_logo.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Graceful fallback for test or unbundled asset environments
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: const HeartShieldPainter(),
          );
        },
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
