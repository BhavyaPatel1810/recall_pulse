import 'package:flutter/material.dart';
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
