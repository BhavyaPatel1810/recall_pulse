import os
import re
import subprocess

print("--- RecallPulse Auto-Setup Shuru Ho Raha Hai ---")

# 1. Packages install karein
print("\n1. Packages install ho rahe hain...")
subprocess.run([
    "flutter", "pub", "add",
    "sqflite", "path", "google_generative_ai",
    "flutter_local_notifications", "timezone", "workmanager",
    "uuid", "intl"
], check=True)

# 2. Folders create karein
print("\n2. Project folders create ho rahe hain...")
for folder in ['lib/models', 'lib/services', 'lib/logic', 'lib/screens']:
    os.makedirs(folder, exist_ok=True)

# 3. Dart Files Content
files = {}

files['lib/models/flashcard.dart'] = r'''class Flashcard {
  final String id;
  final String deckId;
  final String question;
  final String answer;
  final String explanation;
  final int repetitions;
  final double easeFactor;
  final int interval;
  final DateTime nextReviewDate;
  final DateTime createdAt;

  Flashcard({
    required this.id,
    required this.deckId,
    required this.question,
    required this.answer,
    this.explanation = '',
    this.repetitions = 0,
    this.easeFactor = 2.5,
    this.interval = 1,
    required this.nextReviewDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deck_id': deckId,
      'question': question,
      'answer': answer,
      'explanation': explanation,
      'repetitions': repetitions,
      'ease_factor': easeFactor,
      'interval': interval,
      'next_review_date': nextReviewDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Flashcard.fromMap(Map<String, dynamic> map) {
    return Flashcard(
      id: map['id'],
      deckId: map['deck_id'],
      question: map['question'],
      answer: map['answer'],
      explanation: map['explanation'] ?? '',
      repetitions: map['repetitions'] ?? 0,
      easeFactor: map['ease_factor']?.toDouble() ?? 2.5,
      interval: map['interval'] ?? 1,
      nextReviewDate: DateTime.parse(map['next_review_date']),
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Flashcard copyWith({
    String? question,
    String? answer,
    String? explanation,
    int? repetitions,
    double? easeFactor,
    int? interval,
    DateTime? nextReviewDate,
  }) {
    return Flashcard(
      id: id,
      deckId: deckId,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      explanation: explanation ?? this.explanation,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      createdAt: createdAt,
    );
  }
}
'''

files['lib/models/deck.dart'] = r'''class Deck {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;

  Deck({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Deck.fromMap(Map<String, dynamic> map) {
    return Deck(
      id: map['id'],
      title: map['title'],
      description: map['description'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
'''

files['lib/logic/spaced_repetition.dart'] = r'''enum ReviewRating { again, hard, good, easy }

class SpacedRepetitionEngine {
  static Map<String, dynamic> calculateNextReview({
    required int currentRepetitions,
    required double currentEaseFactor,
    required int currentInterval,
    required ReviewRating rating,
  }) {
    int quality;
    switch (rating) {
      case ReviewRating.again: quality = 1; break;
      case ReviewRating.hard: quality = 3; break;
      case ReviewRating.good: quality = 4; break;
      case ReviewRating.easy: quality = 5; break;
    }

    int nextRepetitions = currentRepetitions;
    int nextInterval = currentInterval;
    double nextEaseFactor = currentEaseFactor;

    if (quality >= 3) {
      if (currentRepetitions == 0) {
        nextInterval = 1;
      } else if (currentRepetitions == 1) {
        nextInterval = 6;
      } else {
        nextInterval = (currentInterval * currentEaseFactor).round();
      }
      nextRepetitions += 1;
    } else {
      nextRepetitions = 0;
      nextInterval = 1;
    }

    nextEaseFactor = currentEaseFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (nextEaseFactor < 1.3) nextEaseFactor = 1.3;

    final nextReviewDate = DateTime.now().add(Duration(days: nextInterval));

    return {
      'repetitions': nextRepetitions,
      'easeFactor': nextEaseFactor,
      'interval': nextInterval,
      'nextReviewDate': nextReviewDate,
    };
  }
}
'''

files['lib/services/gemini_service.dart'] = r'''import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:uuid/uuid.dart';
import '../models/flashcard.dart';

class GeminiService {
  final String apiKey;
  late final GenerativeModel _model;

  GeminiService({required this.apiKey}) {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.2,
      ),
    );
  }

  Future<List<Flashcard>> generateCardsFromText({
    required String rawText,
    required String deckId,
  }) async {
    final prompt = 'Tum ek expert flashcard creator ho. Niche diye gaye study material ko padho aur high-yield flashcards create karo active recall ke liye.\n'
        'Output sirf valid JSON array hona chahiye format me:\n'
        '[\n'
        '  {\n'
        '    "question": "Clear and direct question",\n'
        '    "answer": "Concise and accurate answer",\n'
        '    "explanation": "Short conceptual explanation or context"\n'
        '  }\n'
        ']\n\n'
        'Study Material:\n' + rawText;

    final content = [Content.text(prompt)];
    final response = await _model.generateContent(content);
    final responseText = response.text;

    if (responseText == null || responseText.isEmpty) return [];

    try {
      final List<dynamic> parsedList = jsonDecode(responseText);
      final uuid = const Uuid();
      final now = DateTime.now();

      return parsedList.map((item) {
        return Flashcard(
          id: uuid.v4(),
          deckId: deckId,
          question: item['question'] ?? 'No Question',
          answer: item['answer'] ?? 'No Answer',
          explanation: item['explanation'] ?? '',
          repetitions: 0,
          easeFactor: 2.5,
          interval: 1,
          nextReviewDate: now,
          createdAt: now,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String> resolveDoubt({
    required String cardQuestion,
    required String cardAnswer,
    required String userQuery,
  }) async {
    final doubtModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    final prompt = 'Context:\n'
        'Flashcard Question: ' + cardQuestion + '\n'
        'Flashcard Answer: ' + cardAnswer + '\n\n'
        'Student Doubt: ' + userQuery + '\n\n'
        'Direct, crisp aur conceptual clarification do.';

    final response = await doubtModel.generateContent([Content.text(prompt)]);
    return response.text ?? 'Koi explanation generate nahi ho saka.';
  }
}
'''

files['lib/services/database_helper.dart'] = r'''import 'package:sqflite/sqflite.dart';
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
'''

files['lib/services/notification_service.dart'] = r'''import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'database_helper.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
  }

  Future<void> triggerRandomDueCardNotification() async {
    final dueCards = await DatabaseHelper.instance.getDueFlashcards();
    if (dueCards.isEmpty) return;

    final randomCard = dueCards[Random().nextInt(dueCards.length)];

    final BigTextStyleInformation bigTextStyleInformation = BigTextStyleInformation(
      randomCard.question,
      htmlFormatBigText: false,
      contentTitle: 'RecallPulse: Quick Revision!',
      summaryText: 'Tap karke answer check karein',
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'recall_pulse_channel',
      'Flashcard Nudges',
      channelDescription: 'Spaced repetition revision popups',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: bigTextStyleInformation,
    );

    final NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      'RecallPulse: Quick Revision!',
      randomCard.question,
      notificationDetails,
      payload: randomCard.id,
    );
  }
}
'''

files['lib/screens/review_screen.dart'] = r'''import 'package:flutter/material.dart';
import '../models/flashcard.dart';
import '../logic/spaced_repetition.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';

class ReviewScreen extends StatefulWidget {
  final List<Flashcard> cards;
  final String geminiApiKey;

  const ReviewScreen({super.key, required this.cards, required this.geminiApiKey});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _currentIndex = 0;
  bool _showAnswer = false;
  late final GeminiService _geminiService;
  final TextEditingController _doubtController = TextEditingController();
  bool _isAiThinking = false;
  String _aiResponse = '';

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService(apiKey: widget.geminiApiKey);
  }

  void _handleRating(ReviewRating rating) async {
    final currentCard = widget.cards[_currentIndex];
    final updatedMetrics = SpacedRepetitionEngine.calculateNextReview(
      currentRepetitions: currentCard.repetitions,
      currentEaseFactor: currentCard.easeFactor,
      currentInterval: currentCard.interval,
      rating: rating,
    );

    final updatedCard = currentCard.copyWith(
      repetitions: updatedMetrics['repetitions'],
      easeFactor: updatedMetrics['easeFactor'],
      interval: updatedMetrics['interval'],
      nextReviewDate: updatedMetrics['nextReviewDate'],
    );

    await DatabaseHelper.instance.updateFlashcard(updatedCard);

    if (_currentIndex + 1 < widget.cards.length) {
      setState(() {
        _currentIndex++;
        _showAnswer = false;
        _aiResponse = '';
      });
    } else {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revision complete!')),
        );
      }
    }
  }

  void _openAiDoubtDrawer(Flashcard card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gemini In-App Tutor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  const SizedBox(height: 10),
                  Text('Q: ' + card.question, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 12),
                  if (_aiResponse.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                      child: Text(_aiResponse, style: const TextStyle(color: Colors.white)),
                    ),
                  if (_isAiThinking)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _doubtController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Apna doubt likhein...',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            filled: true,
                            fillColor: Colors.grey[800],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blueAccent),
                        onPressed: () async {
                          if (_doubtController.text.trim().isEmpty) return;
                          setSheetState(() => _isAiThinking = true);
                          final reply = await _geminiService.resolveDoubt(
                            cardQuestion: card.question,
                            cardAnswer: card.answer,
                            userQuery: _doubtController.text.trim(),
                          );
                          setSheetState(() {
                            _aiResponse = reply;
                            _isAiThinking = false;
                          });
                          _doubtController.clear();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: Text('Review ke liye koi card nahi hai!')),
      );
    }

    final card = widget.cards[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Card ${(_currentIndex + 1)}/${widget.cards.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.blueAccent),
            tooltip: 'Ask Gemini Doubt',
            onPressed: () => _openAiDoubtDrawer(card),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showAnswer = !_showAnswer),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(card.question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                      if (_showAnswer) ...[
                        const Divider(height: 40, color: Colors.grey),
                        Text(card.answer, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.lightGreenAccent)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_showAnswer)
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.blueAccent),
                onPressed: () => setState(() => _showAnswer = true),
                child: const Text('Answer Dekho', style: TextStyle(fontSize: 16, color: Colors.white)),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ratingBtn('Again', Colors.redAccent, () => _handleRating(ReviewRating.again)),
                  _ratingBtn('Hard', Colors.orangeAccent, () => _handleRating(ReviewRating.hard)),
                  _ratingBtn('Good', Colors.blueAccent, () => _handleRating(ReviewRating.good)),
                  _ratingBtn('Easy', Colors.greenAccent, () => _handleRating(ReviewRating.easy)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _ratingBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    );
  }
}
'''

files['lib/screens/ai_card_creator_screen.dart'] = r'''import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';

class AiCardCreatorScreen extends StatefulWidget {
  final List<Deck> decks;
  final String geminiApiKey;

  const AiCardCreatorScreen({super.key, required this.decks, required this.geminiApiKey});

  @override
  State<AiCardCreatorScreen> createState() => _AiCardCreatorScreenState();
}

class _AiCardCreatorScreenState extends State<AiCardCreatorScreen> {
  final TextEditingController _textController = TextEditingController();
  late String _selectedDeckId;
  late final GeminiService _geminiService;
  bool _isGenerating = false;
  List<Flashcard> _generatedCards = [];

  @override
  void initState() {
    super.initState();
    _selectedDeckId = widget.decks.first.id;
    _geminiService = GeminiService(apiKey: widget.geminiApiKey);
  }

  void _generateCards() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _generatedCards = [];
    });

    try {
      final cards = await _geminiService.generateCardsFromText(
        rawText: text,
        deckId: _selectedDeckId,
      );
      setState(() => _generatedCards = cards);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _saveCards() async {
    if (_generatedCards.isEmpty) return;
    await DatabaseHelper.instance.insertMultipleFlashcards(_generatedCards);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_generatedCards.length} cards save ho gaye!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Gemini Flashcard Creator'),
        actions: [
          if (_generatedCards.isNotEmpty)
            TextButton.icon(
              onPressed: _saveCards,
              icon: const Icon(Icons.check, color: Colors.lightGreenAccent),
              label: const Text('Save All', style: TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButton<String>(
              value: _selectedDeckId,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              items: widget.decks.map((deck) {
                return DropdownMenuItem<String>(value: deck.id, child: Text(deck.title));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedDeckId = val);
              },
            ),
            const SizedBox(height: 12),
            if (_generatedCards.isEmpty) ...[
              Expanded(
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Apne notes ya topic text yahan paste karein...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.indigoAccent),
                onPressed: _isGenerating ? null : _generateCards,
                icon: _isGenerating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                label: Text(_isGenerating ? 'Cards ban rahe hain...' : 'Flashcards Generate Karein'),
              ),
            ] else ...[
              Expanded(
                child: ListView.builder(
                  itemCount: _generatedCards.length,
                  itemBuilder: (context, index) {
                    final card = _generatedCards[index];
                    return Card(
                      color: const Color(0xFF1E1E1E),
                      child: ListTile(
                        title: Text('Q: ' + card.question, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('A: ' + card.answer, style: const TextStyle(color: Colors.lightGreenAccent)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => setState(() => _generatedCards.removeAt(index)),
                        ),
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.green),
                onPressed: _saveCards,
                child: Text('${_generatedCards.length} Cards Save Karein'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
'''

files['lib/screens/home_screen.dart'] = r'''import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import 'ai_card_creator_screen.dart';
import 'review_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Deck> _decks = [];
  Map<String, int> _deckDueCounts = {};
  Map<String, int> _deckTotalCounts = {};
  bool _isLoading = true;
  String _geminiApiKey = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final decks = await DatabaseHelper.instance.getAllDecks();
    final Map<String, int> dueCounts = {};
    final Map<String, int> totalCounts = {};
    final now = DateTime.now();

    for (var deck in decks) {
      final cards = await DatabaseHelper.instance.getCardsByDeck(deck.id);
      totalCounts[deck.id] = cards.length;
      dueCounts[deck.id] = cards.where((c) => c.nextReviewDate.isBefore(now) || c.nextReviewDate.isAtSameMomentAs(now)).length;
    }

    setState(() {
      _decks = decks;
      _deckDueCounts = dueCounts;
      _deckTotalCounts = totalCounts;
      _isLoading = false;
    });
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: _geminiApiKey);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Gemini API Key Set Karein', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'AI Studio API Key', hintStyle: TextStyle(color: Colors.grey)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              setState(() => _geminiApiKey = controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _createNewDeckDialog() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Naya Deck', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: titleController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Deck Title', hintStyle: TextStyle(color: Colors.grey)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.trim().isEmpty) return;
              await DatabaseHelper.instance.insertDeck(
                Deck(id: const Uuid().v4(), title: titleController.text.trim(), createdAt: DateTime.now()),
              );
              Navigator.pop(context);
              _loadData();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _startReview(Deck deck) async {
    final cards = await DatabaseHelper.instance.getCardsByDeck(deck.id);
    if (cards.isEmpty) return;
    if (_geminiApiKey.isEmpty) {
      _showApiKeyDialog();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewScreen(cards: cards, geminiApiKey: _geminiApiKey),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('RecallPulse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Colors.orangeAccent),
            tooltip: 'Trigger Notification Popup',
            onPressed: () => NotificationService().triggerRandomDueCardNotification(),
          ),
          IconButton(
            icon: Icon(Icons.key, color: _geminiApiKey.isEmpty ? Colors.redAccent : Colors.lightGreenAccent),
            onPressed: _showApiKeyDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _decks.length,
              itemBuilder: (context, index) {
                final deck = _decks[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  child: ListTile(
                    title: Text(deck.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('Total: ${_deckTotalCounts[deck.id] ?? 0} | Due: ${_deckDueCounts[deck.id] ?? 0}', style: const TextStyle(color: Colors.grey)),
                    trailing: IconButton(icon: const Icon(Icons.play_arrow, color: Colors.blueAccent), onPressed: () => _startReview(deck)),
                  ),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'ai',
            backgroundColor: Colors.indigoAccent,
            onPressed: () async {
              if (_decks.isEmpty) {
                _createNewDeckDialog();
                return;
              }
              if (_geminiApiKey.isEmpty) {
                _showApiKeyDialog();
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AiCardCreatorScreen(decks: _decks, geminiApiKey: _geminiApiKey)),
              );
              _loadData();
            },
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add_deck',
            backgroundColor: Colors.blueAccent,
            onPressed: _createNewDeckDialog,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
'''

files['lib/main.dart'] = r'''import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.triggerRandomDueCardNotification();
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  await notificationService.init();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    'recall_pulse_nudges',
    'fetchDueCardTask',
    frequency: const Duration(hours: 2),
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HomeScreen(),
  ));
}
'''

print("\n3. Files generate ho rahi hain...")
for path, code in files.items():
    with open(path, 'w', encoding='utf-8') as f:
        f.write(code)
    print(f"  [OK] {path}")

# 4. Android Permissions check
manifest = 'android/app/src/main/AndroidManifest.xml'
if os.path.exists(manifest):
    with open(manifest, 'r', encoding='utf-8') as f:
        content = f.read()
    if 'android.permission.POST_NOTIFICATIONS' not in content:
        perms = (
            '    <uses-permission android:name="android.permission.INTERNET"/>\n'
            '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
            '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
            '    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n'
        )
        content = content.replace('<application', perms + '    <application', 1)
        with open(manifest, 'w', encoding='utf-8') as f:
            f.write(content)
        print("\n4. Android Permissions add ho gayi hain.")

# 5. MinSdkVersion Update
kts_file = 'android/app/build.gradle.kts'
gradle_file = 'android/app/build.gradle'

if os.path.exists(kts_file):
    with open(kts_file, 'r', encoding='utf-8') as f:
        c = f.read()
    c = re.sub(r'minSdk\s*=\s*.*', 'minSdk = 21', c)
    with open(kts_file, 'w', encoding='utf-8') as f:
        f.write(c)
    print("5. build.gradle.kts mein minSdk = 21 update ho gaya.")
elif os.path.exists(gradle_file):
    with open(gradle_file, 'r', encoding='utf-8') as f:
        c = f.read()
    c = re.sub(r'minSdkVersion\s+.*', 'minSdkVersion 21', c)
    c = re.sub(r'minSdk\s*=\s*.*', 'minSdk = 21', c)
    with open(gradle_file, 'w', encoding='utf-8') as f:
        f.write(c)
    print("5. build.gradle mein minSdkVersion 21 update ho gaya.")

print("\n--- Poora Setup Safalta Se Ho Gaya! ---")
