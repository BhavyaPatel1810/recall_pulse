import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';
import '../theme/pulse_colors.dart';
import '../widgets/generate_loader.dart';
import '../widgets/glass_panel.dart';

enum _SourceMode { notes, topic }

class AiCardCreatorScreen extends StatefulWidget {
  const AiCardCreatorScreen({
    super.key,
    required this.decks,
    required this.geminiApiKey,
    this.initialDeckId,
  });

  final List<Deck> decks;
  final String geminiApiKey;
  final String? initialDeckId;

  @override
  State<AiCardCreatorScreen> createState() => _AiCardCreatorScreenState();
}

class _AiCardCreatorScreenState extends State<AiCardCreatorScreen> {
  final TextEditingController _textController = TextEditingController();
  late String _selectedDeckId;
  late final GeminiService _geminiService;
  _SourceMode _mode = _SourceMode.notes;
  bool _isGenerating = false;
  bool _isSaving = false;
  List<Flashcard> _generatedCards = [];

  @override
  void initState() {
    super.initState();
    final requested = widget.initialDeckId;
    final exists = widget.decks.any((deck) => deck.id == requested);
    _selectedDeckId = exists ? requested! : widget.decks.first.id;
    _geminiService = GeminiService(apiKey: widget.geminiApiKey);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _generateCards() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _toast(_mode == _SourceMode.notes ? 'Paste some study material first.' : 'Enter a topic first.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedCards = [];
    });

    final prompt = _mode == _SourceMode.topic ? 'Topic to study: $text' : text;
    try {
      final cards = await _geminiService.generateCardsFromText(
        rawText: prompt,
        deckId: _selectedDeckId,
      );
      if (!mounted) return;
      setState(() => _generatedCards = cards);
      if (cards.isEmpty) {
        _toast('No cards came back. Try a more specific prompt.');
      }
    } catch (error) {
      if (mounted) _toast('Could not generate cards. $error');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _saveCards() async {
    if (_generatedCards.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await DatabaseHelper.instance.insertMultipleFlashcards(_generatedCards);
      if (!mounted) return;
      final count = _generatedCards.length;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Saved $count cards to the deck.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _toast('Save failed. $error');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.obsidian,
      appBar: AppBar(
        title: const Text('Generate cards'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: _isGenerating
            ? const GenerateLoader()
            : _generatedCards.isEmpty
                ? _InputSheet(
                    mode: _mode,
                    decks: widget.decks,
                    selectedDeckId: _selectedDeckId,
                    controller: _textController,
                    onModeChanged: (mode) => setState(() => _mode = mode),
                    onDeckChanged: (id) => setState(() => _selectedDeckId = id),
                    onGenerate: _generateCards,
                  )
                : _PreviewSheet(
                    cards: _generatedCards,
                    saving: _isSaving,
                    onDelete: (index) => setState(() => _generatedCards.removeAt(index)),
                    onBack: () => setState(() => _generatedCards = []),
                    onSave: _saveCards,
                  ),
      ),
    );
  }
}

class _InputSheet extends StatelessWidget {
  const _InputSheet({
    required this.mode,
    required this.decks,
    required this.selectedDeckId,
    required this.controller,
    required this.onModeChanged,
    required this.onDeckChanged,
    required this.onGenerate,
  });

  final _SourceMode mode;
  final List<Deck> decks;
  final String selectedDeckId;
  final TextEditingController controller;
  final ValueChanged<_SourceMode> onModeChanged;
  final ValueChanged<String> onDeckChanged;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GlassPanel(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<_SourceMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _SourceMode.notes,
                      label: Text('Notes'),
                      icon: Icon(Icons.notes_rounded),
                    ),
                    ButtonSegment(
                      value: _SourceMode.topic,
                      label: Text('Topic'),
                      icon: Icon(Icons.topic_rounded),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (value) => onModeChanged(value.first),
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return PulseColors.obsidian;
                      return PulseColors.text;
                    }),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return PulseColors.cyan;
                      return Colors.transparent;
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedDeckId),
                  initialValue: selectedDeckId,
                  dropdownColor: PulseColors.slateRaised,
                  decoration: InputDecoration(
                    labelText: 'Save into',
                    labelStyle: const TextStyle(color: PulseColors.muted),
                    filled: true,
                    fillColor: PulseColors.obsidian.withValues(alpha: 0.65),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: decks
                      .map(
                        (deck) => DropdownMenuItem(
                          value: deck.id,
                          child: Text(deck.title, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onDeckChanged(value);
                  },
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(color: PulseColors.text, height: 1.4),
                    decoration: InputDecoration(
                      hintText: mode == _SourceMode.notes
                          ? 'Paste lecture notes, a chapter, or a problem set...'
                          : 'Enter a topic, like "TCP congestion control"',
                      hintStyle: const TextStyle(color: PulseColors.muted),
                      filled: true,
                      fillColor: PulseColors.obsidian.withValues(alpha: 0.65),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryButton(label: 'Generate flashcards', icon: Icons.auto_awesome_rounded, onPressed: onGenerate),
      ],
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.cards,
    required this.saving,
    required this.onDelete,
    required this.onBack,
    required this.onSave,
  });

  final List<Flashcard> cards;
  final bool saving;
  final ValueChanged<int> onDelete;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              '${cards.length} ready',
              style: const TextStyle(color: PulseColors.text, fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const Spacer(),
            TextButton(onPressed: saving ? null : onBack, child: const Text('Edit prompt')),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final card = cards[index];
              return GlassPanel(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.question,
                            style: const TextStyle(color: PulseColors.text, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(card.answer, style: const TextStyle(color: PulseColors.easy)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => onDelete(index),
                      icon: const Icon(Icons.close_rounded, color: PulseColors.again),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: saving ? 'Saving...' : 'Save ${cards.length} to deck',
          icon: Icons.save_rounded,
          onPressed: saving ? null : onSave,
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : PulseColors.accent,
        color: onPressed == null ? PulseColors.slateRaised : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
