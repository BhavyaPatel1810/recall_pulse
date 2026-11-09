import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../screens/review_screen.dart';
import 'database_helper.dart';

enum NotificationCardMode {
  customStarred, // Mode A: Only explicitly starred cards (isStarredForNotification == true)
  specificDeck,  // Mode B: Due cards from a specific target deck
  allDue,        // Mode C: All currently due cards across the database
}

class NotificationConfig {
  final bool isEnabled;
  final NotificationCardMode mode;
  final String? targetDeckId;
  final int dailyFrequency;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  const NotificationConfig({
    this.isEnabled = false,
    this.mode = NotificationCardMode.customStarred,
    this.targetDeckId,
    this.dailyFrequency = 5,
    this.startTime = const TimeOfDay(hour: 8, minute: 0),
    this.endTime = const TimeOfDay(hour: 22, minute: 0),
  });

  NotificationConfig copyWith({
    bool? isEnabled,
    NotificationCardMode? mode,
    String? targetDeckId,
    int? dailyFrequency,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return NotificationConfig(
      isEnabled: isEnabled ?? this.isEnabled,
      mode: mode ?? this.mode,
      targetDeckId: targetDeckId ?? this.targetDeckId,
      dailyFrequency: dailyFrequency ?? this.dailyFrequency,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

class _ScheduledCardItem {
  final Deck deck;
  final Flashcard card;

  const _ScheduledCardItem({required this.deck, required this.card});
}

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  NotificationService._init();

  /// Attach this navigatorKey to MaterialApp(navigatorKey: NotificationService.navigatorKey)
  /// so tapping a notification deep-links directly into the ReviewScreen.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  Timer? _linuxDesktopTimer;
  String? _lastLinuxTriggeredMinuteKey;

  // SharedPreferences Keys
  static const String _prefEnabled = 'pulse_notif_enabled';
  static const String _prefMode = 'pulse_notif_mode';
  static const String _prefTargetDeck = 'pulse_notif_target_deck';
  static const String _prefFrequency = 'pulse_notif_frequency';
  static const String _prefStartHour = 'pulse_notif_start_hour';
  static const String _prefStartMin = 'pulse_notif_start_min';
  static const String _prefEndHour = 'pulse_notif_end_hour';
  static const String _prefEndMin = 'pulse_notif_end_min';

  static const String _channelId = 'recallpulse_srs_channel';
  static const String _channelName = 'RecallPulse Active Recall Pulses';
  static const String _channelDesc = 'Scheduled flashcard active recall prompts throughout the day';

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Review Flashcard',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService initialization warning: $e');
    }

    // Re-sync schedule on startup if enabled
    final config = await loadConfig();
    if (config.isEnabled) {
      await scheduleDailyNotifications(config: config);
    }
  }

  /// Requests Android 13+ (API 33+) notification and exact alarm runtime permissions.
  Future<bool> requestPermissions() async {
    if (!_isInitialized) await initialize();

    if (Platform.isAndroid) {
      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission() ?? false;
        try {
          await androidImpl.requestExactAlarmsPermission();
        } catch (_) {
          // Fallback to inexact scheduling if exact alarm permission is restricted
        }
        return granted;
      }
    }
    return true;
  }

  Future<NotificationConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(_prefEnabled) ?? false;
    final modeStr = prefs.getString(_prefMode) ?? NotificationCardMode.customStarred.name;
    final targetDeckId = prefs.getString(_prefTargetDeck);
    final frequency = (prefs.getInt(_prefFrequency) ?? 5).clamp(1, 15);
    final startHour = prefs.getInt(_prefStartHour) ?? 8;
    final startMin = prefs.getInt(_prefStartMin) ?? 0;
    final endHour = prefs.getInt(_prefEndHour) ?? 22;
    final endMin = prefs.getInt(_prefEndMin) ?? 0;

    final mode = NotificationCardMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => NotificationCardMode.customStarred,
    );

    return NotificationConfig(
      isEnabled: isEnabled,
      mode: mode,
      targetDeckId: targetDeckId,
      dailyFrequency: frequency,
      startTime: TimeOfDay(hour: startHour, minute: startMin),
      endTime: TimeOfDay(hour: endHour, minute: endMin),
    );
  }

  Future<void> saveConfig(NotificationConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, config.isEnabled);
    await prefs.setString(_prefMode, config.mode.name);
    if (config.targetDeckId != null) {
      await prefs.setString(_prefTargetDeck, config.targetDeckId!);
    } else {
      await prefs.remove(_prefTargetDeck);
    }
    await prefs.setInt(_prefFrequency, config.dailyFrequency.clamp(1, 15));
    await prefs.setInt(_prefStartHour, config.startTime.hour);
    await prefs.setInt(_prefStartMin, config.startTime.minute);
    await prefs.setInt(_prefEndHour, config.endTime.hour);
    await prefs.setInt(_prefEndMin, config.endTime.minute);

    await scheduleDailyNotifications(config: config);
  }

  /// Calculates evenly spaced notification trigger times across the active window [startTime .. endTime].
  List<TimeOfDay> calculateTriggerTimes({
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required int frequency,
  }) {
    final count = frequency.clamp(1, 15);
    final int startMins = startTime.hour * 60 + startTime.minute;
    int endMins = endTime.hour * 60 + endTime.minute;

    if (endMins <= startMins) {
      // Ensure at least a 60-minute forward window if user picks an earlier end time
      endMins = min(23 * 60 + 59, startMins + 60);
    }

    if (count == 1) {
      return [startTime];
    }

    final List<TimeOfDay> triggers = [];
    final double intervalStep = (endMins - startMins) / (count - 1);

    for (int i = 0; i < count; i++) {
      final int slotMins = (startMins + (intervalStep * i)).round().clamp(0, 23 * 60 + 59);
      triggers.add(TimeOfDay(hour: slotMins ~/ 60, minute: slotMins % 60));
    }

    return triggers;
  }

  /// Resolves candidate flashcards according to Mode A, Mode B, or Mode C.
  Future<List<_ScheduledCardItem>> _resolveCandidateCards(NotificationConfig config) async {
    final allDecks = await DatabaseHelper.instance.getAllDecks();
    if (allDecks.isEmpty) return [];

    final Map<String, Deck> deckMap = {for (final d in allDecks) d.id: d};
    final List<_ScheduledCardItem> candidates = [];

    switch (config.mode) {
      case NotificationCardMode.customStarred:
        final starred = await DatabaseHelper.instance.getStarredCards();
        for (final card in starred) {
          final deck = deckMap[card.deckId];
          if (deck != null) {
            candidates.add(_ScheduledCardItem(deck: deck, card: card));
          }
        }
        break;

      case NotificationCardMode.specificDeck:
        final deckId = config.targetDeckId ?? allDecks.first.id;
        final deck = deckMap[deckId] ?? allDecks.first;
        List<Flashcard> cards = await DatabaseHelper.instance.getDueFlashcardsForDeck(deck.id);
        if (cards.isEmpty) {
          // Fallback to all cards in the selected deck if none are currently due
          cards = await DatabaseHelper.instance.getFlashcardsForDeck(deck.id);
        }
        for (final card in cards) {
          candidates.add(_ScheduledCardItem(deck: deck, card: card));
        }
        break;

      case NotificationCardMode.allDue:
        for (final deck in allDecks) {
          final dueCards = await DatabaseHelper.instance.getDueFlashcardsForDeck(deck.id);
          for (final card in dueCards) {
            candidates.add(_ScheduledCardItem(deck: deck, card: card));
          }
        }
        if (candidates.isEmpty) {
          // Fallback to all flashcards if 0 cards are currently overdue
          for (final deck in allDecks) {
            final deckCards = await DatabaseHelper.instance.getFlashcardsForDeck(deck.id);
            for (final card in deckCards) {
              candidates.add(_ScheduledCardItem(deck: deck, card: card));
            }
          }
        }
        break;
    }

    return candidates;
  }

  /// Schedules the daily flashcard notifications across Android and Linux Desktop.
  Future<int> scheduleDailyNotifications({NotificationConfig? config}) async {
    if (!_isInitialized) await initialize();

    final activeConfig = config ?? await loadConfig();
    await cancelAllNotifications();

    if (!activeConfig.isEnabled) {
      return 0;
    }

    final candidates = await _resolveCandidateCards(activeConfig);
    if (candidates.isEmpty) {
      return 0;
    }

    final shuffled = List<_ScheduledCardItem>.from(candidates)..shuffle(Random());
    final triggerTimes = calculateTriggerTimes(
      startTime: activeConfig.startTime,
      endTime: activeConfig.endTime,
      frequency: activeConfig.dailyFrequency,
    );

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      _startDesktopScheduleTimer(triggerTimes, shuffled);
      return triggerTimes.length;
    }

    int scheduledCount = 0;
    final now = tz.TZDateTime.now(tz.local);

    for (int i = 0; i < triggerTimes.length; i++) {
      final slot = triggerTimes[i];
      final item = shuffled[i % shuffled.length];

      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        slot.hour,
        slot.minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      final payload = jsonEncode({
        'deckId': item.deck.id,
        'cardId': item.card.id,
      });

      final details = _buildNotificationDetails(item);

      try {
        await _notificationsPlugin.zonedSchedule(
          1000 + i,
          '⚡ ${item.deck.title}',
          item.card.question,
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
        scheduledCount++;
      } catch (_) {
        // Fallback to inexact scheduling if exact alarms are restricted by OS
        try {
          await _notificationsPlugin.zonedSchedule(
            1000 + i,
            '⚡ ${item.deck.title}',
            item.card.question,
            scheduledDate,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: payload,
          );
          scheduledCount++;
        } catch (err) {
          debugPrint('Failed to schedule slot $i: $err');
        }
      }
    }

    return scheduledCount;
  }

  /// Safe non-crashing desktop notification scheduler for Linux where zonedSchedule is unsupported.
  void _startDesktopScheduleTimer(
    List<TimeOfDay> triggerTimes,
    List<_ScheduledCardItem> items,
  ) {
    _linuxDesktopTimer?.cancel();
    _linuxDesktopTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = DateTime.now();
      final minuteKey = '${now.year}-${now.month}-${now.day}-${now.hour}:${now.minute}';
      if (_lastLinuxTriggeredMinuteKey == minuteKey) return;

      for (int i = 0; i < triggerTimes.length; i++) {
        final slot = triggerTimes[i];
        if (slot.hour == now.hour && slot.minute == now.minute) {
          _lastLinuxTriggeredMinuteKey = minuteKey;
          final item = items[i % items.length];
          await _showImmediateItemNotification(
            id: 2000 + i,
            item: item,
          );
          break;
        }
      }
    });
  }

  /// Triggers an immediate test notification using a card from the user's current selection mode.
  Future<bool> sendTestNotificationNow({NotificationConfig? config}) async {
    if (!_isInitialized) await initialize();
    await requestPermissions();

    final activeConfig = config ?? await loadConfig();
    List<_ScheduledCardItem> candidates = await _resolveCandidateCards(activeConfig);

    if (candidates.isEmpty) {
      // Fallback to any card in the DB if the user hasn't starred any yet
      final decks = await DatabaseHelper.instance.getAllDecks();
      for (final d in decks) {
        final cards = await DatabaseHelper.instance.getFlashcardsForDeck(d.id);
        if (cards.isNotEmpty) {
          candidates.add(_ScheduledCardItem(deck: d, card: cards.first));
          break;
        }
      }
    }

    if (candidates.isEmpty) {
      return false;
    }

    final randomItem = candidates[Random().nextInt(candidates.length)];
    return await _showImmediateItemNotification(id: 9999, item: randomItem);
  }

  Future<bool> _showImmediateItemNotification({
    required int id,
    required _ScheduledCardItem item,
  }) async {
    final payload = jsonEncode({
      'deckId': item.deck.id,
      'cardId': item.card.id,
    });

    final details = _buildNotificationDetails(item);

    try {
      await _notificationsPlugin.show(
        id,
        '⚡ ${item.deck.title}',
        item.card.question,
        details,
        payload: payload,
      );
      return true;
    } catch (e) {
      debugPrint('Desktop/Mobile notification dispatch error: $e');
      return false;
    }
  }

  NotificationDetails _buildNotificationDetails(_ScheduledCardItem item) {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        item.card.question,
        contentTitle: '⚡ ${item.deck.title}',
        summaryText: 'Tap to flip & review in RecallPulse',
      ),
      category: AndroidNotificationCategory.reminder,
    );

    const linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
    );

    return NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
    );
  }

  Future<void> cancelAllNotifications() async {
    _linuxDesktopTimer?.cancel();
    _linuxDesktopTimer = null;
    try {
      await _notificationsPlugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _onNotificationTapped(NotificationResponse response) async {
    final payloadStr = response.payload;
    if (payloadStr == null || payloadStr.isEmpty) return;

    try {
      final map = jsonDecode(payloadStr) as Map<String, dynamic>;
      final deckId = map['deckId'] as String?;
      final cardId = map['cardId'] as String?;
      if (deckId == null) return;

      final deck = await DatabaseHelper.instance.getDeckById(deckId);
      if (deck == null) return;

      final deckCards = await DatabaseHelper.instance.getFlashcardsForDeck(deckId);
      if (deckCards.isEmpty) return;

      // Prioritize the exact flashcard that appeared in the notification
      final List<Flashcard> orderedQueue = [];
      if (cardId != null) {
        final target = deckCards.where((c) => c.id == cardId).toList();
        orderedQueue.addAll(target);
        orderedQueue.addAll(deckCards.where((c) => c.id != cardId));
      } else {
        orderedQueue.addAll(deckCards);
      }

      final navState = navigatorKey.currentState;
      if (navState != null) {
        navState.push(
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              deck: deck,
              customCards: orderedQueue,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error handling notification tap payload: $e');
    }
  }
}