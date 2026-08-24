import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The states the unlock affordance can be in. Drives which animation plays.
enum BiometricPulseState { idle, scanning, success, error }

/// Fingerprint mark that breathes while idle, sweeps a scan line while the OS
/// prompt is up, and snaps to a check on success.
///
/// Honours [MediaQueryData.disableAnimations]: with it on, every state renders
/// as a still frame, since a looping pulse is exactly the kind of motion people
/// turn that setting off for.
class BiometricPulse extends StatefulWidget {
  const BiometricPulse({
    super.key,
    required this.state,
    this.size = 96,
    this.onTap,
  });

  final BiometricPulseState state;
  final double size;
  final VoidCallback? onTap;

  @override
  State<BiometricPulse> createState() => _BiometricPulseState();
}

class _BiometricPulseState extends State<BiometricPulse>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(BiometricPulse old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncControllers();
  }

  void _syncControllers() {
    switch (widget.state) {
      case BiometricPulseState.idle:
      case BiometricPulseState.scanning:
        _settle.reset();
        if (!_loop.isAnimating) _loop.repeat();
      case BiometricPulseState.success:
        _loop.stop();
        _settle.forward(from: 0);
      case BiometricPulseState.error:
        _loop.stop();
        _settle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final isSuccess = widget.state == BiometricPulseState.success;
    final isError = widget.state == BiometricPulseState.error;

    final tint = isError
        ? cs.error
        : isSuccess
            ? cs.primary
            : cs.primary;

    return Semantics(
      button: widget.onTap != null,
      label: switch (widget.state) {
        BiometricPulseState.scanning => 'Waiting for your fingerprint',
        BiometricPulseState.success => 'Unlocked',
        BiometricPulseState.error => 'Not recognised, tap to try again',
        BiometricPulseState.idle => 'Unlock with biometrics',
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_loop, _settle]),
            builder: (context, _) {
              return CustomPaint(
                painter: _PulsePainter(
                  loop: reduceMotion ? 0 : _loop.value,
                  settle: reduceMotion ? 1 : _settle.value,
                  state: widget.state,
                  tint: tint,
                  track: cs.outline,
                  reduceMotion: reduceMotion,
                ),
                child: Center(
                  child: Icon(
                    isSuccess ? Icons.check_rounded : Icons.fingerprint_rounded,
                    size: widget.size * 0.44,
                    color: tint,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.loop,
    required this.settle,
    required this.state,
    required this.tint,
    required this.track,
    required this.reduceMotion,
  });

  final double loop;
  final double settle;
  final BiometricPulseState state;
  final Color tint;
  final Color track;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Resting ring — always drawn so the control has a shape at rest and with
    // motion disabled.
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = track,
    );

    if (!reduceMotion && state != BiometricPulseState.success) {
      // Two rings half a cycle apart, so one is always mid-expansion.
      for (final phase in [loop, (loop + 0.5) % 1.0]) {
        final t = Curves.easeOut.transform(phase);
        canvas.drawCircle(
          center,
          (radius - 2) + t * 14,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = tint.withValues(alpha: (1 - t) * 0.45),
        );
      }
    }

    if (state == BiometricPulseState.scanning && !reduceMotion) {
      // Sweep an arc round the ring to read as "reading you right now".
      final sweepStart = loop * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2),
        sweepStart,
        math.pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = tint,
      );
    }

    if (state == BiometricPulseState.success) {
      // Ring draws itself closed as confirmation.
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2),
        -math.pi / 2,
        2 * math.pi * Curves.easeOutCubic.transform(settle),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = tint,
      );
    }

    if (state == BiometricPulseState.error && !reduceMotion) {
      // A single decaying shudder, not a loop — it reports, then stops.
      final shake = math.sin(settle * math.pi * 6) * (1 - settle) * 5;
      canvas.drawCircle(
        center + Offset(shake, 0),
        radius - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = tint,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.loop != loop ||
      old.settle != settle ||
      old.state != state ||
      old.tint != tint;
}
