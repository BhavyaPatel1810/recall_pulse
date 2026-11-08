import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'theme/pulse_colors.dart';
import 'theme/pulse_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: PulseColors.obsidian,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RecallPulseApp());
}

class RecallPulseApp extends StatelessWidget {
  const RecallPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RecallPulse',
      debugShowCheckedModeBanner: false,
      theme: PulseTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
