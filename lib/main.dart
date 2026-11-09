import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/deck.dart';
import 'models/flashcard.dart';
import 'screens/ai_card_creator_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/deck_detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/database_helper.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'theme/pulse_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure Deep Obsidian Dark system chrome bars
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: PulseTheme.bgPrimary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize SQLite FFI for Desktop platforms (Linux, Windows, macOS)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Warm up core local database & services safely
  try {
    await DatabaseHelper.instance.database;
    await SettingsService.instance.getSelectedModel();
    await AuthService.instance.initialize();
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('RecallPulse startup initialization notice: $e');
  }

  runApp(const RecallPulseApp());
}

class RecallPulseApp extends StatelessWidget {
  const RecallPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RecallPulse',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      theme: PulseTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/ai-creator': (context) => const AiCardCreatorScreen(),
        '/notifications': (context) => const NotificationSettingsScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/auth': (context) => const AuthScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/deck-detail') {
          final deck = settings.arguments as Deck;
          return MaterialPageRoute(
            builder: (_) => DeckDetailScreen(deck: deck),
          );
        }
        if (settings.name == '/review') {
          final args = settings.arguments;
          if (args is Deck) {
            return MaterialPageRoute(
              builder: (_) => ReviewScreen(deck: args),
            );
          } else if (args is Map<String, dynamic>) {
            final deck = args['deck'] as Deck;
            final customCards = args['customCards'] as List<Flashcard>?;
            return MaterialPageRoute(
              builder: (_) => ReviewScreen(
                deck: deck,
                customCards: customCards,
              ),
            );
          }
        }
        return null;
      },
    );
  }
}