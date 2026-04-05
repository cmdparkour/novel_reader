import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reading_settings.dart';

class SettingsService {
  static const String _settingsKey = 'reading_settings';

  Future<ReadingSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_settingsKey);
    if (settingsJson != null) {
      final settings = ReadingSettings.fromJson(jsonDecode(settingsJson));
      return settings.copyWith(
        lineHeight: settings.lineHeight <= 1.8 ? 2.0 : settings.lineHeight,
        readingMode:
            settings.readingMode == ReadingMode.scroll
                ? ReadingMode.pageTurn
                : settings.readingMode,
        pageTurnStyle: settings.pageTurnStyle,
      );
    }
    return const ReadingSettings();
  }

  Future<void> saveSettings(ReadingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}
