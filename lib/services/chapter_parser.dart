import '../models/chapter.dart';

class ChapterParser {
  /// Volume-level patterns: 第X卷/篇/部 (standalone, not combined with 第X章)
  static final RegExp _volumePattern = RegExp(
    r'^\s*第[零一二三四五六七八九十百千万\d]+[卷篇部]\s+.{1,30}$',
    multiLine: true,
  );

  /// Chapter-level patterns (ordered by specificity).
  static final List<RegExp> _chapterPatterns = [
    // 第X章/节/回 (with optional inline volume prefix)
    RegExp(
      r'^\s*(?:第[零一二三四五六七八九十百千万\d]+[篇卷部]\s*.{0,15}\s+)?第[零一二三四五六七八九十百千万\d]+[章节回]\s*.{0,30}$',
      multiLine: true,
    ),
    // Chapter N / CHAPTER N
    RegExp(r'^\s*[Cc]hapter\s+\d+.*$', multiLine: true),
    // 【第X章】style
    RegExp(r'^\s*【第[零一二三四五六七八九十百千万\d]+[章节回卷].*?】\s*$', multiLine: true),
  ];

  /// Parse chapters from content string.
  /// Detects two-level hierarchy (volume → chapter) when volume headings exist.
  static List<Chapter> parse(String content) {
    // Detect volume headings
    final volumeMatches = <_Heading>[];
    for (final match in _volumePattern.allMatches(content)) {
      final title = match.group(0)!.trim();
      if (title.length >= 2 && title.length <= 50) {
        volumeMatches.add(_Heading(title: title, position: match.start));
      }
    }

    // Detect chapter headings
    final chapterMatches = <_Heading>[];
    for (final pattern in _chapterPatterns) {
      for (final match in pattern.allMatches(content)) {
        final title = match.group(0)!.trim();
        if (title.length < 2 || title.length > 50) continue;
        chapterMatches.add(_Heading(title: title, position: match.start));
      }
    }

    // Remove chapter matches that overlap with volume matches (within 10 chars)
    final filteredChapters = <_Heading>[];
    for (final ch in chapterMatches) {
      final isVolumeHeading = volumeMatches.any(
        (v) => (ch.position - v.position).abs() < 10,
      );
      if (!isVolumeHeading) {
        filteredChapters.add(ch);
      }
    }

    // Sort and deduplicate all headings
    filteredChapters.sort((a, b) => a.position.compareTo(b.position));
    final dedupedChapters = _deduplicate(filteredChapters);
    volumeMatches.sort((a, b) => a.position.compareTo(b.position));
    final dedupedVolumes = _deduplicate(volumeMatches);

    // If no chapters found at all
    if (dedupedChapters.isEmpty && dedupedVolumes.isEmpty) {
      return [
        Chapter(
          index: 0,
          title: '全文',
          startPosition: 0,
          endPosition: content.length,
        ),
      ];
    }

    // Merge all headings into a single sorted list with type info
    final allHeadings = <_TypedHeading>[];
    for (final v in dedupedVolumes) {
      allHeadings.add(_TypedHeading(heading: v, isVolume: true));
    }
    for (final c in dedupedChapters) {
      allHeadings.add(_TypedHeading(heading: c, isVolume: false));
    }
    allHeadings.sort(
      (a, b) => a.heading.position.compareTo(b.heading.position),
    );

    // Deduplicate across types (volume and chapter at same position)
    final mergedHeadings = <_TypedHeading>[];
    for (final h in allHeadings) {
      if (mergedHeadings.isNotEmpty &&
          (h.heading.position - mergedHeadings.last.heading.position).abs() <
              10) {
        // Keep volume over chapter when they overlap
        if (h.isVolume && !mergedHeadings.last.isVolume) {
          mergedHeadings.last = h;
        }
        continue;
      }
      mergedHeadings.add(h);
    }

    // Build chapter list with volume assignment
    final chapters = <Chapter>[];
    String? currentVolume;

    // Content before first heading → preface
    if (mergedHeadings.first.heading.position > 100) {
      chapters.add(
        Chapter(
          index: 0,
          title: '前言',
          startPosition: 0,
          endPosition: mergedHeadings.first.heading.position,
        ),
      );
    }

    for (int i = 0; i < mergedHeadings.length; i++) {
      final current = mergedHeadings[i];
      final endPos =
          i + 1 < mergedHeadings.length
              ? mergedHeadings[i + 1].heading.position
              : content.length;

      if (current.isVolume) {
        currentVolume = current.heading.title;
        // Only add volume as a chapter entry if it has substantial content
        // before the next heading (i.e. volume intro text)
        if (i + 1 < mergedHeadings.length) {
          final nextPos = mergedHeadings[i + 1].heading.position;
          final gap = nextPos - current.heading.position;
          // If the gap is small, it's just a heading followed by a chapter heading
          // — skip adding the volume as its own chapter entry
          if (gap > 200) {
            chapters.add(
              Chapter(
                index: chapters.length,
                title: current.heading.title,
                startPosition: current.heading.position,
                endPosition: nextPos,
                volumeTitle: currentVolume,
              ),
            );
          }
        } else {
          // Volume is the last heading
          chapters.add(
            Chapter(
              index: chapters.length,
              title: current.heading.title,
              startPosition: current.heading.position,
              endPosition: endPos,
              volumeTitle: currentVolume,
            ),
          );
        }
      } else {
        chapters.add(
          Chapter(
            index: chapters.length,
            title: current.heading.title,
            startPosition: current.heading.position,
            endPosition: endPos,
            volumeTitle: currentVolume,
          ),
        );
      }
    }

    return chapters;
  }

  static List<_Heading> _deduplicate(List<_Heading> matches) {
    if (matches.isEmpty) return matches;
    final result = <_Heading>[matches.first];
    for (int i = 1; i < matches.length; i++) {
      if (matches[i].position - result.last.position > 10) {
        result.add(matches[i]);
      }
    }
    return result;
  }
}

class _Heading {
  final String title;
  final int position;
  const _Heading({required this.title, required this.position});
}

class _TypedHeading {
  final _Heading heading;
  final bool isVolume;
  _TypedHeading({required this.heading, required this.isVolume});
}
