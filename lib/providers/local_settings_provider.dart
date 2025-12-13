import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class LocalSettingsNotifier extends StateNotifier<Map<String, dynamic>> {
  LocalSettingsNotifier()
      : super({'allowAdult': false, 'autoRotateEnabled': true}) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allowAdult = prefs.getBool('allowAdult') ?? false;
      final autoRotateEnabled = prefs.getBool('autoRotateEnabled') ?? true;

      state = {
        'allowAdult': allowAdult,
        'autoRotateEnabled': autoRotateEnabled,
      };

      debugPrint('Local settings loaded: allowAdult=$allowAdult');
    } catch (e) {
      debugPrint('Failed to load local settings: $e');
    }
  }

  Future<void> updateSetting(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      }

      state = {...state, key: value};
      debugPrint('Local setting updated: $key=$value');
    } catch (e) {
      debugPrint('Failed to update setting: $e');
    }
  }
}

final localSettingsProvider =
    StateNotifierProvider<LocalSettingsNotifier, Map<String, dynamic>>(
  (ref) => LocalSettingsNotifier(),
);
