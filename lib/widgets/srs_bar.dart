import 'package:flutter/material.dart';
import '../logic/spaced_repetition.dart';
import '../theme/pulse_colors.dart';

class SrsBar extends StatelessWidget {
  const SrsBar({super.key, required this.onRate});

  final ValueChanged<ReviewRating> onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SrsButton(
          label: 'Again',
          color: PulseColors.again,
          onPressed: () => onRate(ReviewRating.again),
        ),
        const SizedBox(width: 8),
        _SrsButton(
          label: 'Hard',
          color: PulseColors.hard,
          onPressed: () => onRate(ReviewRating.hard),
        ),
        const SizedBox(width: 8),
        _SrsButton(
          label: 'Good',
          color: PulseColors.good,
          onPressed: () => onRate(ReviewRating.good),
        ),
        const SizedBox(width: 8),
        _SrsButton(
          label: 'Easy',
          color: PulseColors.easy,
          onPressed: () => onRate(ReviewRating.easy),
        ),
      ],
    );
  }
}

class _SrsButton extends StatelessWidget {
  const _SrsButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.75)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
