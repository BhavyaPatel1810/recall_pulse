import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../theme/pulse_colors.dart';
import '../widgets/deck_card.dart';
import '../widgets/pulse_fab.dart';
import '../widgets/stat_pill.dart';
import 'ai_card_creator_screen.dart';
import 'review_screen.dart';

class _DeckSnapshot {
  const _DeckSnapshot({
    required this.deck,
    required this.cards,
  });

  final Deck deck;
  final List<Flashcard> cards;

  int get total => cards.length;

  int dueCount(DateTime dayEnd) => cards.where((card) => _isDue(card, dayEnd)).length;

  int get mastered => cards.where((card) => card.repetitions >= 1).length;
}

bool _isDue(Flashcard card, DateTime dayEnd) => !card.nextReviewDate.isAfter(dayEnd);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_DeckSnapshot> _decks = [];
  bool _isLoading = true;
  String _geminiApiKey = '';

  static const _accents = [
    PulseColors.cyan,
    Color(0xFF22D3EE),
    PulseColors.indigo,
    Color(0xFF818CF8),
    Color(0xFF38BDF8),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  DateTime get _dayEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final decks = await DatabaseHelper.instance.getAllDecks();
    final snapshots = <_DeckSnapshot>[];
    for (final deck in decks) {
      final cards = await DatabaseHelper.instance.getCardsByDeck(deck.id);
      snapshots.add(_DeckSnapshot(deck: deck, cards: cards));
    }
    if (!mounted) return;
    setState(() {
      _decks = snapshots;
      _isLoading = false;
    });
  }

  int get _masteredTotal => _decks.fold(0, (sum, deck) => sum + deck.mastered);

  int get _dueTotal {
    final end = _dayEnd;
    return _decks.fold(0, (sum, deck) => sum + deck.dueCount(end));
  }

  List<Flashcard> _allDueCards() {
    final end = _dayEnd;
    final cards = _decks.expand((deck) => deck.cards.where((card) => _isDue(card, end))).toList();
    cards.sort((a, b) => a.nextReviewDate.compareTo(b.nextReviewDate));
    return cards;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showApiKeySheet() async {
    final controller = TextEditingController(text: _geminiApiKey);
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.slate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gemini API key', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Stored on this device for this session. Used only to generate cards and resolve doubts.',
                style: TextStyle(color: PulseColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                style: const TextStyle(color: PulseColors.text),
                decoration: _fieldDecoration('Paste your AI Studio key'),
              ),
              const SizedBox(height: 16),
              _GradientButton(
                label: 'Save key',
                onPressed: () => Navigator.pop(context, controller.text.trim()),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    setState(() => _geminiApiKey = saved);
  }

  Future<void> _createDeck() async {
    final controller = TextEditingController();
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.slate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New deck', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: PulseColors.text),
                decoration: _fieldDecoration('Organic chemistry, OS midterm...'),
              ),
              const SizedBox(height: 16),
              _GradientButton(
                label: 'Create deck',
                onPressed: () => Navigator.pop(context, controller.text.trim()),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await DatabaseHelper.instance.insertDeck(
      Deck(id: const Uuid().v4(), title: title, createdAt: DateTime.now()),
    );
    await _loadData();
  }

  Future<bool> _ensureApiKey() async {
    if (_geminiApiKey.isNotEmpty) return true;
    await _showApiKeySheet();
    return _geminiApiKey.isNotEmpty;
  }

  Future<void> _openReview(List<Flashcard> cards) async {
    if (cards.isEmpty) {
      _toast('Nothing due right now.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReviewScreen(cards: cards, geminiApiKey: _geminiApiKey)),
    );
    await _loadData();
  }

  Future<void> _studyDeck(_DeckSnapshot snapshot) async {
    if (snapshot.total == 0) {
      _toast('This deck has no cards yet.');
      return;
    }
    final due = snapshot.cards.where((card) => _isDue(card, _dayEnd)).toList();
    await _openReview(due.isEmpty ? snapshot.cards : due);
  }

  Future<void> _openGenerator({String? deckId}) async {
    if (_decks.isEmpty) {
      await _createDeck();
      if (_decks.isEmpty) return;
    }
    if (!await _ensureApiKey()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiCardCreatorScreen(
          decks: _decks.map((item) => item.deck).toList(),
          geminiApiKey: _geminiApiKey,
          initialDeckId: deckId,
        ),
      ),
    );
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.obsidian,
      body: Stack(
        children: [
          const _AmbientGlow(),
          SafeArea(
            child: Column(
              children: [
                _HomeBar(
                  mastered: _masteredTotal,
                  due: _dueTotal,
                  hasKey: _geminiApiKey.isNotEmpty,
                  onCreateDeck: _createDeck,
                  onGenerate: () => _openGenerator(),
                  onKey: _showApiKeySheet,
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: PulseColors.cyan))
                      : _decks.isEmpty
                          ? _EmptyDecks(onCreate: _createDeck)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                              itemCount: _decks.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final snapshot = _decks[index];
                                return DeckCard(
                                  title: snapshot.deck.title,
                                  total: snapshot.total,
                                  due: snapshot.dueCount(_dayEnd),
                                  mastered: snapshot.mastered,
                                  accent: _accents[index % _accents.length],
                                  onStudy: () => _studyDeck(snapshot),
                                  onGenerate: () => _openGenerator(deckId: snapshot.deck.id),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _isLoading
          ? null
          : PulseFab(
              enabled: _dueTotal > 0,
              onPressed: () => _openReview(_allDueCards()),
            ),
    );
  }
}

class _HomeBar extends StatelessWidget {
  const _HomeBar({
    required this.mastered,
    required this.due,
    required this.hasKey,
    required this.onCreateDeck,
    required this.onGenerate,
    required this.onKey,
  });

  final int mastered;
  final int due;
  final bool hasKey;
  final VoidCallback onCreateDeck;
  final VoidCallback onGenerate;
  final VoidCallback onKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RecallPulse',
                      style: TextStyle(
                        color: PulseColors.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Active recall, on your schedule',
                      style: TextStyle(color: PulseColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'API key',
                onPressed: onKey,
                icon: Icon(
                  Icons.key_rounded,
                  color: hasKey ? PulseColors.easy : PulseColors.again,
                ),
              ),
              IconButton(
                tooltip: 'Generate cards',
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome_rounded, color: PulseColors.cyan),
              ),
              IconButton(
                tooltip: 'New deck',
                onPressed: onCreateDeck,
                icon: const Icon(Icons.add_rounded, color: PulseColors.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                StatPill(
                  label: 'Cards Mastered',
                  value: '$mastered',
                  icon: Icons.verified_rounded,
                  color: PulseColors.easy,
                ),
                const SizedBox(width: 10),
                StatPill(
                  label: 'Due Today',
                  value: '$due',
                  icon: Icons.bolt_rounded,
                  color: PulseColors.cyan,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDecks extends StatelessWidget {
  const _EmptyDecks({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PulseColors.cyan.withValues(alpha: 0.12),
                border: Border.all(color: PulseColors.cyan.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.style_rounded, color: PulseColors.cyan, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'No decks yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: PulseColors.text),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a deck, then generate cards from your notes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PulseColors.muted),
            ),
            const SizedBox(height: 18),
            _GradientButton(label: 'Create a deck', onPressed: onCreate),
          ],
        ),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: _orb(PulseColors.indigo, 220),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: _orb(PulseColors.cyan, 180),
          ),
        ],
      ),
    );
  }

  Widget _orb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
      ),
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: PulseColors.muted),
    filled: true,
    fillColor: PulseColors.obsidian,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: PulseColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: PulseColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: PulseColors.cyan),
    ),
  );
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: PulseColors.accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
