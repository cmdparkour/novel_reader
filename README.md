# 小说阅读器 (Novel Reader)

一个简洁的Flutter本地小说阅读器应用，支持导入和阅读TXT格式的小说文件。

## 功能特性

### 已实现功能

- **本地文件导入**: 支持导入TXT格式的小说文件
- **书架管理**: 
  - 网格视图展示已导入的小说
  - 显示阅读进度
  - 长按删除小说
- **小说阅读器**:
  - 流畅的阅读体验
  - 点击屏幕显示/隐藏菜单
  - 滚动阅读支持
  - 自动保存阅读进度
  - 支持文本选择和复制
- **阅读设置**:
  - 字体大小调节 (12-32)
  - 行间距调节 (1.0-3.0)
  - 屏幕亮度控制
  - 多种背景颜色主题 (护眼、白色、夜间、绿色)
  - 多种文字颜色选择 (黑色、深灰、浅灰)
  - 实时预览
- **阅读进度**:
  - 自动保存当前阅读位置
  - 进度条显示
  - 下次打开自动跳转到上次位置

## 项目结构

```
lib/
├── main.dart                          # 应用入口
├── models/                            # 数据模型
│   ├── book.dart                      # 书籍模型
│   └── reading_settings.dart          # 阅读设置模型
├── providers/                         # 状态管理
│   ├── book_provider.dart             # 书籍状态管理
│   └── settings_provider.dart         # 设置状态管理
├── services/                          # 业务服务
│   ├── book_service.dart              # 书籍服务
│   └── settings_service.dart          # 设置服务
└── pages/                             # UI页面
    ├── bookshelf_page.dart            # 书架页面
    ├── reader_page.dart               # 阅读器页面
    └── settings_page.dart             # 设置页面
```

## 技术栈

- **Flutter**: 跨平台UI框架
- **Provider**: 状态管理
- **SharedPreferences**: 本地数据持久化
- **FilePicker**: 文件选择
- **ScreenBrightness**: 屏幕亮度控制

## 安装和运行

### 环境要求

- Flutter SDK >= 3.7.2
- Dart >= 3.7.2

### 安装依赖

```bash
cd E:\project\novel_reader
flutter pub get
```

### 运行应用

```bash
# 查看可用设备
flutter devices

# 运行到指定设备
flutter run -d <device_id>

# 或直接运行（会自动选择设备）
flutter run
```

### 构建发布版本

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# iOS (需要macOS环境)
flutter build ios --release
```

## 使用说明

### 导入小说

1. 打开应用，进入书架页面
2. 点击右下角的 "+" 按钮
3. 选择要导入的TXT文件
4. 小说会自动添加到书架

### 阅读小说

1. 在书架页面点击任意小说封面
2. 进入阅读器页面
3. 点击屏幕中央显示/隐藏菜单
4. 滚动屏幕进行阅读
5. 使用底部进度条快速跳转

### 调整阅读设置

1. 在阅读器页面点击屏幕显示菜单
2. 点击右上角设置按钮
3. 根据个人喜好调整:
   - 字体大小
   - 行间距
   - 屏幕亮度
   - 背景颜色
   - 文字颜色
4. 设置会自动保存

### 删除小说

1. 在书架页面长按要删除的小说
2. 确认删除

## 数据存储

- 书籍列表和阅读进度: `SharedPreferences`
- 阅读设置: `SharedPreferences`
- 小说文件: 保持在原位置，不进行复制

## 已知限制

1. 目前仅支持TXT格式
2. 不支持章节解析（按整本显示）
3. 文件编码自动检测（依赖系统默认）
4. 大文件可能加载较慢

## 未来改进方向

- [ ] 支持更多格式 (EPUB, PDF等)
- [ ] 智能章节解析
- [ ] 书签功能
- [ ] 搜索功能
- [ ] 自定义字体
- [ ] 翻页动画
- [ ] 夜间模式自动切换
- [ ] 云同步
- [ ] 在线书源

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request！
