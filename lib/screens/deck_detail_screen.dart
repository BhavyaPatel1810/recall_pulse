import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../theme/pulse_theme.dart';
import 'ai_card_creator_screen.dart';
import 'review_screen.dart';

class DeckDetailScreen extends StatefulWidget {
  final Deck deck;

  const DeckDetailScreen({super.key, required this.deck});

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  List<Flashcard> _cards = [];
  bool _isLoading = true;
  String _cardSearchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final cards = await DatabaseHelper.instance.getFlashcardsForDeck(widget.deck.id);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _isLoading = false;
    });
  }

  List<Flashcard> get _filteredCards {
    if (_cardSearchQuery.trim().isEmpty) return _cards;
    final query = _cardSearchQuery.toLowerCase();
    return _cards.where((c) {
      return c.question.toLowerCase().contains(query) ||
          c.answer.toLowerCase().contains(query) ||
          c.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  int get _dueCount {
    final now = DateTime.now();
    return _cards.where((c) => c.nextReviewDate.isBefore(now)).length;
  }

  int get _masteredCount {
    return _cards.where((c) => c.interval >= 21).length;
  }

  void _showAddEditCardDialog({Flashcard? existingCard}) {
    final isEditing = existingCard != null;
    final questionCtrl = TextEditingController(text: existingCard?.question ?? '');
    final answerCtrl = TextEditingController(text: existingCard?.answer ?? '');
    final explanationCtrl = TextEditingController(text: existingCard?.aiExplanation ?? '');
    final tagsCtrl = TextEditingController(text: existingCard?.tags.join(', ') ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: PulseTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: PulseTheme.borderSubtle),
          ),
          title: Text(isEditing ? 'Edit Flashcard' : 'Add New Flashcard'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: questionCtrl,
                    maxLines: 2,
                    autofocus: !isEditing,
                    decoration: const InputDecoration(
                      labelText: 'Question / Prompt',
                      hintText: 'Enter prompt or technical challenge...',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: answerCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Answer',
                      hintText: 'Enter comprehensive answer...',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: explanationCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'AI Deep Dive Note (Optional)',
                      hintText: 'Key caveats, heuristics, edge-cases...',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: tagsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma separated)',
                      hintText: 'e.g. Memory, Algorithms, DB',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: PulseTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final q = questionCtrl.text.trim();
                final a = answerCtrl.text.trim();
                final exp = explanationCtrl.text.trim();
                final rawTags = tagsCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                if (q.isEmpty || a.isEmpty) return;

                Navigator.of(dialogCtx).pop();
                if (!mounted) return;

                final nowUtc = DateTime.now().toUtc();
                if (isEditing) {
                  final updated = existingCard.copyWith(
                    question: q,
                    answer: a,
                    aiExplanation: exp,
                    tags: rawTags,
                    updatedAt: nowUtc,
                    isSynced: false,
                  );
                  await DatabaseHelper.instance.updateFlashcard(updated);
                } else {
                  final newCard = Flashcard(
                    id: const Uuid().v4(),
                    deckId: widget.deck.id,
                    question: q,
                    answer: a,
                    aiExplanation: exp,
                    tags: rawTags,
                    nextReviewDate: nowUtc,
                    updatedAt: nowUtc,
                    isSynced: false,
                  );
                  await DatabaseHelper.instance.insertFlashcard(newCard);
                }

                if (!mounted) return;
                await _loadCards();
              },
              child: Text(isEditing ? 'Save Changes' : 'Add Flashcard'),
            ),
          ],
        );
      },
    );
  }

  void _deleteCard(Flashcard card) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: PulseTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: PulseTheme.borderSubtle),
          ),
          title: const Text('Delete Flashcard?'),
          content: const Text(
            'This flashcard will be removed from your spaced repetition schedule.',
            style: TextStyle(color: PulseTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: PulseTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: PulseTheme.neonCoral),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                if (!mounted) return;
                await DatabaseHelper.instance.deleteFlashcard(card.id);
                if (!mounted) return;
                await _loadCards();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleNotificationBell(Flashcard card) async {
    final nextState = !card.isStarredForNotification;
    HapticFeedback.lightImpact();

    await DatabaseHelper.instance.toggleStarredForNotification(card.id, nextState);
    if (!mounted) return;

    setState(() {
      final index = _cards.indexWhere((c) => c.id == card.id);
      if (index != -1) {
        _cards[index] = card.copyWith(isStarredForNotification: nextState, isSynced: false);
      }
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: PulseTheme.surfaceElevated,
        content: Text(
          nextState
              ? 'Card marked for daily notification review pulse'
              : 'Card removed from daily notification pulses',
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.deck.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo.withOpacity(0.15),
                foregroundColor: PulseTheme.neonIndigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text(
                'AI Generate',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AiCardCreatorScreen(initialDeck: widget.deck),
                  ),
                );
                if (!mounted) return;
                await _loadCards();
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: PulseTheme.neonIndigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Card', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showAddEditCardDialog(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: PulseTheme.neonIndigo))
          : Column(
              children: [
                _buildHeaderStats(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _cardSearchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20, color: PulseTheme.textTertiary),
                      suffixIcon: _cardSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: PulseTheme.textTertiary),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _cardSearchQuery = '';
                                });
                              },
                            )
                          : null,
                      hintText: 'Search cards by question, answer, or tags...',
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredCards.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.style_outlined, size: 48, color: PulseTheme.textTertiary),
                              const SizedBox(height: 12),
                              Text(
                                _cardSearchQuery.isEmpty
                                    ? 'No cards yet. Add your first card or use AI Generate!'
                                    : 'No cards match "$_cardSearchQuery"',
                                style: const TextStyle(color: PulseTheme.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 84),
                          itemCount: _filteredCards.length,
                          itemBuilder: (context, index) {
                            final card = _filteredCards[index];
                            return _buildCardTile(card);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: PulseGlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                PulseStatPill(
                  icon: Icons.layers_outlined,
                  label: 'Cards',
                  value: '${_cards.length}',
                  color: PulseTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                PulseStatPill(
                  icon: Icons.alarm,
                  label: 'Due',
                  value: '$_dueCount',
                  color: _dueCount > 0 ? PulseTheme.neonCoral : PulseTheme.textTertiary,
                ),
                const SizedBox(width: 8),
                PulseStatPill(
                  icon: Icons.verified_outlined,
                  label: 'Mastered',
                  value: '$_masteredCount',
                  color: PulseTheme.neonEmerald,
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PulseTheme.neonIndigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(_dueCount > 0 ? 'Study Due ($_dueCount)' : 'Practice All'),
                  onPressed: _cards.isEmpty
                      ? null
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReviewScreen(deck: widget.deck),
                            ),
                          );
                          if (!mounted) return;
                          await _loadCards();
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardTile(Flashcard card) {
    final isDue = card.nextReviewDate.isBefore(DateTime.now());
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: PulseTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDue ? PulseTheme.neonCoral.withOpacity(0.3) : PulseTheme.borderSubtle,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    card.question,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton(
                  tooltip: card.isStarredForNotification
                      ? 'Starred for Daily Pulse Notifications'
                      : 'Star for Notifications',
                  icon: Icon(
                    card.isStarredForNotification ? Icons.notifications_active : Icons.notifications_none,
                    color: card.isStarredForNotification ? PulseTheme.neonAmber : PulseTheme.textTertiary,
                    size: 20,
                  ),
                  onPressed: () => _toggleNotificationBell(card),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: PulseTheme.textTertiary),
                  color: PulseTheme.surfaceElevated,
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showAddEditCardDialog(existingCard: card);
                    } else if (val == 'delete') {
                      _deleteCard(card);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: PulseTheme.neonCoral)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              card.answer,
              style: const TextStyle(color: PulseTheme.textSecondary, fontSize: 13),
            ),
            if (card.aiExplanation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PulseTheme.neonIndigo.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PulseTheme.neonIndigo.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: PulseTheme.neonIndigo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.aiExplanation,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFC7D2FE)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...card.tags.map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: PulseTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$t',
                      style: const TextStyle(fontSize: 11, color: PulseTheme.textTertiary),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDue ? PulseTheme.neonCoral.withOpacity(0.12) : PulseTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDue ? 'Due for review' : 'Next: ${dateFormat.format(card.nextReviewDate.toLocal())}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDue ? PulseTheme.neonCoral : PulseTheme.textSecondary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: PulseTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'EF: ${card.easeFactor.toStringAsFixed(1)} | Reps: ${card.repetitions}',
                    style: const TextStyle(fontSize: 11, color: PulseTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}