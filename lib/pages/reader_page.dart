import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/reading_settings.dart';
import '../providers/book_provider.dart';
import '../providers/settings_provider.dart';
import '../services/book_service.dart';
import '../services/chapter_parser.dart';
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
  PageController _pageController = PageController();

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
    // Available width/height inside page padding
    // Horizontal: 16 each side = 32 total
    // Vertical: 16 top + 48 bottom (reserve space for menu overlay)
    final availableWidth = pageSize.width - 32;
    final availableHeight = pageSize.height - 64;

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
    int charCount = 0;
    for (int i = 0; i < pageIndex && i < _pages.length; i++) {
      charCount += _pages[i].length;
    }
    return charCount;
  }

  @override
  void initState() {
    super.initState();
    _loadContent();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
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

      // Determine current chapter based on saved position
      int chapterIndex = 0;
      if (widget.book.currentPosition > 0) {
        for (int i = 0; i < chapters.length; i++) {
          if (widget.book.currentPosition >= chapters[i].startPosition &&
              widget.book.currentPosition < chapters[i].endPosition) {
            chapterIndex = i;
            break;
          }
        }
      }

      setState(() {
        _fullContent = content;
        _chapters = chapters;
        _currentChapterIndex = chapterIndex;
        _isLoading = false;
      });

      // Load current chapter content
      _loadChapterContent(chapterIndex);
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

  // Pending initial page index when layout size is not yet available
  int _pendingInitialPageIndex = 0;

  /// Load only the content for the specified chapter.
  void _loadChapterContent(
    int chapterIndex, {
    int initialPageIndex = 0,
    bool hideMenu = false,
  }) {
    if (_chapters.isEmpty ||
        chapterIndex < 0 ||
        chapterIndex >= _chapters.length)
      return;

    final chapter = _chapters[chapterIndex];
    final rawContent = _fullContent.substring(
      chapter.startPosition,
      chapter.endPosition,
    );
    final content = rawContent.replaceFirstMapped(
      RegExp(r'^([^\n]*)(\n\s*)+'),
      (match) => '${match[1]}\n',
    );

    // If layout size is not yet available, defer pagination
    List<String> pages;
    if (_lastLayoutSize == Size.zero) {
      pages = [];
      _pendingInitialPageIndex = initialPageIndex;
    } else {
      pages = _paginateContent(content, _lastLayoutSize);
    }
    final safePageIndex =
        pages.isEmpty ? 0 : initialPageIndex.clamp(0, pages.length - 1);

    setState(() {
      _chapterContent = content;
      _currentChapterIndex = chapterIndex;
      _pages = pages;
      _currentPageIndex = safePageIndex;
      if (hideMenu) {
        _showMenu = false;
      }
    });

    // Reset scroll/page position for new chapter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn && _pages.isNotEmpty) {
        final hasPrevBoundary = _currentChapterIndex > 0;
        final initialPage = safePageIndex + (hasPrevBoundary ? 1 : 0);
        _pageController.dispose();
        _pageController = PageController(initialPage: initialPage);
        setState(() {});
      }
    });

    debugPrint(
      '[READER] chapter $chapterIndex loaded, content length=${content.length}',
    );
  }

  /// Split current chapter content into pages for page turn mode.
  void _buildPages() {
    setState(() {
      _pages = _paginateContent(_chapterContent, _lastLayoutSize);
      _currentPageIndex =
          _pages.isEmpty ? 0 : _currentPageIndex.clamp(0, _pages.length - 1);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn && _pages.isNotEmpty) {
        _pageController.dispose();
        _pageController = PageController(initialPage: _currentPageIndex);
        if (mounted) setState(() {});
      }
    });
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
        // Calculate position from current page within chapter
        int charCount = 0;
        for (int i = 0; i < _currentPageIndex && i < _pages.length; i++) {
          charCount += _pages[i].length;
        }
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    ).then((_) {
      _loadChapterContent(
        _currentChapterIndex,
        initialPageIndex: _currentPageIndex,
      );
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

    _loadChapterContent(chapterIndex, hideMenu: true);
    _saveProgress(position: _chapters[chapterIndex].startPosition);
  }

  void _onPageChanged(int pageIndex) {
    // Reached the boundary page (last + 1) → go to next chapter
    if (_hasNextChapter && pageIndex >= _pages.length) {
      _loadChapterContent(_currentChapterIndex + 1);
      return;
    }
    // Reached the boundary page (first - 1 = index -1 mapped to 0 in itemBuilder)
    // This is handled differently with PageView item count, see _buildPageTurnView

    setState(() {
      _currentPageIndex = pageIndex.clamp(
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

  double get _currentProgress {
    if (_chapters.isEmpty || _fullContent.isEmpty) return 0.0;

    final chapterStart = _chapters[_currentChapterIndex].startPosition;
    final settings = context.read<SettingsProvider>().settings;

    double chapterFraction;
    if (settings.readingMode == ReadingMode.pageTurn) {
      chapterFraction =
          _pages.isEmpty ? 0.0 : _currentPageIndex / _pages.length;
    } else {
      if (!_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent <= 0) {
        chapterFraction = 0.0;
      } else {
        chapterFraction =
            _scrollController.offset /
            _scrollController.position.maxScrollExtent;
      }
    }

    final globalPos = chapterStart + (chapterFraction * _chapterContent.length);
    return (globalPos / _fullContent.length).clamp(0.0, 1.0);
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
        child: Stack(
          children: [
            // Content area
            GestureDetector(
              onTap: _toggleMenu,
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : settings.readingMode == ReadingMode.pageTurn
                      ? _buildPageTurnView(settings)
                      : _buildScrollView(settings),
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

                      // Progress bar
                      Row(
                        children: [
                          Text(
                            '${(_currentProgress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(settings.textColor),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _currentProgress.clamp(0.0, 1.0),
                              onChanged: (value) {
                                // Jump to global position
                                final targetPos =
                                    (value * _fullContent.length).round();
                                // Find which chapter this falls in
                                for (int i = 0; i < _chapters.length; i++) {
                                  if (targetPos >= _chapters[i].startPosition &&
                                      targetPos < _chapters[i].endPosition) {
                                    if (i != _currentChapterIndex) {
                                      _jumpToChapter(i);
                                    }
                                    break;
                                  }
                                }
                              },
                            ),
                          ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildScrollView(ReadingSettings settings) {
    return SingleChildScrollView(
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
    );
  }

  Widget _buildPageTurnView(ReadingSettings settings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastLayoutSize != newSize) {
          // Schedule re-pagination on next frame with new size
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _lastLayoutSize != newSize) {
              _lastLayoutSize = newSize;
              if (_chapterContent.isNotEmpty) {
                final pages = _paginateContent(_chapterContent, newSize);
                final safePageIndex =
                    pages.isEmpty
                        ? 0
                        : _pendingInitialPageIndex.clamp(0, pages.length - 1);
                _pendingInitialPageIndex = 0;
                final hasPrevBoundary = _currentChapterIndex > 0;
                final initialPage = safePageIndex + (hasPrevBoundary ? 1 : 0);
                _pageController.dispose();
                _pageController = PageController(initialPage: initialPage);
                setState(() {
                  _pages = pages;
                  _currentPageIndex = safePageIndex;
                });
              }
            }
          });
        }

        if (_pages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Total items: pages + optional boundary pages
        final hasPrevBoundary = _hasPreviousChapter;
        final hasNextBoundary = _hasNextChapter;
        final totalItems =
            _pages.length +
            (hasPrevBoundary ? 1 : 0) +
            (hasNextBoundary ? 1 : 0);
        final offset = hasPrevBoundary ? 1 : 0;

        return PageView.builder(
          controller: _pageController,
          itemCount: totalItems,
          onPageChanged: (index) {
            final pageIndex = index - offset;
            if (hasPrevBoundary && index == 0) {
              final prevIdx = _currentChapterIndex - 1;
              final prevChapter = _chapters[prevIdx];
              final prevContent = _fullContent.substring(
                prevChapter.startPosition,
                prevChapter.endPosition,
              );
              final prevPages = _paginateContent(prevContent, _lastLayoutSize);
              _loadChapterContent(
                prevIdx,
                initialPageIndex: prevPages.isEmpty ? 0 : prevPages.length - 1,
              );
              return;
            }
            if (hasNextBoundary && pageIndex >= _pages.length) {
              _loadChapterContent(_currentChapterIndex + 1);
              return;
            }
            _onPageChanged(pageIndex);
          },
          itemBuilder: (context, index) {
            final pageIndex = index - offset;
            if (hasPrevBoundary && index == 0) {
              return _buildBoundaryPage(
                settings,
                title: _chapters[_currentChapterIndex - 1].title,
                hint: '滑动进入上一章',
                icon: Icons.keyboard_double_arrow_left,
              );
            }
            if (hasNextBoundary && pageIndex >= _pages.length) {
              return _buildBoundaryPage(
                settings,
                title: _chapters[_currentChapterIndex + 1].title,
                hint: '滑动进入下一章',
                icon: Icons.keyboard_double_arrow_right,
              );
            }
            return _buildPageContent(settings, _pages[pageIndex]);
          },
        );
      },
    );
  }

  Widget _buildPageContent(ReadingSettings settings, String pageContent) {
    return Container(
      color: Color(settings.backgroundColor),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
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
    required String title,
    required String hint,
    required IconData icon,
  }) {
    return Padding(
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
}
