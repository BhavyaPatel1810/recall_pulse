import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pulse_colors.dart';

abstract final class PulseTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: PulseColors.cyan,
      onPrimary: PulseColors.obsidian,
      secondary: PulseColors.indigo,
      onSecondary: Colors.white,
      surface: PulseColors.slate,
      onSurface: PulseColors.text,
      error: PulseColors.again,
      onError: PulseColors.obsidian,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PulseColors.obsidian,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: PulseColors.text,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: PulseColors.obsidian,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: PulseColors.slateRaised,
        contentTextStyle: const TextStyle(color: PulseColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PulseColors.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: PulseColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          color: PulseColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: PulseColors.text,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: PulseColors.text, height: 1.4),
        bodyMedium: TextStyle(color: PulseColors.muted, height: 1.4),
        labelLarge: TextStyle(
          color: PulseColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
