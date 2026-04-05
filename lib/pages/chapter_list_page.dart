import 'package:flutter/material.dart';
import '../models/chapter.dart';

class ChapterListPage extends StatefulWidget {
  final List<Chapter> chapters;
  final int currentChapterIndex;
  final void Function(int chapterIndex) onChapterSelected;

  const ChapterListPage({
    super.key,
    required this.chapters,
    required this.currentChapterIndex,
    required this.onChapterSelected,
  });

  @override
  State<ChapterListPage> createState() => _ChapterListPageState();
}

class _ChapterListPageState extends State<ChapterListPage> {
  final ScrollController _scrollController = ScrollController();

  /// Check if any chapter has a volume grouping.
  bool get _hasVolumes => widget.chapters.any((c) => c.volumeTitle != null);

  // Estimated tile height for auto-scroll calculation.
  static const double _tileHeight = 56.0;
  static const double _volumeHeaderHeight = 48.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentChapter();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentChapter() {
    if (!_scrollController.hasClients) return;
    final index = widget.currentChapterIndex;
    if (index <= 0) return;

    double offset;
    if (_hasVolumes) {
      // Count volume headers and tiles before the current chapter.
      offset = _estimateGroupedOffset(index);
    } else {
      offset = index * _tileHeight;
    }

    // Center the item in the viewport.
    final viewportHeight = _scrollController.position.viewportDimension;
    offset = (offset - viewportHeight / 2 + _tileHeight / 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.jumpTo(offset);
  }

  double _estimateGroupedOffset(int targetIndex) {
    double offset = 0;
    String? currentVolume;
    for (int i = 0; i < widget.chapters.length && i < targetIndex; i++) {
      final volume = widget.chapters[i].volumeTitle;
      if (volume != currentVolume) {
        // New volume header.
        if (volume != null) offset += _volumeHeaderHeight;
        currentVolume = volume;
      }
      offset += _tileHeight;
    }
    // Account for the header of the target chapter's group if it starts a new volume.
    final targetVolume = widget.chapters[targetIndex].volumeTitle;
    if (targetVolume != currentVolume && targetVolume != null) {
      offset += _volumeHeaderHeight;
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('目录 (${widget.chapters.length}章)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _hasVolumes ? _buildGroupedList(context) : _buildFlatList(context),
    );
  }

  /// Flat list — no volume grouping.
  Widget _buildFlatList(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.chapters.length,
      itemBuilder: (context, index) => _buildChapterTile(context, index),
    );
  }

  /// Grouped list — chapters grouped under volume headers.
  Widget _buildGroupedList(BuildContext context) {
    final groups = <_VolumeGroup>[];
    String? currentVolume;
    List<int> currentIndices = [];

    for (int i = 0; i < widget.chapters.length; i++) {
      final chapter = widget.chapters[i];
      final volume = chapter.volumeTitle;

      if (volume != currentVolume) {
        if (currentIndices.isNotEmpty) {
          groups.add(
            _VolumeGroup(
              volumeTitle: currentVolume,
              chapterIndices: List.of(currentIndices),
            ),
          );
        }
        currentVolume = volume;
        currentIndices = [i];
      } else {
        currentIndices.add(i);
      }
    }
    // Add last group
    if (currentIndices.isNotEmpty) {
      groups.add(
        _VolumeGroup(
          volumeTitle: currentVolume,
          chapterIndices: currentIndices,
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        return _buildVolumeSection(context, group);
      },
    );
  }

  Widget _buildVolumeSection(BuildContext context, _VolumeGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Volume header
        if (group.volumeTitle != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              group.volumeTitle!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          )
        else
          const SizedBox(height: 8),
        // Chapters in this volume
        ...group.chapterIndices.map(
          (index) => _buildChapterTile(context, index),
        ),
      ],
    );
  }

  Widget _buildChapterTile(BuildContext context, int index) {
    final chapter = widget.chapters[index];
    final isCurrent = index == widget.currentChapterIndex;

    return ListTile(
      contentPadding: EdgeInsets.only(
        left: _hasVolumes && chapter.volumeTitle != null ? 32 : 16,
        right: 16,
      ),
      leading:
          isCurrent
              ? Icon(
                Icons.bookmark,
                color: Theme.of(context).colorScheme.primary,
              )
              : Text(
                '${index + 1}',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
      title: Text(
        chapter.title,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? Theme.of(context).colorScheme.primary : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          isCurrent
              ? const Text(
                '当前',
                style: TextStyle(color: Colors.blue, fontSize: 12),
              )
              : null,
      onTap: () {
        widget.onChapterSelected(index);
        Navigator.pop(context);
      },
    );
  }
}

class _VolumeGroup {
  final String? volumeTitle;
  final List<int> chapterIndices;

  const _VolumeGroup({required this.volumeTitle, required this.chapterIndices});
}
