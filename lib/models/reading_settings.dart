enum ReadingMode { scroll, pageTurn }

enum AppThemeMode { light, dark, system }

enum PageTurnStyle { simple, realistic }

class ReadingSettings {
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final int backgroundColor;
  final int textColor;
  final double screenBrightness;
  final ReadingMode readingMode;
  final AppThemeMode themeMode;
  final PageTurnStyle pageTurnStyle;

  const ReadingSettings({
    this.fontSize = 24.0,
    this.lineHeight = 2.4,
    this.fontFamily = 'System',
    this.backgroundColor = 0xFFF5F5DC, // Beige
    this.textColor = 0xFF000000, // Black
    this.screenBrightness = 0.5,
    this.readingMode = ReadingMode.pageTurn,
    this.themeMode = AppThemeMode.light,
    this.pageTurnStyle = PageTurnStyle.simple,
  });

  ReadingSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    int? backgroundColor,
    int? textColor,
    double? screenBrightness,
    ReadingMode? readingMode,
    AppThemeMode? themeMode,
    PageTurnStyle? pageTurnStyle,
  }) {
    return ReadingSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      screenBrightness: screenBrightness ?? this.screenBrightness,
      readingMode: readingMode ?? this.readingMode,
      themeMode: themeMode ?? this.themeMode,
      pageTurnStyle: pageTurnStyle ?? this.pageTurnStyle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'screenBrightness': screenBrightness,
      'readingMode': readingMode.index,
      'themeMode': themeMode.index,
      'pageTurnStyle': pageTurnStyle.index,
    };
  }

  factory ReadingSettings.fromJson(Map<String, dynamic> json) {
    return ReadingSettings(
      fontSize: json['fontSize']?.toDouble() ?? 24.0,
      lineHeight: json['lineHeight']?.toDouble() ?? 2.4,
      fontFamily: json['fontFamily'] ?? 'System',
      backgroundColor: json['backgroundColor'] ?? 0xFFF5F5DC,
      textColor: json['textColor'] ?? 0xFF000000,
      screenBrightness: json['screenBrightness']?.toDouble() ?? 0.5,
      readingMode:
          ReadingMode.values.elementAtOrNull(json['readingMode'] ?? 1) ??
          ReadingMode.pageTurn,
      themeMode:
          AppThemeMode.values.elementAtOrNull(json['themeMode'] ?? 0) ??
          AppThemeMode.light,
      pageTurnStyle:
          PageTurnStyle.values.elementAtOrNull(json['pageTurnStyle'] ?? 0) ??
          PageTurnStyle.simple,
    );
  }

  /// Returns effective background and text colors considering theme mode and system brightness.
  /// [platformBrightness] should come from MediaQuery.platformBrightnessOf(context).
  ReadingSettings effectiveSettings(bool isSystemDark) {
    if (themeMode == AppThemeMode.system && isSystemDark) {
      return copyWith(backgroundColor: 0xFF2E2E2E, textColor: 0xFFE0E0E0);
    }
    return this;
  }
}

extension _SafeElementAt<T> on List<T> {
  T? elementAtOrNull(int index) {
    if (index >= 0 && index < length) return this[index];
    return null;
  }
}
