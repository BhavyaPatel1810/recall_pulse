import 'dart:io' show Platform;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';

class DeckStats {
  final int totalCards;
  final int dueCards;
  final int masteredCards;

  const DeckStats({
    required this.totalCards,
    required this.dueCards,
    required this.masteredCards,
  });
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('recallpulse.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onConfigure: _onConfigure,
      onCreate: _createDB,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE decks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0,
        isDeleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE flashcards (
        id TEXT PRIMARY KEY,
        deckId TEXT NOT NULL,
        question TEXT NOT NULL,
        answer TEXT NOT NULL,
        aiExplanation TEXT NOT NULL,
        tags TEXT NOT NULL,
        easeFactor REAL NOT NULL,
        interval INTEGER NOT NULL,
        repetitions INTEGER NOT NULL,
        nextReviewDate TEXT NOT NULL,
        isStarredForNotification INTEGER NOT NULL DEFAULT 0,
        updatedAt TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (deckId) REFERENCES decks (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_flashcards_deckId ON flashcards(deckId)');
    await db.execute('CREATE INDEX idx_flashcards_review ON flashcards(nextReviewDate, isDeleted)');
    await db.execute('CREATE INDEX idx_decks_sync ON decks(isSynced)');
    await db.execute('CREATE INDEX idx_flashcards_sync ON flashcards(isSynced)');

    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    final nowUtc = DateTime.now().toUtc();
    const uuid = Uuid();
    final deckId = uuid.v4();

    await db.insert('decks', {
      'id': deckId,
      'title': 'System Design & High Availability',
      'description': 'Core architectural principles, distributed consensus, CAP theorem, and caching.',
      'category': 'Architecture',
      'createdAt': nowUtc.toIso8601String(),
      'updatedAt': nowUtc.toIso8601String(),
      'isSynced': 0,
      'isDeleted': 0,
    });

    final initialCards = [
      {
        'id': uuid.v4(),
        'deckId': deckId,
        'question': 'What does the CAP Theorem state for distributed data stores?',
        'answer': 'A distributed system can guarantee at most two out of three: Consistency, Availability, and Partition Tolerance.',
        'aiExplanation': 'In the presence of a network partition (P), the system must choose between cancelling the operation and decreasing availability (C) or continuing the operation and risking inconsistency (A).',
        'tags': '["SystemDesign", "CAP", "Distributed"]',
        'easeFactor': 2.5,
        'interval': 0,
        'repetitions': 0,
        'nextReviewDate': nowUtc.subtract(const Duration(minutes: 5)).toIso8601String(),
        'isStarredForNotification': 1,
        'updatedAt': nowUtc.toIso8601String(),
        'isSynced': 0,
        'isDeleted': 0,
      },
      {
        'id': uuid.v4(),
        'deckId': deckId,
        'question': 'Explain the difference between Cache-Aside and Write-Through caching patterns.',
        'answer': 'Cache-Aside: The application checks cache, falls back to DB on miss, then writes to cache. Write-Through: The app writes to cache, which synchronously writes to the DB.',
        'aiExplanation': 'Cache-Aside is resilient to cache failure, whereas Write-Through ensures cache and storage consistency at the cost of higher write latency.',
        'tags': '["Caching", "Backend", "Performance"]',
        'easeFactor': 2.5,
        'interval': 0,
        'repetitions': 0,
        'nextReviewDate': nowUtc.subtract(const Duration(minutes: 2)).toIso8601String(),
        'isStarredForNotification': 0,
        'updatedAt': nowUtc.toIso8601String(),
        'isSynced': 0,
        'isDeleted': 0,
      },
      {
        'id': uuid.v4(),
        'deckId': deckId,
        'question': 'What is Raft Consensus and what are its three fundamental states?',
        'answer': 'Raft is a consensus algorithm designed for leader election, log replication, and safety. Node states: Follower, Candidate, and Leader.',
        'aiExplanation': 'Raft decomposes consensus into explicit leader election, log replication, and safety constraints to make distributed state machines understandable and deterministic.',
        'tags': '["Consensus", "Raft", "DistributedSystems"]',
        'easeFactor': 2.5,
        'interval': 25,
        'repetitions': 4,
        'nextReviewDate': nowUtc.add(const Duration(days: 21)).toIso8601String(),
        'isStarredForNotification': 1,
        'updatedAt': nowUtc.toIso8601String(),
        'isSynced': 0,
        'isDeleted': 0,
      }
    ];

    for (final card in initialCards) {
      await db.insert('flashcards', card);
    }
  }

  // --- Deck Operations (Offline-First: marks isSynced = 0 & UTC updatedAt) ---

  Future<void> insertDeck(Deck deck) async {
    final db = await database;
    final nowUtc = DateTime.now().toUtc();
    final prepared = deck.copyWith(
      createdAt: deck.createdAt.toUtc(),
      updatedAt: nowUtc,
      isSynced: false,
    );
    await db.insert('decks', prepared.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateDeck(Deck deck) async {
    final db = await database;
    final prepared = deck.copyWith(
      updatedAt: DateTime.now().toUtc(),
      isSynced: false,
    );
    await db.update(
      'decks',
      prepared.toMap(),
      where: 'id = ?',
      whereArgs: [deck.id],
    );
  }

  Future<void> deleteDeck(String deckId) async {
    final db = await database;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'decks',
        {'isDeleted': 1, 'isSynced': 0, 'updatedAt': nowIso},
        where: 'id = ?',
        whereArgs: [deckId],
      );
      await txn.update(
        'flashcards',
        {'isDeleted': 1, 'isSynced': 0, 'updatedAt': nowIso},
        where: 'deckId = ?',
        whereArgs: [deckId],
      );
    });
  }

  Future<List<Deck>> getAllDecks() async {
    final db = await database;
    final maps = await db.query(
      'decks',
      where: 'isDeleted = 0',
      orderBy: 'updatedAt DESC',
    );
    return maps.map((e) => Deck.fromMap(e)).toList();
  }

  Future<Deck?> getDeckById(String id) async {
    final db = await database;
    final maps = await db.query(
      'decks',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Deck.fromMap(maps.first);
    }
    return null;
  }

  Future<DeckStats> getDeckStats(String deckId) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();

    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flashcards WHERE deckId = ? AND isDeleted = 0',
      [deckId],
    );
    final dueResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flashcards WHERE deckId = ? AND isDeleted = 0 AND nextReviewDate <= ?',
      [deckId, nowIso],
    );
    final masteredResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flashcards WHERE deckId = ? AND isDeleted = 0 AND interval >= 21',
      [deckId],
    );

    return DeckStats(
      totalCards: (totalResult.first['count'] as num?)?.toInt() ?? 0,
      dueCards: (dueResult.first['count'] as num?)?.toInt() ?? 0,
      masteredCards: (masteredResult.first['count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, DeckStats>> getAllDeckStats() async {
    final decks = await getAllDecks();
    final Map<String, DeckStats> statsMap = {};
    for (final deck in decks) {
      statsMap[deck.id] = await getDeckStats(deck.id);
    }
    return statsMap;
  }

  // --- Flashcard Operations (Offline-First: marks isSynced = 0 & UTC updatedAt) ---

  Future<void> insertFlashcard(Flashcard card) async {
    final db = await database;
    final prepared = card.copyWith(
      updatedAt: DateTime.now().toUtc(),
      isSynced: false,
    );
    await db.insert('flashcards', prepared.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateFlashcard(Flashcard card) async {
    final db = await database;
    final prepared = card.copyWith(
      updatedAt: DateTime.now().toUtc(),
      isSynced: false,
    );
    await db.update(
      'flashcards',
      prepared.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<void> deleteFlashcard(String cardId) async {
    final db = await database;
    await db.update(
      'flashcards',
      {
        'isDeleted': 1,
        'isSynced': 0,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }

  Future<List<Flashcard>> getFlashcardsForDeck(String deckId) async {
    final db = await database;
    final maps = await db.query(
      'flashcards',
      where: 'deckId = ? AND isDeleted = 0',
      whereArgs: [deckId],
      orderBy: 'updatedAt DESC',
    );
    return maps.map((e) => Flashcard.fromMap(e)).toList();
  }

  Future<List<Flashcard>> getDueFlashcardsForDeck(String deckId) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final maps = await db.query(
      'flashcards',
      where: 'deckId = ? AND isDeleted = 0 AND nextReviewDate <= ?',
      whereArgs: [deckId, nowIso],
      orderBy: 'nextReviewDate ASC',
    );
    return maps.map((e) => Flashcard.fromMap(e)).toList();
  }

  Future<int> getTotalDueCount() async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flashcards WHERE isDeleted = 0 AND nextReviewDate <= ?',
      [nowIso],
    );
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> toggleStarredForNotification(String cardId, bool isStarred) async {
    final db = await database;
    await db.update(
      'flashcards',
      {
        'isStarredForNotification': isStarred ? 1 : 0,
        'isSynced': 0,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }

  Future<List<Flashcard>> getStarredCards() async {
    final db = await database;
    final maps = await db.query(
      'flashcards',
      where: 'isStarredForNotification = 1 AND isDeleted = 0',
      orderBy: 'updatedAt DESC',
    );
    return maps.map((e) => Flashcard.fromMap(e)).toList();
  }

  // --- Cloud Synchronization & Last-Write-Wins (LWW) Queries ---

  Future<List<Deck>> getUnsyncedDecks() async {
    final db = await database;
    final maps = await db.query('decks', where: 'isSynced = 0');
    return maps.map((e) => Deck.fromMap(e)).toList();
  }

  Future<List<Flashcard>> getUnsyncedFlashcards() async {
    final db = await database;
    final maps = await db.query('flashcards', where: 'isSynced = 0');
    return maps.map((e) => Flashcard.fromMap(e)).toList();
  }

  Future<int> getUnsyncedCount() async {
    final db = await database;
    final deckRes = await db.rawQuery('SELECT COUNT(*) as count FROM decks WHERE isSynced = 0');
    final cardRes = await db.rawQuery('SELECT COUNT(*) as count FROM flashcards WHERE isSynced = 0');
    final dCount = (deckRes.first['count'] as num?)?.toInt() ?? 0;
    final cCount = (cardRes.first['count'] as num?)?.toInt() ?? 0;
    return dCount + cCount;
  }

  Future<Deck?> getDeckByIdIncludeDeleted(String id) async {
    final db = await database;
    final maps = await db.query(
      'decks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Deck.fromMap(maps.first);
    }
    return null;
  }

  Future<Flashcard?> getFlashcardByIdIncludeDeleted(String id) async {
    final db = await database;
    final maps = await db.query(
      'flashcards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Flashcard.fromMap(maps.first);
    }
    return null;
  }

  Future<void> upsertDeckFromCloud(Deck cloudDeck) async {
    final db = await database;
    final syncedDeck = cloudDeck.copyWith(isSynced: true);
    await db.insert(
      'decks',
      syncedDeck.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertFlashcardFromCloud(Flashcard cloudCard) async {
    final db = await database;
    final syncedCard = cloudCard.copyWith(isSynced: true);
    await db.insert(
      'flashcards',
      syncedCard.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markDeckSynced(String id) async {
    final db = await database;
    await db.update(
      'decks',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFlashcardSynced(String id) async {
    final db = await database;
    await db.update(
      'flashcards',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks all local guest records as unsynced so signing into an account merges them seamlessly.
  Future<void> prepareGuestRecordsForAccountMerge() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('decks', {'isSynced': 0});
      await txn.update('flashcards', {'isSynced': 0});
    });
  }
}