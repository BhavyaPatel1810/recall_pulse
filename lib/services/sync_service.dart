import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import 'auth_service.dart';
import 'database_helper.dart';

enum SyncStatusState {
  synced,
  unsyncedChanges,
  syncing,
  offlineOrGuest,
  error,
}

class SyncReport {
  final bool success;
  final int pushedDecks;
  final int pushedCards;
  final int pulledDecks;
  final int pulledCards;
  final String message;

  const SyncReport({
    required this.success,
    this.pushedDecks = 0,
    this.pushedCards = 0,
    this.pulledDecks = 0,
    this.pulledCards = 0,
    required this.message,
  });
}

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  static const String _prefLastSyncTime = 'pulse_last_sync_utc_iso';

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final StreamController<SyncStatusState> _statusController =
      StreamController<SyncStatusState>.broadcast();
  Stream<SyncStatusState> get statusStream => _statusController.stream;

  /// Evaluates current sync badge state for the HomeScreen AppBar.
  Future<SyncStatusState> evaluateCurrentSyncState() async {
    if (_isSyncing) return SyncStatusState.syncing;
    if (!AuthService.instance.isLoggedIn) {
      final unsynced = await DatabaseHelper.instance.getUnsyncedCount();
      return unsynced > 0 ? SyncStatusState.unsyncedChanges : SyncStatusState.offlineOrGuest;
    }

    final unsyncedCount = await DatabaseHelper.instance.getUnsyncedCount();
    final state = unsyncedCount > 0 ? SyncStatusState.unsyncedChanges : SyncStatusState.synced;
    _statusController.add(state);
    return state;
  }

  Future<DateTime?> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefLastSyncTime);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// Executes the full Bi-Directional Sync (Push + Pull + Deterministic LWW Conflict Resolution).
  Future<SyncReport> syncAllData() async {
    if (_isSyncing) {
      return const SyncReport(
        success: false,
        message: 'A synchronization cycle is already in progress.',
      );
    }

    final client = AuthService.instance.client;
    final user = AuthService.instance.currentUser;
    if (client == null || user == null) {
      await evaluateCurrentSyncState();
      return const SyncReport(
        success: false,
        message: 'Running in Offline Guest Mode. Sign in to sync with Cloud.',
      );
    }

    _isSyncing = true;
    _statusController.add(SyncStatusState.syncing);

    final syncCycleStartUtc = DateTime.now().toUtc();
    int pushedDecksCount = 0;
    int pushedCardsCount = 0;
    int pulledDecksCount = 0;
    int pulledCardsCount = 0;

    try {
      final lastSyncUtc = await getLastSyncTimestamp();
      final userId = user.id;

      // ------------------------------------------------------------------
      // STEP 1: FETCH REMOTE DELTAS FOR DETERMINISTIC LWW COMPARISON
      // ------------------------------------------------------------------
      var remoteDecksQuery = client.from('decks').select().eq('user_id', userId);
      var remoteCardsQuery = client.from('flashcards').select().eq('user_id', userId);

      if (lastSyncUtc != null) {
        final isoFilter = lastSyncUtc.toIso8601String();
        remoteDecksQuery = remoteDecksQuery.gt('updated_at', isoFilter);
        remoteCardsQuery = remoteCardsQuery.gt('updated_at', isoFilter);
      }

      final List<dynamic> remoteDeckRows = await remoteDecksQuery;
      final List<dynamic> remoteCardRows = await remoteCardsQuery;

      final Map<String, Deck> remoteDecksMap = {};
      for (final row in remoteDeckRows.whereType<Map<String, dynamic>>()) {
        final deck = _deckFromSupabaseRow(row);
        remoteDecksMap[deck.id] = deck;
      }

      final Map<String, Flashcard> remoteCardsMap = {};
      for (final row in remoteCardRows.whereType<Map<String, dynamic>>()) {
        final card = _flashcardFromSupabaseRow(row);
        remoteCardsMap[card.id] = card;
      }

      // ------------------------------------------------------------------
      // STEP 2: PUSH PHASE (Local Unsynced -> Cloud, respecting LWW)
      // ------------------------------------------------------------------
      final unsyncedDecks = await DatabaseHelper.instance.getUnsyncedDecks();
      final List<Map<String, dynamic>> decksToUpsert = [];
      final List<String> deckIdsPushed = [];

      for (final localDeck in unsyncedDecks) {
        final remoteComplement = remoteDecksMap[localDeck.id];
        if (remoteComplement == null ||
            !remoteComplement.updatedAt.toUtc().isAfter(localDeck.updatedAt.toUtc())) {
          // Local wins or does not exist remotely
          decksToUpsert.add(_deckToSupabaseRow(localDeck, userId));
          deckIdsPushed.add(localDeck.id);
          // Remove from pull map so we don't overwrite what we just pushed
          remoteDecksMap.remove(localDeck.id);
        }
      }

      if (decksToUpsert.isNotEmpty) {
        await client.from('decks').upsert(decksToUpsert, onConflict: 'id');
        for (final id in deckIdsPushed) {
          await DatabaseHelper.instance.markDeckSynced(id);
        }
        pushedDecksCount = decksToUpsert.length;
      }

      // Apply any remote decks where Remote won LWW (or brand new remote decks) BEFORE pushing flashcards
      // so foreign key constraints on deck_id are always satisfied.
      for (final remoteDeck in remoteDecksMap.values) {
        final localDeck = await DatabaseHelper.instance.getDeckByIdIncludeDeleted(remoteDeck.id);
        if (localDeck == null ||
            remoteDeck.updatedAt.toUtc().isAfter(localDeck.updatedAt.toUtc())) {
          await DatabaseHelper.instance.upsertDeckFromCloud(remoteDeck);
          pulledDecksCount++;
        }
      }

      // Now push unsynced flashcards where Local wins LWW
      final unsyncedCards = await DatabaseHelper.instance.getUnsyncedFlashcards();
      final List<Map<String, dynamic>> cardsToUpsert = [];
      final List<String> cardIdsPushed = [];

      for (final localCard in unsyncedCards) {
        final remoteComplement = remoteCardsMap[localCard.id];
        if (remoteComplement == null ||
            !remoteComplement.updatedAt.toUtc().isAfter(localCard.updatedAt.toUtc())) {
          cardsToUpsert.add(_flashcardToSupabaseRow(localCard, userId));
          cardIdsPushed.add(localCard.id);
          remoteCardsMap.remove(localCard.id);
        }
      }

      if (cardsToUpsert.isNotEmpty) {
        await client.from('flashcards').upsert(cardsToUpsert, onConflict: 'id');
        for (final id in cardIdsPushed) {
          await DatabaseHelper.instance.markFlashcardSynced(id);
        }
        pushedCardsCount = cardsToUpsert.length;
      }

      // ------------------------------------------------------------------
      // STEP 3: PULL PHASE (Apply Remaining Remote Flashcards where Remote wins LWW)
      // ------------------------------------------------------------------
      for (final remoteCard in remoteCardsMap.values) {
        final localCard =
            await DatabaseHelper.instance.getFlashcardByIdIncludeDeleted(remoteCard.id);
        if (localCard == null ||
            remoteCard.updatedAt.toUtc().isAfter(localCard.updatedAt.toUtc())) {
          await DatabaseHelper.instance.upsertFlashcardFromCloud(remoteCard);
          pulledCardsCount++;
        }
      }

      // ------------------------------------------------------------------
      // STEP 4: COMMIT SYNC TIMESTAMP
      // ------------------------------------------------------------------
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastSyncTime, syncCycleStartUtc.toIso8601String());

      _isSyncing = false;
      await evaluateCurrentSyncState();

      return SyncReport(
        success: true,
        pushedDecks: pushedDecksCount,
        pushedCards: pushedCardsCount,
        pulledDecks: pulledDecksCount,
        pulledCards: pulledCardsCount,
        message:
            'Sync complete (↑${pushedDecksCount + pushedCardsCount} pushed, ↓${pulledDecksCount + pulledCardsCount} pulled).',
      );
    } catch (e) {
      debugPrint('SyncService error: $e');
      _isSyncing = false;
      _statusController.add(SyncStatusState.error);
      return SyncReport(
        success: false,
        message: 'Sync error: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }
  }

  // --- Data Mappers (SQLite CamelCase <-> Supabase PostgreSQL snake_case) ---

  Map<String, dynamic> _deckToSupabaseRow(Deck deck, String userId) {
    return {
      'id': deck.id,
      'user_id': userId,
      'title': deck.title,
      'description': deck.description,
      'category': deck.category,
      'created_at': deck.createdAt.toUtc().toIso8601String(),
      'updated_at': deck.updatedAt.toUtc().toIso8601String(),
      'is_deleted': deck.isDeleted,
    };
  }

  Deck _deckFromSupabaseRow(Map<String, dynamic> row) {
    return Deck(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      category: row['category'] as String? ?? 'General',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      isSynced: true,
      isDeleted: (row['is_deleted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> _flashcardToSupabaseRow(Flashcard card, String userId) {
    return {
      'id': card.id,
      'user_id': userId,
      'deck_id': card.deckId,
      'question': card.question,
      'answer': card.answer,
      'ai_explanation': card.aiExplanation,
      'tags': card.tags,
      'ease_factor': card.easeFactor,
      'interval': card.interval,
      'repetitions': card.repetitions,
      'next_review_date': card.nextReviewDate.toUtc().toIso8601String(),
      'is_starred_for_notification': card.isStarredForNotification,
      'updated_at': card.updatedAt.toUtc().toIso8601String(),
      'is_deleted': card.isDeleted,
    };
  }

  Flashcard _flashcardFromSupabaseRow(Map<String, dynamic> row) {
    List<String> parsedTags = [];
    if (row['tags'] is List) {
      parsedTags = (row['tags'] as List).map((e) => e.toString()).toList();
    }

    return Flashcard(
      id: row['id'] as String,
      deckId: row['deck_id'] as String,
      question: row['question'] as String? ?? '',
      answer: row['answer'] as String? ?? '',
      aiExplanation: row['ai_explanation'] as String? ?? '',
      tags: parsedTags,
      easeFactor: (row['ease_factor'] as num?)?.toDouble() ?? 2.5,
      interval: (row['interval'] as num?)?.toInt() ?? 0,
      repetitions: (row['repetitions'] as num?)?.toInt() ?? 0,
      nextReviewDate: DateTime.tryParse(row['next_review_date'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      isStarredForNotification: (row['is_starred_for_notification'] as bool?) ?? false,
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      isSynced: true,
      isDeleted: (row['is_deleted'] as bool?) ?? false,
    );
  }
}