import 'dart:convert';
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
