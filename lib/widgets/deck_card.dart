import 'package:flutter/material.dart';
import '../theme/pulse_colors.dart';
import 'glass_panel.dart';
import 'progress_ring.dart';

class DeckCard extends StatelessWidget {
  const DeckCard({
    super.key,
    required this.title,
    required this.total,
    required this.due,
    required this.mastered,
    required this.accent,
    required this.onStudy,
    required this.onGenerate,
  });

  final String title;
  final int total;
  final int due;
  final int mastered;
  final Color accent;
  final VoidCallback onStudy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : mastered / total;
    final initial = title.trim().isEmpty ? 'R' : title.trim()[0].toUpperCase();

    return GlassPanel(
      onTap: onStudy,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, PulseColors.indigo],
              ),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PulseColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$total cards',
                  style: const TextStyle(color: PulseColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Badge(
                      label: due > 0 ? '$due due' : 'Caught up',
                      color: due > 0 ? PulseColors.cyan : PulseColors.easy,
                    ),
                    const SizedBox(width: 8),
                    _Badge(
                      label: '$mastered mastered',
                      color: PulseColors.indigo,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ProgressRing(progress: progress),
              const SizedBox(height: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Generate cards',
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                color: PulseColors.cyan,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
