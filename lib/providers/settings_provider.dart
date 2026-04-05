import 'package:flutter/material.dart';
import '../models/reading_settings.dart';
import '../services/settings_service.dart';
import 'package:screen_brightness/screen_brightness.dart';

class SettingsProvider with ChangeNotifier {
  final SettingsService _settingsService = SettingsService();
  ReadingSettings _settings = const ReadingSettings();

  ReadingSettings get settings => _settings;

  Future<void> loadSettings() async {
    try {
      _settings = await _settingsService.getSettings();
      await _applyBrightness();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> updateFontSize(double fontSize) async {
    _settings = _settings.copyWith(fontSize: fontSize);
    await _saveSettings();
  }

  Future<void> updateLineHeight(double lineHeight) async {
    _settings = _settings.copyWith(lineHeight: lineHeight);
    await _saveSettings();
  }

  Future<void> updateBackgroundColor(int color) async {
    _settings = _settings.copyWith(backgroundColor: color);
    await _saveSettings();
  }

  Future<void> updateTextColor(int color) async {
    _settings = _settings.copyWith(textColor: color);
    await _saveSettings();
  }

  Future<void> updateBrightness(double brightness) async {
    _settings = _settings.copyWith(screenBrightness: brightness);
    await _applyBrightness();
    await _saveSettings();
  }

  Future<void> updateReadingMode(ReadingMode mode) async {
    _settings = _settings.copyWith(readingMode: mode);
    await _saveSettings();
  }

  Future<void> updatePageTurnStyle(PageTurnStyle style) async {
    _settings = _settings.copyWith(pageTurnStyle: style);
    await _saveSettings();
  }

  Future<void> updateThemeMode(AppThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _saveSettings();
  }

  /// Get effective settings considering system dark mode
  ReadingSettings effectiveSettings(bool isSystemDark) {
    return _settings.effectiveSettings(isSystemDark);
  }

  Future<void> _saveSettings() async {
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> _applyBrightness() async {
    try {
      await ScreenBrightness().setScreenBrightness(_settings.screenBrightness);
    } catch (e) {
      debugPrint('Error setting brightness: $e');
    }
  }

  Future<void> resetBrightness() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
    } catch (e) {
      debugPrint('Error resetting brightness: $e');
    }
  }
}
