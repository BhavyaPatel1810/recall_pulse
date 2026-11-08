import 'package:flutter/material.dart';
import '../theme/pulse_colors.dart';

class PulseFab extends StatefulWidget {
  const PulseFab({super.key, required this.onPressed, this.enabled = true});

  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<PulseFab> createState() => _PulseFabState();
}

class _PulseFabState extends State<PulseFab> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
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
        final t = Curves.easeInOut.transform(_controller.value);
        final scale = widget.enabled ? 1 + (t * 0.045) : 1.0;
        final glow = widget.enabled ? 0.28 + (t * 0.35) : 0.08;
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: PulseColors.cyan.withValues(alpha: glow),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: PulseColors.indigo.withValues(alpha: glow * 0.7),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: FloatingActionButton.extended(
        onPressed: widget.onPressed,
        elevation: 0,
        backgroundColor: widget.enabled ? PulseColors.cyan : PulseColors.slateRaised,
        foregroundColor: widget.enabled ? PulseColors.obsidian : PulseColors.muted,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text(
          'Quick study',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
