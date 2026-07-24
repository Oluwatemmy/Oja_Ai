import 'package:flutter/material.dart';

import '../theme.dart';

class MicIcon extends StatelessWidget {
  const MicIcon({super.key, this.size = 72, this.color = OjaColors.cream});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.mic_rounded, size: size, color: color);
  }
}

/// Gold pulsing circle shown while Gemma dey hear you.
class PulsingCircle extends StatefulWidget {
  const PulsingCircle({
    super.key,
    required this.child,
    required this.color,
    this.size = 190,
    this.glowColor,
  });

  final Widget child;
  final Color color;
  final double size;
  final Color? glowColor;

  @override
  State<PulsingCircle> createState() => _PulsingCircleState();
}

class _PulsingCircleState extends State<PulsingCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.glowColor ?? widget.color;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final spread = 14 + 12 * _controller.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.25 - 0.13 * _controller.value),
                spreadRadius: spread,
              ),
              BoxShadow(
                color: OjaColors.navy.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Seven dancing bars, like the prototype's ojaWave animation.
class WaveformBars extends StatefulWidget {
  const WaveformBars({super.key, this.height = 40, this.barWidth = 7});

  final double height;
  final double barWidth;

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  static const _delays = [0.0, .12, .24, .36, .48, .6, .72];
  static const _colors = [
    OjaColors.gold,
    OjaColors.gold,
    OjaColors.navy,
    OjaColors.gold,
    OjaColors.navy,
    OjaColors.gold,
    OjaColors.gold,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _delays.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              _bar(i),
            ],
          ],
        );
      },
    );
  }

  Widget _bar(int index) {
    var t = (_controller.value - _delays[index]) % 1.0;
    if (t < 0) t += 1.0;
    // 0.3 -> 1.0 -> 0.3 like scaleY keyframes.
    final scale = 0.3 + 0.7 * (1 - (2 * t - 1).abs());
    return Container(
      width: widget.barWidth,
      height: widget.height * scale,
      decoration: BoxDecoration(
        color: _colors[index],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Three blinking dots — "E dey write am…".
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.dotSize = 16});

  final double dotSize;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  static const _delays = [0.0, 0.2, 0.4];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _delays.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _dot(i),
            ],
          ],
        );
      },
    );
  }

  Widget _dot(int index) {
    var t = (_controller.value - _delays[index]) % 1.0;
    if (t < 0) t += 1.0;
    final opacity = 0.25 + 0.75 * (1 - (2 * t - 1).abs());
    return Opacity(
      opacity: opacity,
      child: Container(
        width: widget.dotSize,
        height: widget.dotSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: OjaColors.navy,
        ),
      ),
    );
  }
}
