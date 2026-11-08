import 'package:flutter/material.dart';
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
