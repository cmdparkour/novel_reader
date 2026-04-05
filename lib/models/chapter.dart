class Chapter {
  final int index;
  final String title;
  final int startPosition;
  final int endPosition;

  /// If this chapter belongs to a volume/section (卷/篇/部),
  /// this field holds the volume title. null means no volume grouping.
  final String? volumeTitle;

  const Chapter({
    required this.index,
    required this.title,
    required this.startPosition,
    required this.endPosition,
    this.volumeTitle,
  });

  int get length => endPosition - startPosition;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'title': title,
      'startPosition': startPosition,
      'endPosition': endPosition,
      'volumeTitle': volumeTitle,
    };
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      index: json['index'],
      title: json['title'],
      startPosition: json['startPosition'],
      endPosition: json['endPosition'],
      volumeTitle: json['volumeTitle'],
    );
  }
}
