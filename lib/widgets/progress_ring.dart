import 'package:flutter/material.dart';
import '../theme/pulse_colors.dart';

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 52,
    this.stroke = 4.5,
  });

  final double progress;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: stroke,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          CircularProgressIndicator(
            value: value,
            strokeWidth: stroke,
            strokeCap: StrokeCap.round,
            color: PulseColors.cyan,
            backgroundColor: Colors.transparent,
          ),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              color: PulseColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
