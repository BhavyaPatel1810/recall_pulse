import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logic/srs_engine.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';
import '../services/settings_service.dart';
import '../theme/pulse_theme.dart';
import 'notification_settings_screen.dart';

class ReviewScreen extends StatefulWidget {
  final Deck deck;
  final List<Flashcard>? customCards;

  const ReviewScreen({
    super.key,
    required this.deck,
    this.customCards,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> with SingleTickerProviderStateMixin {
  List<Flashcard> _reviewQueue = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isFlipped = false;
  int _initialQueueLength = 0;
  int _cardsCompleted = 0;

  // Active Recall & AI Evaluation State
  bool _showActiveRecallInput = true;
  bool _isEvaluatingAnswer = false;
  AnswerEvaluationResult? _currentEvaluation;
  final TextEditingController _typedAnswerController = TextEditingController();

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutCubic),
    );

    _loadSessionCards();
  }

  @override
  void dispose() {
    _flipController.dispose();
    _typedAnswerController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionCards() async {
    final activeRecallPref = await SettingsService.instance.getActiveRecallEnabled();
    List<Flashcard> cards;
    if (widget.customCards != null) {
      cards = List.from(widget.customCards!);
    } else {
      cards = await DatabaseHelper.instance.getDueFlashcardsForDeck(widget.deck.id);
      if (cards.isEmpty) {
        cards = await DatabaseHelper.instance.getFlashcardsForDeck(widget.deck.id);
      }
    }

    if (!mounted) return;
    setState(() {
      _showActiveRecallInput = activeRecallPref;
      _reviewQueue = cards;
      _initialQueueLength = cards.length;
      _isLoading = false;
    });
  }

  void _flipCard() {
    if (_flipController.isAnimating) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  Future<void> _evaluateTypedAnswer() async {
    final userAnswer = _typedAnswerController.text.trim();
    if (userAnswer.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isEvaluatingAnswer = true;
    });

    final currentCard = _reviewQueue[_currentIndex];
    try {
      final eval = await GeminiService.instance.evaluateUserAnswer(
        question: currentCard.question,
        expectedAnswer: currentCard.answer,
        userTypedAnswer: userAnswer,
      );

      if (!mounted) return;
      setState(() {
        _currentEvaluation = eval;
        _isEvaluatingAnswer = false;
      });

      if (!_isFlipped) {
        _flipCard();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isEvaluatingAnswer = false;
      });
      final msg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text(msg),
          action: msg.contains('Settings')
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => SettingsScreen()),
                    );
                  },
                )
              : null,
        ),
      );
    }
  }

  void _openAiTutorBottomSheet(Flashcard card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return _AiTutorSheet(card: card);
      },
    );
  }

  Future<void> _processRating(int rating) async {
    if (_reviewQueue.isEmpty || _currentIndex >= _reviewQueue.length) return;
    HapticFeedback.lightImpact();

    final currentCard = _reviewQueue[_currentIndex];
    final srsResult = SRSEngine.calculateNextReview(currentCard, rating);

    final updatedCard = currentCard.copyWith(
      easeFactor: srsResult.easeFactor,
      interval: srsResult.interval,
      repetitions: srsResult.repetitions,
      nextReviewDate: srsResult.nextReviewDate,
      updatedAt: DateTime.now(),
    );

    await DatabaseHelper.instance.updateFlashcard(updatedCard);

    if (!mounted) return;

    _flipController.reset();
    _typedAnswerController.clear();

    setState(() {
      _isFlipped = false;
      _currentEvaluation = null;
      _cardsCompleted++;
      if (rating == SRSEngine.ratingAgain) {
        _reviewQueue.add(updatedCard);
      }
      _currentIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: PulseTheme.bgPrimary,
        body: Center(child: CircularProgressIndicator(color: PulseTheme.neonIndigo)),
      );
    }

    final isSessionFinished = _currentIndex >= _reviewQueue.length;

    return Scaffold(
      backgroundColor: PulseTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: PulseTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.deck.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!isSessionFinished)
            IconButton(
              tooltip: _showActiveRecallInput ? 'Hide Answer Typing Box' : 'Enable Answer Typing Box',
              icon: Icon(
                Icons.keyboard_alt_outlined,
                color: _showActiveRecallInput ? PulseTheme.neonIndigo : PulseTheme.textTertiary,
              ),
              onPressed: () {
                setState(() {
                  _showActiveRecallInput = !_showActiveRecallInput;
                });
              },
            ),
        ],
      ),
      body: SafeArea(
        child: isSessionFinished ? _buildCompletionScreen() : _buildActiveReviewBody(),
      ),
    );
  }

  Widget _buildActiveReviewBody() {
    final currentCard = _reviewQueue[_currentIndex];
    final totalSteps = max(_initialQueueLength, _reviewQueue.length);
    final progress = (_currentIndex / totalSteps).clamp(0.0, 1.0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Card ${_currentIndex + 1} of $totalSteps',
                    style: const TextStyle(fontSize: 12, color: PulseTheme.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${(progress * 100).toInt()}% Complete',
                    style: const TextStyle(fontSize: 12, color: PulseTheme.neonIndigo, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: PulseTheme.surfaceElevated,
                  valueColor: const AlwaysStoppedAnimation<Color>(PulseTheme.neonIndigo),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: GestureDetector(
              onTap: _flipCard,
              child: AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * pi;
                  final isBackVisible = _flipAnimation.value >= 0.5;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: isBackVisible
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(pi),
                            child: _buildCardBack(currentCard),
                          )
                        : _buildCardFront(currentCard),
                  );
                },
              ),
            ),
          ),
        ),
        if (_showActiveRecallInput && !_isFlipped) _buildActiveRecallTypingBar(),
        _buildSRSActionPanel(currentCard),
      ],
    );
  }

  Widget _buildActiveRecallTypingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: PulseGlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _typedAnswerController,
                minLines: 1,
                maxLines: 2,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _evaluateTypedAnswer(),
                decoration: const InputDecoration(
                  hintText: 'Type your answer for AI evaluation...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isEvaluatingAnswer
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(_isEvaluatingAnswer ? 'Grading...' : 'Check'),
              onPressed: _isEvaluatingAnswer ? null : _evaluateTypedAnswer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardFront(Flashcard card) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PulseTheme.surfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PulseTheme.borderSubtle, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: PulseTheme.neonIndigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'PROMPT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: PulseTheme.neonIndigo,
                  ),
                ),
              ),
              const Icon(Icons.touch_app_outlined, size: 20, color: PulseTheme.textTertiary),
            ],
          ),
          const Spacer(),
          Center(
            child: SingleChildScrollView(
              child: Text(
                card.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              'Tap card to flip or type answer below',
              style: TextStyle(fontSize: 12, color: PulseTheme.textTertiary.withOpacity(0.8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack(Flashcard card) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PulseTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PulseTheme.neonIndigo.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: PulseTheme.neonIndigo.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: PulseTheme.textTertiary, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: PulseTheme.neonIndigo,
                  side: BorderSide(color: PulseTheme.neonIndigo.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.psychology_outlined, size: 16),
                label: const Text(
                  'Ask AI Tutor',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _openAiTutorBottomSheet(card),
              ),
            ],
          ),
          const Divider(color: PulseTheme.borderSubtle, height: 18),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentEvaluation != null) ...[
                    _buildEvaluationResultBanner(_currentEvaluation!),
                    const SizedBox(height: 14),
                  ],
                  const Text(
                    'EXPECTED ANSWER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: PulseTheme.neonEmerald,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.answer,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  if (card.aiExplanation.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PulseTheme.bgPrimary.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PulseTheme.neonIndigo.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 14, color: PulseTheme.neonIndigo),
                              SizedBox(width: 6),
                              Text(
                                'Key Formula / Mnemonic',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: PulseTheme.neonIndigo,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            card.aiExplanation,
                            style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFCBD5E1)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvaluationResultBanner(AnswerEvaluationResult eval) {
    final Color scoreColor = eval.accuracyScore >= 80
        ? PulseTheme.neonEmerald
        : eval.accuracyScore >= 50
            ? PulseTheme.neonAmber
            : PulseTheme.neonCoral;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scoreColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scoreColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${eval.accuracyScore}% Match',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI Active Recall Grading',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            eval.feedback,
            style: const TextStyle(fontSize: 12, color: PulseTheme.textPrimary, height: 1.35),
          ),
          if (eval.missingKeyPoints.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Missing concepts: ${eval.missingKeyPoints.join(" • ")}',
              style: TextStyle(fontSize: 11, color: scoreColor, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSRSActionPanel(Flashcard card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: PulseTheme.surfaceCard,
        border: Border(top: BorderSide(color: PulseTheme.borderSubtle)),
      ),
      child: AnimatedOpacity(
        opacity: _isFlipped ? 1.0 : 0.25,
        duration: const Duration(milliseconds: 250),
        child: IgnorePointer(
          ignoring: !_isFlipped,
          child: Row(
            children: [
              _buildSRSButton(
                rating: SRSEngine.ratingAgain,
                label: 'Again',
                preview: SRSEngine.getIntervalPreview(card, SRSEngine.ratingAgain),
                color: PulseTheme.neonCoral,
              ),
              const SizedBox(width: 8),
              _buildSRSButton(
                rating: SRSEngine.ratingHard,
                label: 'Hard',
                preview: SRSEngine.getIntervalPreview(card, SRSEngine.ratingHard),
                color: PulseTheme.neonAmber,
              ),
              const SizedBox(width: 8),
              _buildSRSButton(
                rating: SRSEngine.ratingGood,
                label: 'Good',
                preview: SRSEngine.getIntervalPreview(card, SRSEngine.ratingGood),
                color: PulseTheme.neonBlue,
              ),
              const SizedBox(width: 8),
              _buildSRSButton(
                rating: SRSEngine.ratingEasy,
                label: 'Easy',
                preview: SRSEngine.getIntervalPreview(card, SRSEngine.ratingEasy),
                color: PulseTheme.neonEmerald,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSRSButton({
    required int rating,
    required String label,
    required String preview,
    required Color color,
  }) {
    final isSuggested = _currentEvaluation?.suggestedRating == rating;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _processRating(rating),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSuggested ? color.withOpacity(0.28) : color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSuggested ? color : color.withOpacity(0.35),
              width: isSuggested ? 2.0 : 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                preview,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSuggested) ...[
                    Icon(Icons.auto_awesome, size: 11, color: color),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: PulseTheme.neonEmerald.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: PulseTheme.neonEmerald.withOpacity(0.4), width: 2),
              ),
              child: const Icon(Icons.emoji_events, size: 64, color: PulseTheme.neonEmerald),
            ),
            const SizedBox(height: 24),
            const Text(
              'Session Complete!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'You reviewed $_cardsCompleted flashcard repetitions. Memory traces refreshed and synchronized.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: PulseTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Deck', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorMessage {
  final String sender; // 'user' or 'ai'
  final String text;

  const _TutorMessage({required this.sender, required this.text});
}

class _AiTutorSheet extends StatefulWidget {
  final Flashcard card;

  const _AiTutorSheet({required this.card});

  @override
  State<_AiTutorSheet> createState() => _AiTutorSheetState();
}

class _AiTutorSheetState extends State<_AiTutorSheet> {
  final TextEditingController _queryController = TextEditingController();
  final List<_TutorMessage> _messages = [];
  bool _isLoadingResponse = false;

  static const List<String> _quickPrompts = [
    'Break this down step-by-step',
    'Give me a real-world analogy',
    'Create a memorable mnemonic trick',
    'What are common exam traps here?',
  ];

  @override
  void initState() {
    super.initState();
    _askTutor('Explain this concept deeply with a real-world analogy and memory trick.');
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _askTutor(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || _isLoadingResponse) return;

    setState(() {
      _messages.add(_TutorMessage(sender: 'user', text: trimmed));
      _isLoadingResponse = true;
    });
    _queryController.clear();

    try {
      final lang = await SettingsService.instance.getPreferredLanguage();
      final reply = await GeminiService.instance.explainCardDeeper(
        widget.card,
        trimmed,
        lang,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(_TutorMessage(sender: 'ai', text: reply));
        _isLoadingResponse = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _TutorMessage(
            sender: 'ai',
            text: e.toString().replaceAll('Exception: ', ''),
          ),
        );
        _isLoadingResponse = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: PulseTheme.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: PulseTheme.borderSubtle, width: 1.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: PulseTheme.textTertiary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.psychology_rounded, color: PulseTheme.neonIndigo, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Interactive AI Study Tutor',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: PulseTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _quickPrompts.map((prompt) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: PulseTheme.surfaceElevated,
                    side: const BorderSide(color: PulseTheme.borderSubtle),
                    label: Text(
                      prompt,
                      style: const TextStyle(fontSize: 12, color: PulseTheme.textPrimary),
                    ),
                    onPressed: () => _askTutor(prompt),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(color: PulseTheme.borderSubtle, height: 20),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length + (_isLoadingResponse ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(color: PulseTheme.neonIndigo),
                    ),
                  );
                }
                final msg = _messages[index];
                final isUser = msg.sender == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? PulseTheme.neonIndigo.withOpacity(0.2)
                          : PulseTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isUser
                            ? PulseTheme.neonIndigo.withOpacity(0.5)
                            : PulseTheme.borderSubtle,
                      ),
                    ),
                    child: SelectableText(
                      msg.text,
                      style: const TextStyle(fontSize: 13.5, height: 1.45),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: const BoxDecoration(
              color: PulseTheme.surfaceElevated,
              border: Border(top: BorderSide(color: PulseTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _askTutor,
                    decoration: const InputDecoration(
                      hintText: 'Ask a follow-up question about this card...',
                      fillColor: PulseTheme.bgPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: PulseTheme.neonIndigo,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  onPressed: () => _askTutor(_queryController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}