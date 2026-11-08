import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/pulse_colors.dart';

class FlipFlashcard extends StatefulWidget {
  const FlipFlashcard({
    super.key,
    required this.question,
    required this.answer,
    this.explanation = '',
    required this.revealed,
    required this.onToggle,
  });

  final String question;
  final String answer;
  final String explanation;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  State<FlipFlashcard> createState() => _FlipFlashcardState();
}

class _FlipFlashcardState extends State<FlipFlashcard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _angle = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    if (widget.revealed) _controller.value = 1;
  }

  @override
  void didUpdateWidget(FlipFlashcard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed == oldWidget.revealed) return;
    if (widget.revealed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_controller.isAnimating) return;
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _angle,
        builder: (context, _) {
          final angle = _angle.value;
          final showFront = angle < math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: showFront ? _face(front: true) : _face(front: false),
          );
        },
      ),
    );
  }

  Widget _face({required bool front}) {
    final face = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PulseColors.cyan, PulseColors.indigo, PulseColors.cyan],
        ),
      ),
      padding: const EdgeInsets.all(1.6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26.4),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  front ? 'QUESTION' : 'ANSWER',
                  style: TextStyle(
                    color: front ? PulseColors.cyan : PulseColors.easy,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(
                          front ? widget.question : widget.answer,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: PulseColors.text,
                            fontSize: 24,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!front && widget.explanation.trim().isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            widget.explanation,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: PulseColors.muted,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                front ? 'Tap to flip' : 'Rate your recall',
                style: const TextStyle(color: PulseColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );

    if (front) return face;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(math.pi),
      child: face,
    );
  }
}
