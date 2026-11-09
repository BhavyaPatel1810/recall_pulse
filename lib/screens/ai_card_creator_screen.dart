import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';
import '../services/settings_service.dart';
import '../theme/pulse_theme.dart';
import 'settings_screen.dart';

class AiCardCreatorScreen extends StatefulWidget {
  final Deck? initialDeck;

  const AiCardCreatorScreen({super.key, this.initialDeck});

  @override
  State<AiCardCreatorScreen> createState() => _AiCardCreatorScreenState();
}

class _AiCardCreatorScreenState extends State<AiCardCreatorScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _contentController = TextEditingController();

  List<Deck> _decks = [];
  String? _selectedDeckId;
  int _cardCount = 10;
  String _selectedDifficulty = 'Intermediate';
  String _preferredLanguage = 'English';

  bool _isLoadingDecks = true;
  bool _isGenerating = false;
  bool _isSavingBatch = false;

  List<GeneratedCardDraft> _generatedDrafts = [];

  late AnimationController _pulseController;

  static const List<String> _difficulties = [
    'Beginner',
    'Intermediate',
    'Advanced',
    'Exam / Expert',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadInitialData();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final decks = await DatabaseHelper.instance.getAllDecks();
    final lang = await SettingsService.instance.getPreferredLanguage();

    if (!mounted) return;
    setState(() {
      _decks = decks;
      _preferredLanguage = lang;
      if (widget.initialDeck != null && decks.any((d) => d.id == widget.initialDeck!.id)) {
        _selectedDeckId = widget.initialDeck!.id;
      } else if (decks.isNotEmpty) {
        _selectedDeckId = decks.first.id;
      }
      _isLoadingDecks = false;
    });
  }

  void _showQuickCreateDeckDialog() {
    final titleCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: 'AI Generated');
    final descCtrl = TextEditingController();

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
          title: const Text('Create Target Deck', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Deck Title',
                    hintText: 'e.g. Operating Systems Internals',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'e.g. Computer Science',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                  ),
                ),
              ],
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
              ),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final cat = catCtrl.text.trim().isEmpty ? 'General' : catCtrl.text.trim();
                final desc = descCtrl.text.trim();

                if (title.isEmpty) return;

                Navigator.of(dialogCtx).pop();
                if (!mounted) return;

                final now = DateTime.now();
                final newDeck = Deck(
                  id: const Uuid().v4(),
                  title: title,
                  description: desc,
                  category: cat,
                  createdAt: now,
                  updatedAt: now,
                );

                await DatabaseHelper.instance.insertDeck(newDeck);
                final updatedDecks = await DatabaseHelper.instance.getAllDecks();
                if (!mounted) return;
                setState(() {
                  _decks = updatedDecks;
                  _selectedDeckId = newDeck.id;
                });
              },
              child: const Text('Create & Select'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateFlashcards() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text('Please enter a topic or paste study notes first.'),
        ),
      );
      return;
    }

    if (_selectedDeckId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          content: Text('Please select or create a target deck first.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();

    setState(() {
      _isGenerating = true;
    });

    try {
      final drafts = await GeminiService.instance.generateFlashcardsFromContent(
        content: content,
        count: _cardCount,
        language: _preferredLanguage,
        difficulty: _selectedDifficulty,
      );

      if (!mounted) return;
      setState(() {
        _generatedDrafts = drafts;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });

      final errMsg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: PulseTheme.neonCoral,
          duration: const Duration(seconds: 5),
          content: Text(errMsg),
          action: errMsg.contains('Settings')
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                )
              : null,
        ),
      );
    }
  }

  void _editDraftCard(int index) {
    final draft = _generatedDrafts[index];
    final qCtrl = TextEditingController(text: draft.question);
    final aCtrl = TextEditingController(text: draft.answer);
    final expCtrl = TextEditingController(text: draft.aiExplanation);
    final tagsCtrl = TextEditingController(text: draft.tags.join(', '));

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
          title: const Text('Refine Generated Card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: qCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Question'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Answer'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: expCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'AI Mnemonic / Formula'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tagsCtrl,
                    decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
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
              ),
              onPressed: () {
                final q = qCtrl.text.trim();
                final a = aCtrl.text.trim();
                final exp = expCtrl.text.trim();
                final tags = tagsCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                if (q.isEmpty || a.isEmpty) return;

                Navigator.of(dialogCtx).pop();
                if (!mounted) return;

                setState(() {
                  _generatedDrafts[index].question = q;
                  _generatedDrafts[index].answer = a;
                  _generatedDrafts[index].aiExplanation = exp;
                  _generatedDrafts[index].tags = tags;
                });
              },
              child: const Text('Update Draft'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveSelectedCardsToSQLite() async {
    final selected = _generatedDrafts.where((d) => d.isSelected).toList();
    if (selected.isEmpty || _selectedDeckId == null) return;

    setState(() {
      _isSavingBatch = true;
    });

    final now = DateTime.now();
    const uuid = Uuid();

    for (final draft in selected) {
      final card = Flashcard(
        id: uuid.v4(),
        deckId: _selectedDeckId!,
        question: draft.question,
        answer: draft.answer,
        aiExplanation: draft.aiExplanation,
        tags: draft.tags,
        nextReviewDate: now,
        updatedAt: now,
      );
      await DatabaseHelper.instance.insertFlashcard(card);
    }

    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isSavingBatch = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: PulseTheme.neonEmerald,
        content: Text(
          'Saved ${selected.length} flashcards to your deck!',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );

    Navigator.of(context).pop(true);
  }

  int get _selectedCount => _generatedDrafts.where((d) => d.isSelected).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: PulseTheme.neonIndigo, size: 20),
            SizedBox(width: 8),
            Text(
              'AI Flashcard Studio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'AI Settings & API Key',
            icon: const Icon(Icons.settings_outlined, color: PulseTheme.textSecondary),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (!mounted) return;
              _loadInitialData();
            },
          ),
        ],
      ),
      bottomNavigationBar: _generatedDrafts.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: PulseTheme.surfaceCard,
                border: Border(top: BorderSide(color: PulseTheme.borderSubtle)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        final allSelected = _selectedCount == _generatedDrafts.length;
                        setState(() {
                          for (final d in _generatedDrafts) {
                            d.isSelected = !allSelected;
                          }
                        });
                      },
                      child: Text(
                        _selectedCount == _generatedDrafts.length ? 'Deselect All' : 'Select All',
                        style: const TextStyle(color: PulseTheme.textSecondary),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PulseTheme.neonEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isSavingBatch
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_done_rounded, size: 20),
                      label: Text(
                        'Save $_selectedCount Cards to Deck',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: (_selectedCount == 0 || _isSavingBatch) ? null : _saveSelectedCardsToSQLite,
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: _isLoadingDecks
          ? const Center(child: CircularProgressIndicator(color: PulseTheme.neonIndigo))
          : ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildDeckSelectorCard(),
                const SizedBox(height: 16),
                _buildPromptConfigurationCard(),
                const SizedBox(height: 20),
                if (_isGenerating) _buildAnimatedLoadingPanel(),
                if (!_isGenerating && _generatedDrafts.isNotEmpty) _buildGeneratedPreviewList(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildDeckSelectorCard() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Target Deck',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: PulseTheme.textSecondary),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.add_circle_outline, size: 16, color: PulseTheme.neonIndigo),
                label: const Text(
                  'New Deck',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: PulseTheme.neonIndigo),
                ),
                onPressed: _showQuickCreateDeckDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _decks.isEmpty
              ? OutlinedButton.icon(
                  onPressed: _showQuickCreateDeckDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create your first deck to begin'),
                )
              : DropdownButtonFormField<String>(
                  value: _selectedDeckId,
                  dropdownColor: PulseTheme.surfaceElevated,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: _decks.map((deck) {
                    return DropdownMenuItem<String>(
                      value: deck.id,
                      child: Text(
                        '${deck.title} (${deck.category})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDeckId = val;
                    });
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildPromptConfigurationCard() {
    return PulseGlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Topic, Syllabus, or Study Notes',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText:
                  'Paste lecture notes, textbook excerpts, research abstracts, or describe a specific topic (e.g., "Linux Kernel Virtual Memory, Page Tables, and TLB Shootdowns")...',
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Number of Flashcards',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PulseTheme.neonIndigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_cardCount Cards',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: PulseTheme.neonIndigo,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _cardCount.toDouble(),
            min: 5,
            max: 30,
            divisions: 25,
            activeColor: PulseTheme.neonIndigo,
            inactiveColor: PulseTheme.surfaceElevated,
            onChanged: (val) {
              setState(() {
                _cardCount = val.round();
              });
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Cognitive Difficulty',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _difficulties.map((diff) {
              final isSelected = _selectedDifficulty == diff;
              return ChoiceChip(
                label: Text(diff),
                selected: isSelected,
                selectedColor: PulseTheme.neonIndigo,
                backgroundColor: PulseTheme.surfaceElevated,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : PulseTheme.textSecondary,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedDifficulty = diff;
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseTheme.neonIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                _isGenerating ? 'Synthesizing Flashcards...' : 'Generate with AI ($_preferredLanguage)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: _isGenerating ? null : _generateFlashcards,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedLoadingPanel() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = 0.2 + (_pulseController.value * 0.4);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: PulseTheme.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: PulseTheme.neonIndigo.withOpacity(glow),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: PulseTheme.neonIndigo.withOpacity(glow * 0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Transform.scale(
                scale: 0.95 + (_pulseController.value * 0.15),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: PulseTheme.neonIndigo.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology_rounded, size: 42, color: PulseTheme.neonIndigo),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Extracting High-Yield Concepts...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Crafting $_cardCount active-recall prompts, mnemonics, and tags at $_selectedDifficulty level.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: PulseTheme.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGeneratedPreviewList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Generated Preview (${_generatedDrafts.length})',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Tap edit icon to refine before saving',
              style: TextStyle(fontSize: 12, color: PulseTheme.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(_generatedDrafts.length, (index) {
          final draft = _generatedDrafts[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: PulseTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: draft.isSelected
                    ? PulseTheme.neonIndigo.withOpacity(0.45)
                    : PulseTheme.borderSubtle,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: draft.isSelected,
                        activeColor: PulseTheme.neonIndigo,
                        onChanged: (val) {
                          setState(() {
                            draft.isSelected = val ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            draft.question,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit Draft Card',
                        icon: const Icon(Icons.edit_outlined, size: 18, color: PulseTheme.textSecondary),
                        onPressed: () => _editDraftCard(index),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          draft.answer,
                          style: const TextStyle(color: PulseTheme.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        if (draft.aiExplanation.isNotEmpty) ...[
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
                                const Icon(Icons.lightbulb_outline, size: 14, color: PulseTheme.neonIndigo),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    draft.aiExplanation,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFFC7D2FE)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (draft.tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: draft.tags.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: PulseTheme.surfaceElevated,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: const TextStyle(fontSize: 11, color: PulseTheme.textTertiary),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}