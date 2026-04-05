class Book {
  final String id;
  final String title;
  final String author;
  final String filePath;
  final DateTime addedDate;
  final int currentChapter;
  final int currentPosition;
  final int totalCharacters;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.addedDate,
    this.currentChapter = 0,
    this.currentPosition = 0,
    this.totalCharacters = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'filePath': filePath,
      'addedDate': addedDate.toIso8601String(),
      'currentChapter': currentChapter,
      'currentPosition': currentPosition,
      'totalCharacters': totalCharacters,
    };
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'],
      title: json['title'],
      author: json['author'] ?? 'Unknown',
      filePath: json['filePath'],
      addedDate: DateTime.parse(json['addedDate']),
      currentChapter: json['currentChapter'] ?? 0,
      currentPosition: json['currentPosition'] ?? 0,
      totalCharacters: json['totalCharacters'] ?? 0,
    );
  }

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? filePath,
    DateTime? addedDate,
    int? currentChapter,
    int? currentPosition,
    int? totalCharacters,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      addedDate: addedDate ?? this.addedDate,
      currentChapter: currentChapter ?? this.currentChapter,
      currentPosition: currentPosition ?? this.currentPosition,
      totalCharacters: totalCharacters ?? this.totalCharacters,
    );
  }

  double get progress {
    if (totalCharacters == 0) return 0.0;
    return currentPosition / totalCharacters;
  }
}
