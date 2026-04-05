import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

class BookService {
  static const String _booksKey = 'books';

  /// Get the persistent directory for storing book files.
  Future<Directory> _getBooksDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final booksDir = Directory('${appDir.path}/books');
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir;
  }

  Future<List<Book>> getBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final booksJson = prefs.getStringList(_booksKey) ?? [];
    return booksJson.map((json) => Book.fromJson(jsonDecode(json))).toList();
  }

  Future<void> saveBooks(List<Book> books) async {
    final prefs = await SharedPreferences.getInstance();
    final booksJson = books.map((book) => jsonEncode(book.toJson())).toList();
    await prefs.setStringList(_booksKey, booksJson);
  }

  Future<Book> addBook(String filePath) async {
    final file = File(filePath);
    final fileName = file.path.split(Platform.pathSeparator).last;

    // Remove file extension for title
    String title = fileName.replaceAll(RegExp(r'\.[^\.]+$'), '');

    final bookId = DateTime.now().millisecondsSinceEpoch.toString();

    // Copy the file to persistent storage so it survives cache cleanup.
    // On Android, file_picker returns a cache path that can be cleaned up.
    final booksDir = await _getBooksDir();
    final persistentPath = '${booksDir.path}/${bookId}_$fileName';
    final persistentFile = await file.copy(persistentPath);

    // Read from the persistent copy to get character count
    int totalCharacters = 0;
    try {
      final content = await persistentFile.readAsString();
      totalCharacters = content.length;
    } catch (e) {
      totalCharacters = 0;
    }

    final book = Book(
      id: bookId,
      title: title,
      author: 'Unknown',
      filePath: persistentPath,
      addedDate: DateTime.now(),
      totalCharacters: totalCharacters,
    );

    final books = await getBooks();
    books.add(book);
    await saveBooks(books);

    return book;
  }

  Future<void> updateBook(Book book) async {
    final books = await getBooks();
    final index = books.indexWhere((b) => b.id == book.id);
    if (index != -1) {
      books[index] = book;
      await saveBooks(books);
    }
  }

  Future<void> deleteBook(String bookId) async {
    final books = await getBooks();
    final bookIndex = books.indexWhere((book) => book.id == bookId);
    if (bookIndex != -1) {
      // Delete the persisted file copy
      try {
        final file = File(books[bookIndex].filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore file deletion errors
      }
      books.removeAt(bookIndex);
      await saveBooks(books);
    }
  }

  Future<String> readBookContent(String filePath) async {
    debugPrint('[BOOK_SERVICE] readBookContent: filePath=$filePath');
    try {
      final file = File(filePath);
      final exists = await file.exists();
      debugPrint('[BOOK_SERVICE] file exists: $exists');
      if (!exists) {
        throw Exception('File not found: $filePath');
      }
      final content = await file.readAsString();
      debugPrint('[BOOK_SERVICE] content read, length=${content.length}');
      return content;
    } catch (e) {
      debugPrint('[BOOK_SERVICE] readBookContent ERROR: $e');
      throw Exception('Failed to read file: $e');
    }
  }
}
