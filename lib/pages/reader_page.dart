import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:page_flip/page_flip.dart';
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
  final PageFlipController _pageFlipController = PageFlipController();

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
  int _pageFlipViewVersion = 0;
  double _pageFlipDragDx = 0;
  double _pageFlipDragDy = 0;
  bool _pageFlipStartedOnFirstPage = false;

  bool get _hasPreviousChapter => _currentChapterIndex > 0;

  bool get _hasNextChapter => _currentChapterIndex < _chapters.length - 1;

  List<String> _paginateContent(String content) {
    if (content.isEmpty) {
      return const [];
    }

    final settings = context.read<SettingsProvider>().settings;
    final charsPerPage = (680 *
            (18.0 / settings.fontSize) /
            settings.lineHeight)
        .round()
        .clamp(200, 2000);

    final pages = <String>[];
    int start = 0;
    while (start < content.length) {
      int end = (start + charsPerPage).clamp(0, content.length);
      if (end < content.length) {
        final newlinePos = content.lastIndexOf('\n', end);
        if (newlinePos > start + (charsPerPage * 0.5)) {
          end = newlinePos + 1;
        }
      }
      pages.add(content.substring(start, end));
      start = end;
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
    final content = rawContent.replaceFirst(
      RegExp(r'^([^\n]*)(\n\s*)+'),
      r'$1\n',
    );
    final pages = _paginateContent(content);
    final safePageIndex =
        pages.isEmpty ? 0 : initialPageIndex.clamp(0, pages.length - 1);

    setState(() {
      _chapterContent = content;
      _currentChapterIndex = chapterIndex;
      _pages = pages;
      _currentPageIndex = safePageIndex;
      _pageFlipViewVersion++;
      if (hideMenu) {
        _showMenu = false;
      }
    });

    // Reset scroll/page position for new chapter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn && _pages.isNotEmpty) {
        _pageFlipController.goToPage(safePageIndex);
      }
    });

    debugPrint(
      '[READER] chapter $chapterIndex loaded, content length=${content.length}',
    );
  }

  /// Split current chapter content into pages for page turn mode.
  void _buildPages() {
    setState(() {
      _pages = _paginateContent(_chapterContent);
      _currentPageIndex =
          _pages.isEmpty ? 0 : _currentPageIndex.clamp(0, _pages.length - 1);
      _pageFlipViewVersion++;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsProvider>().settings;
      if (settings.readingMode == ReadingMode.pageTurn && _pages.isNotEmpty) {
        _pageFlipController.goToPage(_currentPageIndex);
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

  void _onPageFlipped(int pageIndex) {
    if (_hasNextChapter && pageIndex >= _pages.length) {
      _loadChapterContent(_currentChapterIndex + 1);
      return;
    }

    setState(() {
      _currentPageIndex = pageIndex;
    });

    // Calculate global position for progress
    final charCount = _pageOffsetForIndex(pageIndex);
    final globalPos =
        _chapters.isNotEmpty
            ? _chapters[_currentChapterIndex].startPosition + charCount
            : charCount;
    _saveProgress(position: globalPos);
  }

  void _onPageFlipPointerDown(PointerDownEvent event) {
    _pageFlipDragDx = 0;
    _pageFlipDragDy = 0;
    _pageFlipStartedOnFirstPage = _currentPageIndex == 0;
  }

  void _onPageFlipPointerMove(PointerMoveEvent event) {
    _pageFlipDragDx += event.delta.dx;
    _pageFlipDragDy += event.delta.dy;
  }

  void _onPageFlipPointerEnd(PointerEvent event) {
    final shouldOpenPreviousChapter =
        _pageFlipStartedOnFirstPage &&
        _hasPreviousChapter &&
        _pageFlipDragDx > 72 &&
        _pageFlipDragDx.abs() > _pageFlipDragDy.abs();

    _pageFlipDragDx = 0;
    _pageFlipDragDy = 0;
    _pageFlipStartedOnFirstPage = false;

    if (!shouldOpenPreviousChapter) {
      return;
    }

    final previousChapterIndex = _currentChapterIndex - 1;
    final previousChapter = _chapters[previousChapterIndex];
    final previousContent = _fullContent.substring(
      previousChapter.startPosition,
      previousChapter.endPosition,
    );
    final previousPages = _paginateContent(previousContent);
    _loadChapterContent(
      previousChapterIndex,
      initialPageIndex: previousPages.isEmpty ? 0 : previousPages.length - 1,
    );
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
    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Listener(
      onPointerDown: _onPageFlipPointerDown,
      onPointerMove: _onPageFlipPointerMove,
      onPointerUp: _onPageFlipPointerEnd,
      onPointerCancel: _onPageFlipPointerEnd,
      child: PageFlipWidget(
        key: ValueKey(_pageFlipViewVersion),
        controller: _pageFlipController,
        backgroundColor: Color(settings.backgroundColor),
        initialIndex: _currentPageIndex.clamp(0, _pages.length - 1),
        children: List<Widget>.of(
          _pages.map((page) => _buildPageContent(settings, page)),
        ),
        lastPage:
            _hasNextChapter
                ? _buildBoundaryPage(
                  settings,
                  title: _chapters[_currentChapterIndex + 1].title,
                  hint: '继续右滑进入下一章',
                  icon: Icons.keyboard_double_arrow_right,
                )
                : null,
        onPageFlipped: _onPageFlipped,
      ),
    );
  }

  Widget _buildPageContent(ReadingSettings settings, String pageContent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Container(
        color: Color(settings.backgroundColor),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 48),
        child: Text(
          pageContent,
          style: TextStyle(
            fontSize: settings.fontSize,
            height: settings.lineHeight,
            color: Color(settings.textColor),
          ),
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
