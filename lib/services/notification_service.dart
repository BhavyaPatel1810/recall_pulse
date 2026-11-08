import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'database_helper.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    // Named parameter 'settings:' required by latest plugin
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  Future<void> triggerRandomDueCardNotification() async {
    final dueCards = await DatabaseHelper.instance.getDueFlashcards();
    if (dueCards.isEmpty) return;

    final randomCard = dueCards[Random().nextInt(dueCards.length)];

    final BigTextStyleInformation bigTextStyleInformation = BigTextStyleInformation(
      randomCard.question,
      htmlFormatBigText: false,
      contentTitle: 'RecallPulse: Quick Revision!',
      summaryText: 'Tap karke answer check karein',
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'recall_pulse_channel',
      'Flashcard Nudges',
      channelDescription: 'Spaced repetition revision popups',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: bigTextStyleInformation,
    );

    final NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    // Named parameters for show()
    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: 'RecallPulse: Quick Revision!',
      body: randomCard.question,
      notificationDetails: notificationDetails,
      payload: randomCard.id,
    );
  }
}
