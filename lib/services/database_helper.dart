import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('recall_pulse.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute(
      'CREATE TABLE decks ('
      'id TEXT PRIMARY KEY, '
      'title TEXT NOT NULL, '
      'description TEXT, '
      'created_at TEXT NOT NULL'
      ')'
    );

    await db.execute(
      'CREATE TABLE flashcards ('
      'id TEXT PRIMARY KEY, '
      'deck_id TEXT NOT NULL, '
      'question TEXT NOT NULL, '
      'answer TEXT NOT NULL, '
      'explanation TEXT, '
      'repetitions INTEGER NOT NULL, '
      'ease_factor REAL NOT NULL, '
      'interval INTEGER NOT NULL, '
      'next_review_date TEXT NOT NULL, '
      'created_at TEXT NOT NULL, '
      'FOREIGN KEY (deck_id) REFERENCES decks (id) ON DELETE CASCADE'
      ')'
    );
  }

  Future<void> insertDeck(Deck deck) async {
    final db = await instance.database;
    await db.insert('decks', deck.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Deck>> getAllDecks() async {
    final db = await instance.database;
    final result = await db.query('decks', orderBy: 'created_at DESC');
    return result.map((json) => Deck.fromMap(json)).toList();
  }

  Future<void> insertMultipleFlashcards(List<Flashcard> cards) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var card in cards) {
      batch.insert('flashcards', card.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Flashcard>> getCardsByDeck(String deckId) async {
    final db = await instance.database;
    final result = await db.query('flashcards', where: 'deck_id = ?', whereArgs: [deckId]);
    return result.map((json) => Flashcard.fromMap(json)).toList();
  }

  Future<List<Flashcard>> getDueFlashcards() async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    final result = await db.query('flashcards', where: 'next_review_date <= ?', whereArgs: [now]);
    return result.map((json) => Flashcard.fromMap(json)).toList();
  }

  Future<void> updateFlashcard(Flashcard card) async {
    final db = await instance.database;
    await db.update('flashcards', card.toMap(), where: 'id = ?', whereArgs: [card.id]);
  }
}
