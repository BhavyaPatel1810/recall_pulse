import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.triggerRandomDueCardNotification();
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  await notificationService.init();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    'recall_pulse_nudges',
    'fetchDueCardTask',
    frequency: const Duration(hours: 2),
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HomeScreen(),
  ));
}
