import 'package:flutter/material.dart';
import '../logic/spaced_repetition.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';
import '../theme/pulse_colors.dart';
import '../widgets/flip_flashcard.dart';
import '../widgets/srs_bar.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.cards,
    required this.geminiApiKey,
  });

  final List<Flashcard> cards;
  final String geminiApiKey;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _currentIndex = 0;
  bool _revealed = false;
  bool _saving = false;
  late final GeminiService? _geminiService;
  final TextEditingController _doubtController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _geminiService = widget.geminiApiKey.isEmpty ? null : GeminiService(apiKey: widget.geminiApiKey);
  }

  @override
  void dispose() {
    _doubtController.dispose();
    super.dispose();
  }

  Future<void> _handleRating(ReviewRating rating) async {
    if (_saving || widget.cards.isEmpty) return;
    setState(() => _saving = true);
    final currentCard = widget.cards[_currentIndex];
    final updatedMetrics = SpacedRepetitionEngine.calculateNextReview(
      currentRepetitions: currentCard.repetitions,
      currentEaseFactor: currentCard.easeFactor,
      currentInterval: currentCard.interval,
      rating: rating,
    );

    final updatedCard = currentCard.copyWith(
      repetitions: updatedMetrics['repetitions'] as int,
      easeFactor: updatedMetrics['easeFactor'] as double,
      interval: updatedMetrics['interval'] as int,
      nextReviewDate: updatedMetrics['nextReviewDate'] as DateTime,
    );
    await DatabaseHelper.instance.updateFlashcard(updatedCard);
    if (!mounted) return;

    if (_currentIndex + 1 < widget.cards.length) {
      setState(() {
        _currentIndex++;
        _revealed = false;
        _saving = false;
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Session complete. Nice work.')),
    );
  }

  void _openTutor(Flashcard card) {
    final service = _geminiService;
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a Gemini API key to ask a doubt.')),
      );
      return;
    }

    var thinking = false;
    var reply = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.slate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ask about this card',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: PulseColors.text),
                  ),
                  const SizedBox(height: 8),
                  Text(card.question, style: const TextStyle(color: PulseColors.muted)),
                  if (reply.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PulseColors.obsidian,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: PulseColors.line),
                      ),
                      child: Text(reply, style: const TextStyle(color: PulseColors.text, height: 1.4)),
                    ),
                  ],
                  if (thinking)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator(color: PulseColors.cyan)),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _doubtController,
                          style: const TextStyle(color: PulseColors.text),
                          decoration: InputDecoration(
                            hintText: 'What is still unclear?',
                            hintStyle: const TextStyle(color: PulseColors.muted),
                            filled: true,
                            fillColor: PulseColors.obsidian,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: PulseColors.cyan, foregroundColor: PulseColors.obsidian),
                        onPressed: thinking
                            ? null
                            : () async {
                                final query = _doubtController.text.trim();
                                if (query.isEmpty) return;
                                setSheetState(() => thinking = true);
                                final answer = await service.resolveDoubt(
                                  cardQuestion: card.question,
                                  cardAnswer: card.answer,
                                  userQuery: query,
                                );
                                _doubtController.clear();
                                setSheetState(() {
                                  reply = answer;
                                  thinking = false;
                                });
                              },
                        icon: const Icon(Icons.send_rounded),
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
        backgroundColor: PulseColors.obsidian,
        appBar: AppBar(),
        body: const Center(
          child: Text('No cards in this session.', style: TextStyle(color: PulseColors.muted)),
        ),
      );
    }

    final card = widget.cards[_currentIndex];
    final progress = (_currentIndex + 1) / widget.cards.length;

    return Scaffold(
      backgroundColor: PulseColors.obsidian,
      appBar: AppBar(
        title: Text('${_currentIndex + 1} / ${widget.cards.length}'),
        actions: [
          IconButton(
            tooltip: 'Ask a doubt',
            onPressed: () => _openTutor(card),
            icon: const Icon(Icons.auto_awesome_rounded, color: PulseColors.cyan),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            color: PulseColors.cyan,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          children: [
            Expanded(
              child: FlipFlashcard(
                key: ValueKey(card.id),
                question: card.question,
                answer: card.answer,
                explanation: card.explanation,
                revealed: _revealed,
                onToggle: () => setState(() => _revealed = !_revealed),
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _revealed
                  ? SrsBar(
                      key: const ValueKey('srs'),
                      onRate: _saving ? (_) {} : _handleRating,
                    )
                  : const SizedBox(
                      key: ValueKey('hint'),
                      height: 52,
                      child: Center(
                        child: Text(
                          'Flip the card, then grade the recall',
                          style: TextStyle(color: PulseColors.muted),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
