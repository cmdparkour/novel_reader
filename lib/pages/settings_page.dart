import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reading_settings.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Reading mode
          const Text(
            '阅读模式',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ReadingMode>(
            segments: const [
              ButtonSegment(
                value: ReadingMode.scroll,
                label: Text('滚动'),
                icon: Icon(Icons.swap_vert),
              ),
              ButtonSegment(
                value: ReadingMode.pageTurn,
                label: Text('翻页'),
                icon: Icon(Icons.auto_stories),
              ),
            ],
            selected: {settings.readingMode},
            onSelectionChanged: (modes) {
              settingsProvider.updateReadingMode(modes.first);
            },
          ),
          const SizedBox(height: 16),
          const Text(
            '翻页样式',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PageTurnStyle>(
            segments: const [
              ButtonSegment(
                value: PageTurnStyle.simple,
                label: Text('简洁'),
                icon: Icon(Icons.swipe),
              ),
              ButtonSegment(
                value: PageTurnStyle.realistic,
                label: Text('仿真翻页'),
                icon: Icon(Icons.menu_book_rounded),
              ),
            ],
            selected: {settings.pageTurnStyle},
            onSelectionChanged: (styles) {
              settingsProvider.updatePageTurnStyle(styles.first);
            },
          ),
          const SizedBox(height: 24),

          // Theme mode
          const Text(
            '主题模式',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(
                value: AppThemeMode.light,
                label: Text('浅色'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                label: Text('深色'),
                icon: Icon(Icons.dark_mode),
              ),
              ButtonSegment(
                value: AppThemeMode.system,
                label: Text('跟随系统'),
                icon: Icon(Icons.settings_suggest),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (modes) {
              final mode = modes.first;
              settingsProvider.updateThemeMode(mode);
              // Auto-adjust colors when explicitly choosing dark
              if (mode == AppThemeMode.dark) {
                settingsProvider.updateBackgroundColor(0xFF2E2E2E);
                settingsProvider.updateTextColor(0xFFE0E0E0);
              } else if (mode == AppThemeMode.light) {
                settingsProvider.updateBackgroundColor(0xFFF5F5DC);
                settingsProvider.updateTextColor(0xFF000000);
              }
            },
          ),
          const SizedBox(height: 24),

          // Font size
          const Text(
            '字体大小',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${settings.fontSize.round()}'),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12,
                  max: 32,
                  divisions: 20,
                  label: settings.fontSize.round().toString(),
                  onChanged: (value) {
                    settingsProvider.updateFontSize(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Line height
          const Text(
            '行间距',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(settings.lineHeight.toStringAsFixed(1)),
              Expanded(
                child: Slider(
                  value: settings.lineHeight,
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  label: settings.lineHeight.toStringAsFixed(1),
                  onChanged: (value) {
                    settingsProvider.updateLineHeight(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Screen brightness
          const Text(
            '屏幕亮度',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${(settings.screenBrightness * 100).round()}%'),
              Expanded(
                child: Slider(
                  value: settings.screenBrightness,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  label: '${(settings.screenBrightness * 100).round()}%',
                  onChanged: (value) {
                    settingsProvider.updateBrightness(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Background color (only show when not in system/dark theme mode)
          if (settings.themeMode == AppThemeMode.light) ...[
            const Text(
              '背景颜色',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ColorOption(
                  color: const Color(0xFFF5F5DC),
                  label: '护眼',
                  isSelected: settings.backgroundColor == 0xFFF5F5DC,
                  onTap:
                      () => settingsProvider.updateBackgroundColor(0xFFF5F5DC),
                ),
                _ColorOption(
                  color: const Color(0xFFFFFFFF),
                  label: '白色',
                  isSelected: settings.backgroundColor == 0xFFFFFFFF,
                  onTap:
                      () => settingsProvider.updateBackgroundColor(0xFFFFFFFF),
                ),
                _ColorOption(
                  color: const Color(0xFFE8F5E9),
                  label: '绿色',
                  isSelected: settings.backgroundColor == 0xFFE8F5E9,
                  onTap:
                      () => settingsProvider.updateBackgroundColor(0xFFE8F5E9),
                ),
                _ColorOption(
                  color: const Color(0xFFFFF3E0),
                  label: '暖黄',
                  isSelected: settings.backgroundColor == 0xFFFFF3E0,
                  onTap:
                      () => settingsProvider.updateBackgroundColor(0xFFFFF3E0),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Text color
            const Text(
              '文字颜色',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ColorOption(
                  color: const Color(0xFF000000),
                  label: '黑色',
                  isSelected: settings.textColor == 0xFF000000,
                  onTap: () => settingsProvider.updateTextColor(0xFF000000),
                ),
                _ColorOption(
                  color: const Color(0xFF424242),
                  label: '深灰',
                  isSelected: settings.textColor == 0xFF424242,
                  onTap: () => settingsProvider.updateTextColor(0xFF424242),
                ),
                _ColorOption(
                  color: const Color(0xFF795548),
                  label: '棕色',
                  isSelected: settings.textColor == 0xFF795548,
                  onTap: () => settingsProvider.updateTextColor(0xFF795548),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Preview
          const Text(
            '预览',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(settings.backgroundColor),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              '这是阅读预览文字。The quick brown fox jumps over the lazy dog.\n\n'
              '当前模式：${settings.readingMode == ReadingMode.scroll ? "滚动" : "翻页"} | '
              '主题：${_themeModeName(settings.themeMode)}',
              style: TextStyle(
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                color: Color(settings.textColor),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _themeModeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }
}

class _ColorOption extends StatelessWidget {
  final Color color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorOption({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[400]!),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
