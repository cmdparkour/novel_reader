import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsVoiceGender { male, female }

class TtsVoiceInfo {
  final String name;
  final String locale;
  final TtsVoiceGender gender;

  const TtsVoiceInfo({
    required this.name,
    required this.locale,
    required this.gender,
  });

  String get displayName {
    final genderLabel = gender == TtsVoiceGender.female ? '女声' : '男声';
    return '$genderLabel ($name)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsVoiceInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          locale == other.locale;

  @override
  int get hashCode => name.hashCode ^ locale.hashCode;
}

enum TtsPlayState { stopped, playing, paused }

class TtsService {
  final FlutterTts _tts = FlutterTts();

  TtsPlayState _state = TtsPlayState.stopped;
  TtsPlayState get state => _state;

  List<TtsVoiceInfo> _availableVoices = [];
  List<TtsVoiceInfo> get availableVoices => _availableVoices;

  TtsVoiceInfo? _currentVoice;
  TtsVoiceInfo? get currentVoice => _currentVoice;

  double _speechRate = 0.5;
  double get speechRate => _speechRate;

  // Callbacks
  VoidCallback? onStart;
  VoidCallback? onComplete;
  VoidCallback? onPause;
  VoidCallback? onCancel;
  void Function(String text, int startOffset, int endOffset, String word)?
  onProgress;
  void Function(String message)? onError;
  void Function(TtsPlayState state)? onStateChanged;

  Future<void> init() async {
    // Configure for Chinese
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Register callbacks
    _tts.setStartHandler(() {
      _updateState(TtsPlayState.playing);
      onStart?.call();
    });

    _tts.setCompletionHandler(() {
      _updateState(TtsPlayState.stopped);
      onComplete?.call();
    });

    _tts.setPauseHandler(() {
      _updateState(TtsPlayState.paused);
      onPause?.call();
    });

    _tts.setCancelHandler(() {
      _updateState(TtsPlayState.stopped);
      onCancel?.call();
    });

    _tts.setErrorHandler((message) {
      _updateState(TtsPlayState.stopped);
      onError?.call(message.toString());
    });

    _tts.setProgressHandler((
      String text,
      int startOffset,
      int endOffset,
      String word,
    ) {
      onProgress?.call(text, startOffset, endOffset, word);
    });

    // Load available Chinese voices
    await _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final List<dynamic> voices = await _tts.getVoices;
      final chineseVoices = <TtsVoiceInfo>[];

      for (final voice in voices) {
        if (voice is! Map) continue;
        final String locale = (voice['locale'] ?? '').toString();
        final String name = (voice['name'] ?? '').toString();

        if (!locale.startsWith('zh') && !locale.contains('CN')) continue;
        if (name.isEmpty) continue;

        // Determine gender from voice metadata or name heuristics
        final gender = _inferGender(voice, name);
        chineseVoices.add(
          TtsVoiceInfo(name: name, locale: locale, gender: gender),
        );
      }

      // If no Chinese voices found, create placeholder entries using
      // all available voices (some devices label them generically).
      if (chineseVoices.isEmpty) {
        chineseVoices.addAll([
          const TtsVoiceInfo(
            name: 'default-female',
            locale: 'zh-CN',
            gender: TtsVoiceGender.female,
          ),
          const TtsVoiceInfo(
            name: 'default-male',
            locale: 'zh-CN',
            gender: TtsVoiceGender.male,
          ),
        ]);
      }

      _availableVoices = chineseVoices;

      // Auto-select a female voice as default
      final femaleVoice = chineseVoices.firstWhere(
        (v) => v.gender == TtsVoiceGender.female,
        orElse: () => chineseVoices.first,
      );
      await setVoice(femaleVoice);

      debugPrint('[TTS] Loaded ${chineseVoices.length} Chinese voices');
    } catch (e) {
      debugPrint('[TTS] Error loading voices: $e');
    }
  }

  TtsVoiceGender _inferGender(Map voice, String name) {
    // Try explicit gender field (iOS/macOS/Windows)
    final gender = (voice['gender'] ?? '').toString().toLowerCase();
    if (gender.contains('female') || gender.contains('woman')) {
      return TtsVoiceGender.female;
    }
    if (gender.contains('male') || gender.contains('man')) {
      return TtsVoiceGender.male;
    }

    // Heuristics from voice name
    final lowerName = name.toLowerCase();
    if (lowerName.contains('female') ||
        lowerName.contains('woman') ||
        lowerName.contains('xiaomei') ||
        lowerName.contains('liangliang') ||
        lowerName.contains('tingting')) {
      return TtsVoiceGender.female;
    }
    if (lowerName.contains('male') ||
        lowerName.contains('xiaoyu') ||
        lowerName.contains('xiaoming')) {
      return TtsVoiceGender.male;
    }

    // Default: assign alternating genders based on hash
    return name.hashCode % 2 == 0 ? TtsVoiceGender.female : TtsVoiceGender.male;
  }

  Future<void> setVoice(TtsVoiceInfo voice) async {
    _currentVoice = voice;
    if (voice.name.startsWith('default-')) {
      // Placeholder voice — just set language and adjust pitch
      await _tts.setLanguage(voice.locale);
      await _tts.setPitch(voice.gender == TtsVoiceGender.female ? 1.2 : 0.8);
    } else {
      await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    }
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.1, 2.0);
    await _tts.setSpeechRate(_speechRate);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _tts.speak(text);
  }

  Future<void> pause() async {
    await _tts.pause();
  }

  Future<void> stop() async {
    await _tts.stop();
    _updateState(TtsPlayState.stopped);
  }

  void _updateState(TtsPlayState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  Future<void> dispose() async {
    await stop();
  }
}
