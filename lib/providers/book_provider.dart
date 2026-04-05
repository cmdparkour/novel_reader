import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';

class BookProvider with ChangeNotifier {
  final BookService _bookService = BookService();
  List<Book> _books = [];
  bool _isLoading = false;

  List<Book> get books => _books;
  bool get isLoading => _isLoading;

  Future<void> loadBooks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _books = await _bookService.getBooks();
    } catch (e) {
      debugPrint('Error loading books: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Book?> addBook(String filePath) async {
    try {
      final book = await _bookService.addBook(filePath);
      _books.add(book);
      notifyListeners();
      return book;
    } catch (e) {
      debugPrint('Error adding book: $e');
      return null;
    }
  }

  Future<void> updateBook(Book book) async {
    try {
      await _bookService.updateBook(book);
      final index = _books.indexWhere((b) => b.id == book.id);
      if (index != -1) {
        _books[index] = book;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating book: $e');
    }
  }

  Future<void> deleteBook(String bookId) async {
    try {
      await _bookService.deleteBook(bookId);
      _books.removeWhere((book) => book.id == bookId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting book: $e');
    }
  }

  Book? getBookById(String bookId) {
    try {
      return _books.firstWhere((book) => book.id == bookId);
    } catch (e) {
      return null;
    }
  }
}
