import 'package:flutter/material.dart';
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
