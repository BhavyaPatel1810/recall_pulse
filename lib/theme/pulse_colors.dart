import 'package:flutter/material.dart';

/// Obsidian surfaces and neon accents shared across RecallPulse.
abstract final class PulseColors {
  static const Color obsidian = Color(0xFF0F172A);
  static const Color slate = Color(0xFF1E293B);
  static const Color slateRaised = Color(0xFF273449);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color indigo = Color(0xFF6366F1);
  static const Color text = Color(0xFFF8FAFC);
  static const Color muted = Color(0xFF94A3B8);
  static const Color line = Color(0x33FFFFFF);
  static const Color again = Color(0xFFF87171);
  static const Color hard = Color(0xFFFBBF24);
  static const Color good = Color(0xFF7DD3FC);
  static const Color easy = Color(0xFF34D399);

  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, indigo],
  );
}
