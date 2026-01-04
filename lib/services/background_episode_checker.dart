import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'background_task_handler.dart';

class BackgroundEpisodeChecker {
  static const Duration _checkInterval = Duration(hours: 1);

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint('BackgroundEpisodeChecker: Not supported on this platform');
      return;
    }

    await Workmanager().initialize(
      callbackDispatcher,
    );
    debugPrint('BackgroundEpisodeChecker: Initialized');
  }

  static Future<void> registerBackgroundTask() async {
    if (kIsWeb || !Platform.isAndroid) return;

    await cancelBackgroundTask();

    await Workmanager().registerPeriodicTask(
      episodeCheckTask,
      episodeCheckTask,
      frequency: _checkInterval,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 15),
    );

    debugPrint('BackgroundEpisodeChecker: Periodic task registered (every ${_checkInterval.inMinutes} minutes)');
  }

  static Future<void> cancelBackgroundTask() async {
    if (kIsWeb || !Platform.isAndroid) return;

    await Workmanager().cancelByUniqueName(episodeCheckTask);
    debugPrint('BackgroundEpisodeChecker: Task cancelled');
  }

  static Future<void> runImmediateCheck() async {
    if (kIsWeb || !Platform.isAndroid) return;

    await Workmanager().registerOneOffTask(
      '${episodeCheckTask}_immediate',
      episodeCheckTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    debugPrint('BackgroundEpisodeChecker: Immediate check scheduled');
  }
}
