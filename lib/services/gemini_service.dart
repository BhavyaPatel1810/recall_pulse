import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/flashcard.dart';
import '../logic/srs_engine.dart';
import 'settings_service.dart';

class GeneratedCardDraft {
  String question;
  String answer;
  String aiExplanation;
  List<String> tags;
  bool isSelected;

  GeneratedCardDraft({
    required this.question,
    required this.answer,
    required this.aiExplanation,
    required this.tags,
    this.isSelected = true,
  });

  factory GeneratedCardDraft.fromMap(Map<String, dynamic> map) {
    List<String> parsedTags = [];
    if (map['tags'] is List) {
      parsedTags = (map['tags'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    return GeneratedCardDraft(
      question: (map['question'] as String? ?? '').trim(),
      answer: (map['answer'] as String? ?? '').trim(),
      aiExplanation: (map['aiExplanation'] as String? ?? '').trim(),
      tags: parsedTags,
      isSelected: true,
    );
  }
}

class AnswerEvaluationResult {
  final int accuracyScore;
  final String feedback;
  final List<String> missingKeyPoints;
  final int suggestedRating;

  const AnswerEvaluationResult({
    required this.accuracyScore,
    required this.feedback,
    required this.missingKeyPoints,
    required this.suggestedRating,
  });

  factory AnswerEvaluationResult.fromMap(Map<String, dynamic> map) {
    final score = ((map['accuracyScore'] as num?)?.toInt() ?? 0).clamp(0, 100);
    int rating = (map['suggestedRating'] as num?)?.toInt() ?? SRSEngine.ratingGood;
    if (rating < 1 || rating > 4) {
      if (score >= 90) {
        rating = SRSEngine.ratingEasy;
      } else if (score >= 70) {
        rating = SRSEngine.ratingGood;
      } else if (score >= 45) {
        rating = SRSEngine.ratingHard;
      } else {
        rating = SRSEngine.ratingAgain;
      }
    }

    List<String> missing = [];
    if (map['missingKeyPoints'] is List) {
      missing = (map['missingKeyPoints'] as List).map((e) => e.toString()).toList();
    }

    return AnswerEvaluationResult(
      accuracyScore: score,
      feedback: (map['feedback'] as String? ?? 'Evaluated by Gemini AI.').trim(),
      missingKeyPoints: missing,
      suggestedRating: rating,
    );
  }
}

class GeminiService {
  static final GeminiService instance = GeminiService._init();
  GeminiService._init();

  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  Future<bool> verifyConnection() async {
    try {
      final apiKey = await SettingsService.instance.getApiKey();
      final model = await SettingsService.instance.getSelectedModel();
      if (apiKey.isEmpty) return false;

      final uri = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'Respond with OK'}
                  ]
                }
              ],
              'generationConfig': {
                'maxOutputTokens': 10,
              }
            }),
          )
          .timeout(const Duration(seconds: 12));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Generates a strictly parsed list of flashcards from study notes or a topic description.
  Future<List<GeneratedCardDraft>> generateFlashcardsFromContent({
    required String content,
    required int count,
    required String language,
    required String difficulty,
  }) async {
    final apiKey = await SettingsService.instance.getApiKey();
    final model = await SettingsService.instance.getSelectedModel();

    if (apiKey.isEmpty) {
      throw Exception('Gemini API Key is missing. Please configure it in Settings.');
    }

    final prompt = '''
You are an elite spaced-repetition cognitive scientist and educator.
Generate exactly $count high-yield active recall flashcards based on the following topic or study notes.

Target Difficulty: $difficulty
Output Language: $language

Rules for High-Retention Flashcards:
1. Make questions atomic, unambiguous, and test deep understanding or practical application.
2. Make answers concise, accurate, and directly address the prompt.
3. For "aiExplanation", provide a memorable mnemonic, core mathematical formula, edge-case insight, or intuitive analogy.
4. Provide 2 to 4 relevant single-word tags per card.
5. Respond ONLY with a valid JSON array of objects containing keys: "question", "answer", "aiExplanation", and "tags" (array of strings).

Source Topic / Study Material:
"""
$content
"""
''';

    final uri = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.4,
              'responseMimeType': 'application/json',
            }
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final errBody = _parseErrorMessage(response.body);
      throw Exception('Gemini API Error (${response.statusCode}): $errBody');
    }

    final rawText = _extractTextFromResponse(response.body);
    final cleanedJson = _cleanJsonString(rawText);

    final decoded = jsonDecode(cleanedJson);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => GeneratedCardDraft.fromMap(item))
          .where((draft) => draft.question.isNotEmpty && draft.answer.isNotEmpty)
          .toList();
    } else if (decoded is Map<String, dynamic> && decoded['cards'] is List) {
      return (decoded['cards'] as List)
          .whereType<Map<String, dynamic>>()
          .map((item) => GeneratedCardDraft.fromMap(item))
          .where((draft) => draft.question.isNotEmpty && draft.answer.isNotEmpty)
          .toList();
    }

    throw Exception('Unexpected JSON format returned by Gemini.');
  }

  /// Interactive AI Tutor during card review: explains concepts deeper with analogies, derivations, and memory tricks.
  Future<String> explainCardDeeper(
    Flashcard card,
    String userQuery,
    String language,
  ) async {
    final apiKey = await SettingsService.instance.getApiKey();
    final model = await SettingsService.instance.getSelectedModel();

    if (apiKey.isEmpty) {
      throw Exception('Gemini API Key is not configured. Please add your key in Settings.');
    }

    final prompt = '''
You are an expert AI Study Tutor inside RecallPulse.
The student is currently reviewing the following flashcard:
- Question: ${card.question}
- Official Answer: ${card.answer}
- Existing Note: ${card.aiExplanation}

Student's Request / Question: "$userQuery"
Preferred Output Language: $language

Provide a clear, structured, and engaging explanation:
1. Directly answer the student's question.
2. Break down the underlying intuition or step-by-step derivation.
3. Provide a concrete real-world analogy or a vivid memory trick (mnemonic) so they never forget it.
Use clean bullet points and concise paragraphs suitable for mobile and desktop reading.
''';

    final uri = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.5,
            }
          }),
        )
        .timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      final errBody = _parseErrorMessage(response.body);
      throw Exception('Gemini Tutor Error (${response.statusCode}): $errBody');
    }

    return _extractTextFromResponse(response.body).trim();
  }

  /// Evaluates an active recall answer typed by the user against the expected flashcard answer.
  Future<AnswerEvaluationResult> evaluateUserAnswer({
    required String question,
    required String expectedAnswer,
    required String userTypedAnswer,
  }) async {
    final apiKey = await SettingsService.instance.getApiKey();
    final model = await SettingsService.instance.getSelectedModel();
    final language = await SettingsService.instance.getPreferredLanguage();

    if (apiKey.isEmpty) {
      throw Exception('Gemini API Key is missing. Configure it in Settings.');
    }

    final prompt = '''
You are a fair, rigorous spaced-repetition examiner.
Evaluate the student's typed active-recall answer against the expected flashcard answer.

Flashcard Question: "$question"
Expected Answer: "$expectedAnswer"
Student's Typed Answer: "$userTypedAnswer"
Feedback Language: $language

Return ONLY a valid JSON object with the following fields:
- "accuracyScore": integer from 0 to 100 representing conceptual correctness (do not penalize minor typos if conceptual understanding is solid).
- "feedback": 1-2 encouraging and specific sentences explaining what they got right or misunderstood.
- "missingKeyPoints": array of strings listing any critical concepts or terms omitted (empty array if score >= 90).
- "suggestedRating": integer representing the Anki SM-2 rating:
    1 = Again (score < 45, major misconception or blank)
    2 = Hard (score 45 to 69, partial recall with key omissions)
    3 = Good (score 70 to 89, solid recall)
    4 = Easy (score 90 to 100, complete and precise recall)
''';

    final uri = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
            }
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final errBody = _parseErrorMessage(response.body);
      throw Exception('Evaluation failed (${response.statusCode}): $errBody');
    }

    final rawText = _extractTextFromResponse(response.body);
    final cleanedJson = _cleanJsonString(rawText);
    final map = jsonDecode(cleanedJson) as Map<String, dynamic>;

    return AnswerEvaluationResult.fromMap(map);
  }

  String _extractTextFromResponse(String responseBody) {
    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no candidates.');
    }
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini candidate contained no text parts.');
    }
    return (parts.first['text'] as String? ?? '');
  }

  String _cleanJsonString(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  String _parseErrorMessage(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>?;
      return err?['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}