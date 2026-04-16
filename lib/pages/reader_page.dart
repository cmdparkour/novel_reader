import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/reading_settings.dart';
import '../providers/book_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tts_provider.dart';
import '../services/book_service.dart';
import '../services/chapter_parser.dart';
import '../services/tts_service.dart';
import 'chapter_list_page.dart';
import 'settings_page.dart';

class ReaderPage extends StatefulWidget {
  final Book book;

  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final BookService _bookService = BookService();
  final ScrollController _scrollController = ScrollController();
  PageController _pageController = PageController(keepPage: false);

  /// Full content of the book (kept in memory for chapter slicing).
  String _fullContent = '';

  /// Content of the current chapter only.
  String _chapterContent = '';

  List<Chapter> _chapters = [];
  int _currentChapterIndex = 0;
  bool _isLoading = true;
  bool _showMenu = false;

  // Page turn mode state
  List<String> _pages = [];
  int _currentPageIndex = 0;
  Size _lastLayoutSize = Size.zero;
  _ReaderWindow? _window;
  int _windowGeneration = 0;
  bool _isShifting = false;
  int _shiftToken = 0;

  // Scroll mode chapter switching state
  String? _scrollChapterHint;
  int? _scrollPendingChapterIndex;
  bool _isScrollChapterSwitching = false;

  int? _deferredPageTurnPosition;

  bool _showTtsPanel = false;

  /// When true, TTS auto-page-turn / auto-scroll is suppressed so the user
  /// can freely swipe or scroll without TTS fighting for control.
  bool _userIsInteracting = false;
  int _userInteractionToken = 0;

  /// Timer-based fallback to estimate TTS reading position and trigger
  /// page flips even when the progress handler doesn't fire.
  Timer? _ttsEstimateTimer;
  int _ttsEstimateOffset = 0;
  DateTime? _ttsChunkStartTime;

  bool get _hasPreviousChapter => _currentChapterIndex > 0;

  bool get _hasNextChapter => _currentChapterIndex < _chapters.length - 1;

  List<String> _paginateContent(String content, Size pageSize) {
    if (content.isEmpty || pageSize == Size.zero) {
      return const [];
    }

    final settings = context.read<SettingsProvider>().settings;
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineHeight,
    );
    // Available width/height inside page padding (left/right 16, top 16, bottom 0)
    final availableWidth = pageSize.width - 32;
    final availableHeight = pageSize.height - 16;

    // Layout entire content to get line metrics
    final tp = TextPainter(
      text: TextSpan(text: content, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: availableWidth);

    final lineMetrics = tp.computeLineMetrics();
    if (lineMetrics.isEmpty) return [content];

    // Calculate how many complete lines fit per page
    final lineHeight = lineMetrics.first.height;
    final linesPerPage = (availableHeight / lineHeight).floor();
    if (linesPerPage <= 0) return [content];

    // Split content by line boundaries
    final pages = <String>[];
    int lineIndex = 0;
    while (lineIndex < lineMetrics.length) {
      final pageEndLine = (lineIndex + linesPerPage).clamp(
        0,
        lineMetrics.length,
      );

      // Get character offset for the start of the first line on this page
      final startOffset =
          tp
              .getPositionForOffset(
                Offset(
                  0,
                  lineMetrics[lineIndex].baseline -
                      lineMetrics[lineIndex].ascent,
                ),
              )
              .offset;

      // Get character offset for the end of the last line on this page
      int endOffset;
      if (pageEndLine >= lineMetrics.length) {
        endOffset = content.length;
      } else {
        endOffset =
            tp
                .getPositionForOffset(
                  Offset(
                    0,
                    lineMetrics[pageEndLine].baseline -
                        lineMetrics[pageEndLine].ascent,
                  ),
                )
                .offset;
      }

      if (endOffset <= startOffset) {
        // Safety: ensure at least some progress
        endOffset = (startOffset + 1).clamp(0, content.length);
        lineIndex = pageEndLine + 1;
      } else {
        lineIndex = pageEndLine;
      }

      pages.add(content.substring(startOffset, endOffset));
    }
    return pages;
  }

  int _pageOffsetForIndex(int pageIndex) {
    return _pageOffsetForPages(_pages, pageIndex);
  }

  int _pageOffsetForPages(List<String> pages, int pageIndex) {
    int charCount = 0;
    for (int i = 0; i < pageIndex && i < pages.length; i++) {
      charCount += pages[i].length;
    }
    return charCount;
  }

  String _cleanChapterContent(String rawContent) {
    // Normalize line endings: strip all \r so only \n remains.
    final normalized = rawContent.replaceAll('\r', '');
    // Strip leading blank lines (e.g. \n before the heading).
    final trimmed = normalized.replaceFirst(RegExp(r'^\n+'), '');
    // Collapse blank lines between the chapter heading and the first
    // paragraph into a single newline so there is no visual gap.
    return trimmed.replaceFirstMapped(
      RegExp(r'^([^\n]*)\n(?:\s*\n)+'),
      (match) => '${match[1]}\n',
    );
  }

  String _chapterContentForIndex(int chapterIndex) {
    final chapter = _chapters[chapterIndex];
    final rawContent = _fullContent.substring(
      chapter.startPosition,
      chapter.endPosition,
    );
    return _cleanChapterContent(rawContent);
  }

  _ChapterPages _buildChapterPages(int chapterIndex) {
    final cleanedContent = _chapterContentForIndex(chapterIndex);
    return _ChapterPages(
      chapterIndex: chapterIndex,
      pages: _paginateContent(cleanedContent, _lastLayoutSize),
      cleanedContent: cleanedContent,
    );
  }

  _ReaderWindow _buildWindow(int centerChapter) {
    return _ReaderWindow(
      prev: centerChapter > 0 ? _buildChapterPages(centerChapter - 1) : null,
      current: _buildChapterPages(centerChapter),
      next:
          centerChapter < _chapters.length - 1
              ? _buildChapterPages(centerChapter + 1)
              : null,
      currentTitle: _chapters[centerChapter].title,
    );
  }

  int _chapterIndexForPosition(int position) {
    if (_chapters.isEmpty) return 0;
    if (position <= 0) return 0;

    for (int i = 0; i < _chapters.length; i++) {
      if (position >= _chapters[i].startPosition &&
          position < _chapters[i].endPosition) {
        return i;
      }
    }

    return _chapters.length - 1;
  }

  int _pageIndexForCharOffset(List<String> pages, int charOffset) {
    if (pages.isEmpty) return 0;

    final totalLength = pages.fold<int>(0, (sum, page) => sum + page.length);
    final safeOffset = charOffset.clamp(0, totalLength);

    int accumulated = 0;
    for (int i = 0; i < pages.length; i++) {
      final nextAccumulated = accumulated + pages[i].length;
      if (safeOffset < nextAccumulated || i == pages.length - 1) {
        return i;
      }
      accumulated = nextAccumulated;
    }

    return pages.length - 1;
  }

  int _currentGlobalPosition() {
    if (_chapters.isEmpty) return 0;

    final settings = context.read<SettingsProvider>().settings;
    if (settings.readingMode == ReadingMode.pageTurn) {
      return _chapters[_currentChapterIndex].startPosition +
          _pageOffsetForIndex(_currentPageIndex);
    }

    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0) {
      final scrollFraction =
          _scrollController.offset / _scrollController.position.maxScrollExtent;
      final chapterOffset = (scrollFraction * _chapterContent.length).round();
      return _chapters[_currentChapterIndex].startPosition + chapterOffset;
    }

    return _chapters[_currentChapterIndex].startPosition;
  }

  void _applyPageTurnWindow(
    _ReaderWindow window, {
    required int pageInChapter,
    bool hideMenu = false,
    bool shifting = false,
  }) {
    final safePageInChapter =
        window.current.pages.isEmpty
            ? 0
            : pageInChapter.clamp(0, window.current.pages.length - 1);
    final initialPage = window.flattenedIndexFor(
      window.current.chapterIndex,
      safePageInChapter,
    );
    final oldController = _pageController;
    final newController = PageController(
      initialPage: initialPage,
      keepPage: false,
    );
    final shiftToken = shifting ? ++_shiftToken : _shiftToken;

    setState(() {
      _window = window;
      _windowGeneration++;
      _pageController = newController;
      _currentChapterIndex = window.current.chapterIndex;
      _chapterContent = window.current.cleanedContent;
      _pages = window.current.pages;
      _currentPageIndex = safePageInChapter;
      _deferredPageTurnPosition = null;
      if (hideMenu) {
        _showMenu = false;
      }
      if (shifting) {
        _isShifting = true;
      }
    });

    final globalPosition =
        _chapters[window.current.chapterIndex].startPosition +
        _pageOffsetForPages(window.current.pages, safePageInChapter);
    _saveProgress(position: globalPosition);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
      if (shifting && mounted && _shiftToken == shiftToken) {
        setState(() {
          _isShifting = false;
        });
      }
    });
  }

  void _rebuildWindowForGlobalPosition(
    int globalPosition, {
    bool hideMenu = false,
  }) {
    if (_chapters.isEmpty) return;

    final chapterIndex = _chapterIndexForPosition(globalPosition);
    final chapter = _chapters[chapterIndex];
    final chapterContent = _chapterContentForIndex(chapterIndex);
    final charOffset = (globalPosition - chapter.startPosition).clamp(
      0,
      chapterContent.length,
    );

    if (_lastLayoutSize == Size.zero) {
      setState(() {
        _currentChapterIndex = chapterIndex;
        _chapterContent = chapterContent;
        _pages = const [];
        _currentPageIndex = 0;
        _window = null;
        _deferredPageTurnPosition = globalPosition;
        if (hideMenu) {
          _showMenu = false;
        }
      });
      return;
    }

    final window = _buildWindow(chapterIndex);
    final pageInChapter = _pageIndexForCharOffset(
      window.current.pages,
      charOffset,
    );
    _applyPageTurnWindow(
      window,
      pageInChapter: pageInChapter,
      hideMenu: hideMenu,
    );
  }

  void _shiftWindow(int chapterIndex, int pageInChapter) {
    if (_isShifting ||
        chapterIndex < 0 ||
        chapterIndex >= _chapters.length ||
        _lastLayoutSize == Size.zero) {
      return;
    }

    final window = _buildWindow(chapterIndex);
    _applyPageTurnWindow(window, pageInChapter: pageInChapter, shifting: true);
  }

  void _loadChapterForScrollMode(
    int chapterIndex, {
    bool hideMenu = false,
    int? progressPosition,
  }) {
    if (_chapters.isEmpty ||
        chapterIndex < 0 ||
        chapterIndex >= _chapters.length ||
        _isScrollChapterSwitching) {
      return;
    }

    final chapterContent = _chapterContentForIndex(chapterIndex);

    setState(() {
      _isScrollChapterSwitching = true;
      _currentChapterIndex = chapterIndex;
      _chapterContent = chapterContent;
      _pages = const [];
      _currentPageIndex = 0;
      _scrollChapterHint = null;
      _scrollPendingChapterIndex = null;
      _deferredPageTurnPosition =
          progressPosition ?? _chapters[chapterIndex].startPosition;
      if (hideMenu) {
        _showMenu = false;
      }
    });

    _saveProgress(
      position: progressPosition ?? _chapters[chapterIndex].startPosition,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      setState(() {
        _isScrollChapterSwitching = false;
      });
    });
  }

  void _setScrollChapterHint(String hint, int chapterIndex) {
    if (_scrollChapterHint == hint &&
        _scrollPendingChapterIndex == chapterIndex) {
      return;
    }

    setState(() {
      _scrollChapterHint = hint;
      _scrollPendingChapterIndex = chapterIndex;
    });
  }

  void _clearScrollChapterHint() {
    if (_scrollChapterHint == null && _scrollPendingChapterIndex == null) {
      return;
    }

    setState(() {
      _scrollChapterHint = null;
      _scrollPendingChapterIndex = null;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isScrollChapterSwitching || _chapters.isEmpty) {
      return false;
    }

    if (notification is OverscrollNotification) {
      final atTop =
          notification.overscroll < 0 &&
          notification.metrics.pixels <= notification.metrics.minScrollExtent;
      final atBottom =
          notification.overscroll > 0 &&
          notification.metrics.pixels >= notification.metrics.maxScrollExtent;

      if (atTop && _hasPreviousChapter) {
        _setScrollChapterHint('释放进入上一章', _currentChapterIndex - 1);
      } else if (atBottom && _hasNextChapter) {
        _setScrollChapterHint('释放进入下一章', _currentChapterIndex + 1);
      }
    } else if (notification is ScrollUpdateNotification) {
      final atBoundary =
          notification.metrics.pixels <= notification.metrics.minScrollExtent ||
          notification.metrics.pixels >= notification.metrics.maxScrollExtent;
      if (!atBoundary) {
        _clearScrollChapterHint();
      }
    } else if (notification is ScrollEndNotification) {
      final pendingChapterIndex = _scrollPendingChapterIndex;
      _clearScrollChapterHint();
      if (pendingChapterIndex != null) {
        _loadChapterForScrollMode(pendingChapterIndex);
      }
    }

    return false;
  }

  /// Track TTS highlight changes to auto-flip pages / auto-scroll.
  int _lastTtsHighlightStart = -1;
  bool _wasTtsPlaying = false;

  void _onTtsProgressChanged() {
    if (!mounted) return;
    final tts = context.read<TtsProvider>();

    // Detect play/stop transitions to manage the estimate timer.
    if (tts.isPlaying && !_wasTtsPlaying) {
      _wasTtsPlaying = true;
      _startTtsEstimateTimer(tts);
    } else if (!tts.isPlaying && _wasTtsPlaying) {
      _wasTtsPlaying = false;
      _stopTtsEstimateTimer();
      _ttsLastFlippedToPage = -1;
    }

    if (!tts.isPlaying || _userIsInteracting) return;

    // Use highlightStart if available (progress handler fired),
    // otherwise fall back to speakingOffset (chunk-boundary based).
    int charPos = tts.highlightStart;
    if (charPos < 0) {
      charPos = tts.speakingOffset;
    }
    if (charPos < 0 || charPos == _lastTtsHighlightStart) return;
    _lastTtsHighlightStart = charPos;

    // Reset estimate timer anchor whenever we get a real position update
    _ttsEstimateOffset = charPos;
    _ttsChunkStartTime = DateTime.now();

    final settings = context.read<SettingsProvider>().settings;
    if (settings.readingMode == ReadingMode.pageTurn) {
      _syncTtsPageTurn(charPos);
    } else {
      _syncTtsScroll(charPos);
    }
  }

  /// Start a periodic timer that estimates TTS reading position based on
  /// speech rate and elapsed time. Chinese TTS reads ~4-5 chars/sec at
  /// rate 0.5, scaling linearly with speech rate.
  void _startTtsEstimateTimer(TtsProvider tts) {
    _stopTtsEstimateTimer();
    _ttsEstimateOffset = tts.speakingOffset;
    _ttsChunkStartTime = DateTime.now();
    _ttsEstimateTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _onTtsEstimateTick(),
    );
  }

  void _stopTtsEstimateTimer() {
    _ttsEstimateTimer?.cancel();
    _ttsEstimateTimer = null;
  }

  void _onTtsEstimateTick() {
    if (!mounted || _userIsInteracting) return;
    final tts = context.read<TtsProvider>();
    if (!tts.isPlaying) {
      _stopTtsEstimateTimer();
      return;
    }

    if (_ttsChunkStartTime == null) return;

    // Estimate: Chinese TTS speaks ~4 chars/sec at rate 0.5.
    // Scale linearly: rate 1.0 → ~8 chars/sec.
    final charsPerSec = tts.speechRate * 8.0;
    final elapsed =
        DateTime.now().difference(_ttsChunkStartTime!).inMilliseconds / 1000.0;
    final estimatedPos = _ttsEstimateOffset + (charsPerSec * elapsed).round();
    final clampedPos = estimatedPos.clamp(0, _chapterContent.length);

    if (clampedPos == _lastTtsHighlightStart) return;
    _lastTtsHighlightStart = clampedPos;

    final settings = context.read<SettingsProvider>().settings;
    if (settings.readingMode == ReadingMode.pageTurn) {
      _syncTtsPageTurn(clampedPos);
    } else {
      _syncTtsScroll(clampedPos);
    }
  }

  /// Page-turn mode: flip to the page that contains [charPos].
  /// We flip slightly early (when ~60% through the current page) so
  /// the visual page turn happens before the TTS finishes reading the
  /// last words on the current page.
  ///
  /// To prevent oscillation (flip forward → charPos still on old page →
  /// flip back → repeat), we track the last page we flipped TO and never
  /// go backward from a TTS-driven flip.
  int _ttsLastFlippedToPage = -1;

  void _syncTtsPageTurn(int charPos) {
    if (_pages.isEmpty || _isShifting) return;

    // The "natural" page for this charPos (where the char actually lives).
    final naturalPage = _pageIndexForCharOffset(_pages, charPos);

    // Calculate how far into the natural page we are
    final naturalPageStart = _pageOffsetForPages(_pages, naturalPage);
    final naturalPageLen = _pages[naturalPage].length;
    final posInPage = charPos - naturalPageStart;

    // Decide target: flip to next page early when past 60% of the
    // natural page, otherwise stay on the natural page.
    int targetPage = naturalPage;
    if (naturalPageLen > 0 &&
        posInPage > naturalPageLen * 0.6 &&
        naturalPage < _pages.length - 1) {
      targetPage = naturalPage + 1;
    }

    // Never go backward from a TTS-driven flip. This prevents
    // oscillation when the early-flip fires but charPos hasn't
    // actually entered the new page's range yet.
    if (_ttsLastFlippedToPage >= 0 && targetPage < _ttsLastFlippedToPage) {
      // charPos hasn't caught up yet — stay on the page we flipped to.
      targetPage = _ttsLastFlippedToPage;
    }

    // Reset the latch once charPos naturally reaches/passes the flipped page.
    if (naturalPage >= _ttsLastFlippedToPage) {
      _ttsLastFlippedToPage = -1;
    }

    if (targetPage != _currentPageIndex) {
      _ttsLastFlippedToPage = targetPage;
      final window = _window;
      if (window == null) return;
      final flatIndex = window.flattenedIndexFor(
        _currentChapterIndex,
        targetPage,
      );
      _pageController.animateToPage(
        flatIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Scroll mode: scroll so the current reading position is visible.
  void _syncTtsScroll(int charPos) {
    if (!_scrollController.hasClients || _chapterContent.isEmpty) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final fraction = charPos / _chapterContent.length;
    final targetOffset = (fraction * maxScroll).clamp(0.0, maxScroll);
    // Only scroll if more than 5% away to avoid jitter
    final currentFraction = _scrollController.offset / maxScroll;
    if ((fraction - currentFraction).abs() > 0.03) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Mark that the user is manually interacting (swiping / scrolling).
  /// TTS auto-sync is suppressed until the interaction ends.
  void _onUserInteractionStart() {
    _userIsInteracting = true;
    _userInteractionToken++;
    _ttsLastFlippedToPage = -1;
  }

  /// After the user lifts their finger, wait a short grace period before
  /// re-enabling TTS auto-sync so that fling animations can settle.
  void _onUserInteractionEnd() {
    final token = ++_userInteractionToken;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _userInteractionToken == token) {
        _userIsInteracting = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadContent();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tts = context.read<TtsProvider>();

      // Listen for TTS progress to auto-flip pages / auto-scroll
      tts.addListener(_onTtsProgressChanged);

      // When TTS finishes reading the current chapter, auto-advance
      tts.onChapterComplete = () {
        if (!mounted) return;
        if (_hasNextChapter) {
          final nextIndex = _currentChapterIndex + 1;
          _jumpToChapter(nextIndex);
          // Start reading the next chapter after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            final nextContent = _chapterContentForIndex(_currentChapterIndex);
            context.read<TtsProvider>().speakFrom(nextContent, 0);
          });
        }
      };
    });
  }

  @override
  void dispose() {
    _saveProgress();
    _stopTtsEstimateTimer();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
    // Remove TTS listener and stop TTS when leaving reader
    final tts = context.read<TtsProvider>();
    tts.removeListener(_onTtsProgressChanged);
    tts.stop();
    tts.onChapterComplete = null;
    context.read<SettingsProvider>().resetBrightness();
    super.dispose();
  }

  Future<void> _loadContent() async {
    debugPrint(
      '[READER] _loadContent called, filePath=${widget.book.filePath}',
    );
    try {
      final content = await _bookService.readBookContent(widget.book.filePath);
      debugPrint('[READER] content loaded, length=${content.length}');
      final chapters = ChapterParser.parse(content);

      if (!mounted) return;

      int chapterIndex = 0;
      if (widget.book.currentPosition > 0) {
        for (int i = 0; i < chapters.length; i++) {
          if (widget.book.currentPosition >= chapters[i].startPosition &&
              widget.book.currentPosition < chapters[i].endPosition) {
            chapterIndex = i;
            break;
          }
        }
        if (widget.book.currentPosition >= chapters.last.endPosition) {
          chapterIndex = chapters.length - 1;
        }
      }

      final chapter = chapters[chapterIndex];
      final rawContent = content.substring(
        chapter.startPosition,
        chapter.endPosition,
      );
      final chapterContent = _cleanChapterContent(rawContent);

      setState(() {
        _fullContent = content;
        _chapters = chapters;
        _currentChapterIndex = chapterIndex;
        _chapterContent = chapterContent;
        _deferredPageTurnPosition = widget.book.currentPosition;
        _isLoading = false;
      });

      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn) {
        _rebuildWindowForGlobalPosition(widget.book.currentPosition);
      }
    } catch (e, stackTrace) {
      debugPrint('[READER] _loadContent ERROR: $e');
      debugPrint('[READER] stackTrace: $stackTrace');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
        Navigator.pop(context);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _chapterContent.isEmpty) return;
    if (_scrollController.position.maxScrollExtent <= 0) return;

    // Save progress periodically
    final scrollPercent =
        _scrollController.offset / _scrollController.position.maxScrollExtent;
    final chapterPos = (scrollPercent * _chapterContent.length).round();
    final globalPos =
        _chapters[_currentChapterIndex].startPosition + chapterPos;

    if ((globalPos - widget.book.currentPosition).abs() >
        widget.book.totalCharacters * 0.02) {
      _saveProgress(position: globalPos);
    }
  }

  Future<void> _saveProgress({int? position}) async {
    if (!mounted) return;

    int currentPosition;
    if (position != null) {
      currentPosition = position;
    } else {
      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn) {
        final charCount = _pageOffsetForIndex(_currentPageIndex);
        currentPosition =
            _chapters.isNotEmpty
                ? _chapters[_currentChapterIndex].startPosition + charCount
                : charCount;
      } else {
        final scrollFraction =
            (_scrollController.hasClients &&
                    _scrollController.position.maxScrollExtent > 0
                ? _scrollController.offset /
                    _scrollController.position.maxScrollExtent
                : 0.0);
        final chapterOffset = (scrollFraction * _chapterContent.length).round();
        currentPosition =
            _chapters.isNotEmpty
                ? _chapters[_currentChapterIndex].startPosition + chapterOffset
                : chapterOffset;
      }
    }

    final updatedBook = widget.book.copyWith(
      currentPosition: currentPosition,
      currentChapter: _currentChapterIndex,
    );
    context.read<BookProvider>().updateBook(updatedBook);
  }

  void _toggleMenu() {
    setState(() {
      _showMenu = !_showMenu;
    });
  }

  void _openSettings() {
    final savedPosition = _currentGlobalPosition();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    ).then((_) {
      if (!mounted || _chapters.isEmpty) return;

      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn) {
        _deferredPageTurnPosition = savedPosition;
        _rebuildWindowForGlobalPosition(savedPosition);
      } else {
        final chapterIndex = _chapterIndexForPosition(savedPosition);
        _loadChapterForScrollMode(
          chapterIndex,
          progressPosition: savedPosition,
        );
      }
    });
  }

  void _openChapterList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChapterListPage(
              chapters: _chapters,
              currentChapterIndex: _currentChapterIndex,
              onChapterSelected: _jumpToChapter,
            ),
      ),
    );
  }

  void _jumpToChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;

    _saveProgress(position: _chapters[chapterIndex].startPosition);

    final settings = context.read<SettingsProvider>().settings;
    if (settings.readingMode == ReadingMode.pageTurn) {
      _rebuildWindowForGlobalPosition(
        _chapters[chapterIndex].startPosition,
        hideMenu: true,
      );
    } else {
      _loadChapterForScrollMode(chapterIndex, hideMenu: true);
    }
  }

  void _onPageChanged(int pageIndex) {
    final window = _window;
    if (window == null || _isShifting) {
      return;
    }

    final ref = window.refAt(pageIndex);
    if (ref.isBoundary) {
      return;
    }

    final chapterIndex = ref.chapterIndex!;
    final pageInChapter = ref.pageInChapter!;

    if (chapterIndex != window.current.chapterIndex) {
      // User swiped into a pre-loaded prev/next chapter page.
      // Update tracking state immediately so the UI shows the correct
      // chapter/page info, but defer the window re-centering so the
      // PageView swipe animation plays smoothly without interruption.
      final newChapterPages =
          (window.prev != null && chapterIndex == window.prev!.chapterIndex)
              ? window.prev!
              : (window.next != null &&
                  chapterIndex == window.next!.chapterIndex)
              ? window.next!
              : null;

      setState(() {
        _currentChapterIndex = chapterIndex;
        _currentPageIndex = pageInChapter;
        if (newChapterPages != null) {
          _chapterContent = newChapterPages.cleanedContent;
          _pages = newChapterPages.pages;
        }
      });

      final globalPos =
          _chapters[chapterIndex].startPosition +
          (newChapterPages != null
              ? _pageOffsetForPages(newChapterPages.pages, pageInChapter)
              : 0);
      _saveProgress(position: globalPos);

      // Defer window shift to after the swipe animation settles.
      final token = ++_shiftToken;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted || _shiftToken != token || _isShifting) return;
        _shiftWindow(chapterIndex, pageInChapter);
      });
      return;
    }

    setState(() {
      _currentPageIndex = pageInChapter.clamp(
        0,
        _pages.isNotEmpty ? _pages.length - 1 : 0,
      );
    });

    // Calculate global position for progress
    final charCount = _pageOffsetForIndex(_currentPageIndex);
    final globalPos =
        _chapters.isNotEmpty
            ? _chapters[_currentChapterIndex].startPosition + charCount
            : charCount;
    _saveProgress(position: globalPos);
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final isSystemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final settings = settingsProvider.effectiveSettings(isSystemDark);

    return Scaffold(
      backgroundColor: Color(settings.backgroundColor),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Content area
            Listener(
              onPointerDown: (_) => _onUserInteractionStart(),
              onPointerUp: (_) => _onUserInteractionEnd(),
              onPointerCancel: (_) => _onUserInteractionEnd(),
              child: GestureDetector(
                onTap: _toggleMenu,
                child:
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : settings.readingMode == ReadingMode.pageTurn
                        ? _buildPageTurnView(settings)
                        : _buildScrollView(settings),
              ),
            ),

            // Tap overlay to dismiss menu from the reading area only.
            // Do not cover the top/bottom control bars, otherwise slider drag
            // and button taps may accidentally hide the menu.
            if (_showMenu)
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                bottom: 132,
                child: GestureDetector(
                  onTap: _toggleMenu,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),

            // Menu overlay
            if (_showMenu) ...[
              // Top title bar (display only, no actions)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Color(settings.backgroundColor).withAlpha(240),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(settings.textColor),
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: '返回',
                      ),
                      Expanded(
                        child: Text(
                          _chapters.length > 1
                              ? _chapters[_currentChapterIndex].title
                              : widget.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(settings.textColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),

              // Bottom controls
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Color(settings.backgroundColor).withAlpha(240),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (_chapters.length > 1)
                            IconButton(
                              icon: Icon(
                                Icons.list,
                                color: Color(settings.textColor),
                              ),
                              onPressed: _openChapterList,
                              tooltip: '目录',
                            ),
                          IconButton(
                            icon: Icon(
                              Icons.headphones,
                              color: Color(settings.textColor),
                            ),
                            onPressed: () {
                              final tts = context.read<TtsProvider>();
                              final wasPlaying = tts.isPlaying || tts.isPaused;
                              if (!_showTtsPanel) {
                                setState(() {
                                  _showTtsPanel = true;
                                  _showMenu = false;
                                });
                                // Auto-start if not already playing
                                if (!wasPlaying) _startTts();
                              } else {
                                _toggleTtsPanel();
                                setState(() {
                                  _showMenu = false;
                                });
                              }
                            },
                            tooltip: '听书',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.settings,
                              color: Color(settings.textColor),
                            ),
                            onPressed: _openSettings,
                            tooltip: '设置',
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                _chapters.length > 1
                                    ? '${_currentChapterIndex + 1} / ${_chapters.length}'
                                    : widget.book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(settings.textColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),

                      // Page info for page turn mode
                      if (settings.readingMode == ReadingMode.pageTurn &&
                          _pages.isNotEmpty)
                        Text(
                          '${_currentPageIndex + 1} / ${_pages.length} 页',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(settings.textColor).withAlpha(150),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            // TTS panel (shown independently of menu)
            if (_showTtsPanel)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildTtsPanel(settings),
              ),

            // Mini floating TTS indicator when panel is hidden but TTS active
            if (!_showTtsPanel && context.watch<TtsProvider>().isPlaying)
              Positioned(
                bottom: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => setState(() => _showTtsPanel = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(220),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.headphones, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '播放中',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollView(ReadingSettings settings) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chapter title
                if (_chapters.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _chapters[_currentChapterIndex].title,
                      style: TextStyle(
                        fontSize: settings.fontSize + 4,
                        fontWeight: FontWeight.bold,
                        color: Color(settings.textColor),
                      ),
                    ),
                  ),
                // Chapter content
                Text(
                  _chapterContent,
                  style: TextStyle(
                    fontSize: settings.fontSize,
                    height: settings.lineHeight,
                    color: Color(settings.textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_scrollChapterHint != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: IgnorePointer(
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(settings.backgroundColor).withAlpha(220),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      _scrollChapterHint!,
                      style: TextStyle(
                        fontSize: settings.fontSize - 2,
                        color: Color(settings.textColor),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPageTurnView(ReadingSettings settings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastLayoutSize != newSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _lastLayoutSize != newSize) {
              _lastLayoutSize = newSize;
              if (_chapters.isNotEmpty) {
                final globalPosition =
                    _deferredPageTurnPosition ?? _currentGlobalPosition();
                _rebuildWindowForGlobalPosition(globalPosition);
              }
            }
          });
        }

        final window = _window;
        if (window == null || (_pages.isEmpty && _chapterContent.isNotEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return PageView.builder(
          key: ValueKey(_windowGeneration),
          controller: _pageController,
          physics:
              _isShifting
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
          itemCount: window.totalCount,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            final ref = window.refAt(index);
            if (ref.isBoundary) {
              return _buildBoundaryPage(
                settings,
                key: ValueKey(ref.key),
                title: ref.title!,
                hint: ref.hint!,
                icon: ref.icon!,
              );
            }
            return KeyedSubtree(
              key: ValueKey(ref.key),
              child: _buildPageContent(settings, ref.pageContent!),
            );
          },
        );
      },
    );
  }

  Widget _buildPageContent(ReadingSettings settings, String pageContent) {
    return Container(
      color: Color(settings.backgroundColor),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      alignment: Alignment.topLeft,
      child: Text(
        pageContent,
        style: TextStyle(
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          color: Color(settings.textColor),
        ),
      ),
    );
  }

  Widget _buildBoundaryPage(
    ReadingSettings settings, {
    Key? key,
    required String title,
    required String hint,
    required IconData icon,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(settings.backgroundColor),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 34,
                  color: Color(settings.textColor).withAlpha(180),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: settings.fontSize,
                    fontWeight: FontWeight.w700,
                    color: Color(settings.textColor),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: settings.fontSize - 3,
                    color: Color(settings.textColor).withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleTtsPanel() {
    setState(() {
      _showTtsPanel = !_showTtsPanel;
    });
  }

  void _startTts() {
    if (_chapterContent.isEmpty) return;
    final settings = context.read<SettingsProvider>().settings;
    int charOffset = 0;
    if (settings.readingMode == ReadingMode.pageTurn) {
      charOffset = _pageOffsetForIndex(_currentPageIndex);
    } else {
      // Scroll mode: estimate char offset from scroll position
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        final fraction =
            _scrollController.offset /
            _scrollController.position.maxScrollExtent;
        charOffset = (fraction * _chapterContent.length).round();
      }
    }
    context.read<TtsProvider>().speakFrom(_chapterContent, charOffset);
  }

  Widget _buildTtsPanel(ReadingSettings settings) {
    final tts = context.watch<TtsProvider>();
    final bgColor = Color(settings.backgroundColor).withAlpha(245);
    final textColor = Color(settings.textColor);

    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.headphones, color: textColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '听书',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  // Just hide panel — TTS keeps playing in background
                  _toggleTtsPanel();
                },
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: textColor.withAlpha(150),
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Play controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous chapter
              IconButton(
                onPressed:
                    _hasPreviousChapter
                        ? () {
                          tts.stop();
                          _jumpToChapter(_currentChapterIndex - 1);
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) _startTts();
                          });
                        }
                        : null,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  color: textColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Play / Pause
              GestureDetector(
                onTap: () {
                  final tts = context.read<TtsProvider>();
                  if (tts.isPlaying) {
                    tts.pause();
                  } else if (tts.isPaused) {
                    tts.resume();
                  } else {
                    // Stopped — start from current visible position
                    _startTts();
                  }
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Icon(
                    tts.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Next chapter
              IconButton(
                onPressed:
                    _hasNextChapter
                        ? () {
                          tts.stop();
                          _jumpToChapter(_currentChapterIndex + 1);
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) _startTts();
                          });
                        }
                        : null,
                icon: Icon(Icons.skip_next_rounded, color: textColor, size: 32),
              ),
              const SizedBox(width: 8),
              // Stop button
              IconButton(
                onPressed: () {
                  tts.stop();
                },
                icon: Icon(
                  Icons.stop_rounded,
                  color: textColor.withAlpha(150),
                  size: 28,
                ),
                tooltip: '停止',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Voice selection: Male / Female
          Row(
            children: [
              Text(
                '语音',
                style: TextStyle(fontSize: 13, color: textColor.withAlpha(180)),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildVoiceSelector(tts, settings)),
            ],
          ),
          const SizedBox(height: 12),

          // Speech rate
          Row(
            children: [
              Text(
                '语速',
                style: TextStyle(fontSize: 13, color: textColor.withAlpha(180)),
              ),
              const SizedBox(width: 12),
              Text(
                '${tts.speechRate.toStringAsFixed(1)}x',
                style: TextStyle(fontSize: 13, color: textColor),
              ),
              Expanded(
                child: Slider(
                  value: tts.speechRate,
                  min: 0.2,
                  max: 1.5,
                  divisions: 13,
                  label: '${tts.speechRate.toStringAsFixed(1)}x',
                  onChanged: (value) => tts.setSpeechRate(value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceSelector(TtsProvider tts, ReadingSettings settings) {
    final textColor = Color(settings.textColor);
    final isFemale = tts.currentVoice?.gender == TtsVoiceGender.female;

    return Row(
      children: [
        _VoiceChip(
          label: '女声',
          icon: Icons.woman,
          isSelected: isFemale,
          textColor: textColor,
          onTap: () {
            final female =
                tts.femaleVoices.isNotEmpty ? tts.femaleVoices.first : null;
            if (female != null) tts.setVoice(female);
          },
        ),
        const SizedBox(width: 12),
        _VoiceChip(
          label: '男声',
          icon: Icons.man,
          isSelected: !isFemale,
          textColor: textColor,
          onTap: () {
            final male =
                tts.maleVoices.isNotEmpty ? tts.maleVoices.first : null;
            if (male != null) tts.setVoice(male);
          },
        ),
      ],
    );
  }
}

class _ChapterPages {
  final int chapterIndex;
  final List<String> pages;
  final String cleanedContent;

  const _ChapterPages({
    required this.chapterIndex,
    required this.pages,
    required this.cleanedContent,
  });
}

class _ReaderWindow {
  final _ChapterPages? prev;
  final _ChapterPages current;
  final _ChapterPages? next;
  final String currentTitle;

  const _ReaderWindow({
    required this.prev,
    required this.current,
    required this.next,
    required this.currentTitle,
  });

  bool get hasLeadingBoundary => prev == null;

  bool get hasTrailingBoundary => next == null;

  int get prevCount => prev?.pages.length ?? 0;

  int get currentStart => (hasLeadingBoundary ? 1 : 0) + prevCount;

  int get nextStart => currentStart + current.pages.length;

  int get totalCount =>
      (hasLeadingBoundary ? 1 : 0) +
      prevCount +
      current.pages.length +
      (next?.pages.length ?? 0) +
      (hasTrailingBoundary ? 1 : 0);

  int flattenedIndexFor(int chapterIndex, int pageInChapter) {
    if (prev != null && chapterIndex == prev!.chapterIndex) {
      return (hasLeadingBoundary ? 1 : 0) + pageInChapter;
    }
    if (chapterIndex == current.chapterIndex) {
      return currentStart + pageInChapter;
    }
    if (next != null && chapterIndex == next!.chapterIndex) {
      return nextStart + pageInChapter;
    }
    return currentStart;
  }

  _ReaderWindowRef refAt(int index) {
    var cursor = 0;

    if (hasLeadingBoundary) {
      if (index == cursor) {
        return _ReaderWindowRef.boundary(
          key: 'boundary-leading-c${current.chapterIndex}',
          title: currentTitle,
          hint: '已经是第一章了',
          icon: Icons.menu_book,
        );
      }
      cursor++;
    }

    if (prev != null) {
      final end = cursor + prev!.pages.length;
      if (index < end) {
        final pageInChapter = index - cursor;
        return _ReaderWindowRef.page(
          key: 'c${prev!.chapterIndex}-p$pageInChapter',
          chapterIndex: prev!.chapterIndex,
          pageInChapter: pageInChapter,
          pageContent: prev!.pages[pageInChapter],
        );
      }
      cursor = end;
    }

    final currentEnd = cursor + current.pages.length;
    if (index < currentEnd) {
      final pageInChapter = index - cursor;
      return _ReaderWindowRef.page(
        key: 'c${current.chapterIndex}-p$pageInChapter',
        chapterIndex: current.chapterIndex,
        pageInChapter: pageInChapter,
        pageContent: current.pages[pageInChapter],
      );
    }
    cursor = currentEnd;

    if (next != null) {
      final end = cursor + next!.pages.length;
      if (index < end) {
        final pageInChapter = index - cursor;
        return _ReaderWindowRef.page(
          key: 'c${next!.chapterIndex}-p$pageInChapter',
          chapterIndex: next!.chapterIndex,
          pageInChapter: pageInChapter,
          pageContent: next!.pages[pageInChapter],
        );
      }
      cursor = end;
    }

    if (hasTrailingBoundary && index == cursor) {
      return _ReaderWindowRef.boundary(
        key: 'boundary-trailing-c${current.chapterIndex}',
        title: currentTitle,
        hint: '已经是最后一章了',
        icon: Icons.menu_book,
      );
    }

    throw RangeError.index(index, List<int>.generate(totalCount, (i) => i));
  }
}

class _ReaderWindowRef {
  final String key;
  final int? chapterIndex;
  final int? pageInChapter;
  final String? pageContent;
  final String? title;
  final String? hint;
  final IconData? icon;

  const _ReaderWindowRef._({
    required this.key,
    this.chapterIndex,
    this.pageInChapter,
    this.pageContent,
    this.title,
    this.hint,
    this.icon,
  });

  const _ReaderWindowRef.page({
    required String key,
    required int chapterIndex,
    required int pageInChapter,
    required String pageContent,
  }) : this._(
         key: key,
         chapterIndex: chapterIndex,
         pageInChapter: pageInChapter,
         pageContent: pageContent,
       );

  const _ReaderWindowRef.boundary({
    required String key,
    required String title,
    required String hint,
    required IconData icon,
  }) : this._(key: key, title: title, hint: hint, icon: icon);

  bool get isBoundary => title != null;
}

class _VoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color textColor;
  final VoidCallback onTap;

  const _VoiceChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color:
              isSelected
                  ? Theme.of(context).colorScheme.primary.withAlpha(40)
                  : textColor.withAlpha(20),
          border: Border.all(
            color:
                isSelected
                    ? Theme.of(context).colorScheme.primary
                    : textColor.withAlpha(60),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  isSelected
                      ? Theme.of(context).colorScheme.primary
                      : textColor.withAlpha(150),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color:
                    isSelected
                        ? Theme.of(context).colorScheme.primary
                        : textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
