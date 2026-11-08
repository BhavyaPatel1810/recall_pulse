import 'package:flutter/material.dart';
import '../theme/pulse_colors.dart';

class GenerateLoader extends StatefulWidget {
  const GenerateLoader({super.key});

  @override
  State<GenerateLoader> createState() => _GenerateLoaderState();
}

class _GenerateLoaderState extends State<GenerateLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.rotate(
              angle: _controller.value * 6.28318,
              child: child,
            );
          },
          child: Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  PulseColors.cyan,
                  PulseColors.indigo,
                  Colors.transparent,
                  PulseColors.cyan,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: PulseColors.obsidian,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: PulseColors.cyan.withValues(alpha: 0.95),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Building your cards',
          style: TextStyle(
            color: PulseColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Turning the material into active recall',
          style: TextStyle(color: PulseColors.muted),
        ),
      ],
    );
  }
}
