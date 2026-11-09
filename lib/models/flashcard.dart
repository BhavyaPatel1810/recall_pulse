import 'dart:convert';

class Flashcard {
  final String id;
  final String deckId;
  final String question;
  final String answer;
  final String aiExplanation;
  final List<String> tags;
  final double easeFactor;
  final int interval;
  final int repetitions;
  final DateTime nextReviewDate;
  final bool isStarredForNotification;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  const Flashcard({
    required this.id,
    required this.deckId,
    required this.question,
    required this.answer,
    this.aiExplanation = '',
    this.tags = const [],
    this.easeFactor = 2.5,
    this.interval = 0,
    this.repetitions = 0,
    required this.nextReviewDate,
    this.isStarredForNotification = false,
    required this.updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  });

  Flashcard copyWith({
    String? id,
    String? deckId,
    String? question,
    String? answer,
    String? aiExplanation,
    List<String>? tags,
    double? easeFactor,
    int? interval,
    int? repetitions,
    DateTime? nextReviewDate,
    bool? isStarredForNotification,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Flashcard(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      aiExplanation: aiExplanation ?? this.aiExplanation,
      tags: tags ?? this.tags,
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      isStarredForNotification: isStarredForNotification ?? this.isStarredForNotification,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deckId': deckId,
      'question': question,
      'answer': answer,
      'aiExplanation': aiExplanation,
      'tags': jsonEncode(tags),
      'easeFactor': easeFactor,
      'interval': interval,
      'repetitions': repetitions,
      'nextReviewDate': nextReviewDate.toIso8601String(),
      'isStarredForNotification': isStarredForNotification ? 1 : 0,
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Flashcard.fromMap(Map<String, dynamic> map) {
    List<String> parsedTags = [];
    if (map['tags'] != null) {
      try {
        final decoded = jsonDecode(map['tags'] as String);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        parsedTags = (map['tags'] as String)
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }

    return Flashcard(
      id: map['id'] as String,
      deckId: map['deckId'] as String,
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      aiExplanation: map['aiExplanation'] as String? ?? '',
      tags: parsedTags,
      easeFactor: (map['easeFactor'] as num?)?.toDouble() ?? 2.5,
      interval: (map['interval'] as num?)?.toInt() ?? 0,
      repetitions: (map['repetitions'] as num?)?.toInt() ?? 0,
      nextReviewDate: DateTime.tryParse(map['nextReviewDate'] as String? ?? '') ?? DateTime.now(),
      isStarredForNotification: (map['isStarredForNotification'] as int? ?? 0) == 1,
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      isSynced: (map['isSynced'] as int? ?? 0) == 1,
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Flashcard.fromJson(String source) =>
      Flashcard.fromMap(jsonDecode(source) as Map<String, dynamic>);
}