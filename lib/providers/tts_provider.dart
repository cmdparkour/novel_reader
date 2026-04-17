import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/tts_service.dart';

class TtsProvider with ChangeNotifier {
  final TtsService _ttsService = TtsService();
  static const MethodChannel _keepAliveChannel = MethodChannel(
    'novel_reader/tts_keep_alive',
  );
  bool _initialized = false;

  // State
  TtsPlayState _playState = TtsPlayState.stopped;
  int _highlightStart = -1;
  int _highlightEnd = -1;
  String _currentWord = '';

  // The text currently being spoken (full chapter text)
  String _speakingText = '';
  // Character offset within _speakingText where we last finished
  int _speakingOffset = 0;

  // Getters
  TtsPlayState get playState => _playState;
  bool get isPlaying => _playState == TtsPlayState.playing;
  bool get isPaused => _playState == TtsPlayState.paused;
  bool get isStopped => _playState == TtsPlayState.stopped;
  int get highlightStart => _highlightStart;
  int get highlightEnd => _highlightEnd;
  String get currentWord => _currentWord;
  List<TtsVoiceInfo> get availableVoices => _ttsService.availableVoices;
  TtsVoiceInfo? get currentVoice => _ttsService.currentVoice;
  double get speechRate => _ttsService.speechRate;

  /// The character offset within the full chapter text that TTS is currently
  /// reading from. Updated on each chunk advance and on progress callbacks.
  int get speakingOffset => _speakingOffset;

  /// Length of the full text being spoken.
  int get speakingTextLength => _speakingText.length;

  // Callback: invoked when TTS finishes the entire chapter text
  VoidCallback? onChapterComplete;

  Future<void> _setWakeLock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('[TTS] wakelock error: $e');
    }
  }

  Future<void> _setForegroundKeepAlive(bool enabled) async {
    try {
      await _keepAliveChannel.invokeMethod(enabled ? 'start' : 'stop');
    } catch (e) {
      debugPrint('[TTS] foreground service error: $e');
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _ttsService.onStateChanged = (state) {
      _playState = state;
      if (state == TtsPlayState.stopped) {
        _highlightStart = -1;
        _highlightEnd = -1;
        _currentWord = '';
      }
      notifyListeners();
    };

    _ttsService.onProgress = (text, startOffset, endOffset, word) {
      _highlightStart = _speakingOffset + startOffset;
      _highlightEnd = _speakingOffset + endOffset;
      _currentWord = word;
      debugPrint(
        '[TTS] progress: highlight=$_highlightStart-$_highlightEnd word="$word"',
      );
      notifyListeners();
    };

    _ttsService.onComplete = () {
      // flutter_tts has a character limit per speak() call on some platforms.
      // If we split text into chunks, continue with the next chunk.
      final chunkSize = _getChunkSize();
      if (_speakingText.isNotEmpty &&
          _speakingOffset + chunkSize < _speakingText.length) {
        _speakingOffset += chunkSize;
        // Update highlight to the start of the new chunk so reader_page
        // can sync page position even when progress handler doesn't fire.
        _highlightStart = _speakingOffset;
        _highlightEnd = _speakingOffset;
        debugPrint(
          '[TTS] chunk done, advancing to offset=$_speakingOffset / ${_speakingText.length}',
        );
        notifyListeners();
        _speakNextChunk();
      } else {
        debugPrint('[TTS] chapter complete');
        _setWakeLock(false);
        _speakingText = '';
        _speakingOffset = 0;
        _highlightStart = -1;
        _highlightEnd = -1;
        _currentWord = '';
        notifyListeners();
        onChapterComplete?.call();
      }
    };

    await _ttsService.init();
    notifyListeners();
  }

  /// Maximum characters per speak() call.
  /// Android TTS engine may silently truncate at ~4000 chars.
  static const int _maxChunkSize = 3000;

  int _getChunkSize() {
    final remaining = _speakingText.length - _speakingOffset;
    if (remaining <= _maxChunkSize) return remaining;
    // Try to break at a sentence boundary
    final chunk = _speakingText.substring(
      _speakingOffset,
      _speakingOffset + _maxChunkSize,
    );
    final lastSentenceEnd = _findLastSentenceEnd(chunk);
    return lastSentenceEnd > 0 ? lastSentenceEnd : _maxChunkSize;
  }

  int _findLastSentenceEnd(String text) {
    // Look for Chinese/English sentence terminators
    for (int i = text.length - 1; i >= text.length ~/ 2; i--) {
      final c = text[i];
      if (c == '。' || c == '！' || c == '？' || c == '.' || c == '\n') {
        return i + 1;
      }
    }
    return -1;
  }

  void _speakNextChunk() {
    final chunkSize = _getChunkSize();
    final chunk = _speakingText.substring(
      _speakingOffset,
      _speakingOffset + chunkSize,
    );
    _ttsService.speak(chunk);
  }

  /// Start speaking the given text from the beginning.
  Future<void> speak(String text) async {
    if (!_initialized) await init();
    if (text.isEmpty) return;

    _speakingText = text;
    _speakingOffset = 0;
    await _setWakeLock(true);
    await _setForegroundKeepAlive(true);
    _speakNextChunk();
  }

  /// Start speaking from a specific character offset within the chapter.
  Future<void> speakFrom(String fullText, int offset) async {
    if (!_initialized) await init();
    if (fullText.isEmpty) return;

    _speakingText = fullText;
    _speakingOffset = offset.clamp(0, fullText.length);
    await _setWakeLock(true);
    await _setForegroundKeepAlive(true);
    _speakNextChunk();
  }

  Future<void> pause() async {
    await _ttsService.pause();
    await _setWakeLock(false);
    await _setForegroundKeepAlive(false);
  }

  Future<void> resume() async {
    // flutter_tts doesn't have a resume — re-speak from last known offset
    if (_speakingText.isNotEmpty) {
      _speakNextChunk();
    }
  }

  Future<void> stop() async {
    _speakingText = '';
    _speakingOffset = 0;
    await _setWakeLock(false);
    await _setForegroundKeepAlive(false);
    await _ttsService.stop();
  }

  Future<void> togglePlayPause(String text) async {
    if (isPlaying) {
      await pause();
    } else if (isPaused || isStopped) {
      if (isStopped) {
        await speak(text);
      } else {
        await resume();
      }
    }
  }

  Future<void> setVoice(TtsVoiceInfo voice) async {
    final wasPlaying = isPlaying;
    if (wasPlaying) await pause();
    await _ttsService.setVoice(voice);
    notifyListeners();
    // If was playing, restart from current position
    if (wasPlaying && _speakingText.isNotEmpty) {
      _speakNextChunk();
    }
  }

  Future<void> setSpeechRate(double rate) async {
    await _ttsService.setSpeechRate(rate);
    notifyListeners();
  }

  /// Get voices grouped by gender for UI
  List<TtsVoiceInfo> get femaleVoices =>
      _ttsService.availableVoices
          .where((v) => v.gender == TtsVoiceGender.female)
          .toList();

  List<TtsVoiceInfo> get maleVoices =>
      _ttsService.availableVoices
          .where((v) => v.gender == TtsVoiceGender.male)
          .toList();

  Future<void> dispose() async {
    await _setWakeLock(false);
    await _setForegroundKeepAlive(false);
    await _ttsService.dispose();
    super.dispose();
  }
}
