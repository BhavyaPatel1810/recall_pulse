class Flashcard {
  final String id;
  final String deckId;
  final String question;
  final String answer;
  final String explanation;
  final int repetitions;
  final double easeFactor;
  final int interval;
  final DateTime nextReviewDate;
  final DateTime createdAt;

  Flashcard({
    required this.id,
    required this.deckId,
    required this.question,
    required this.answer,
    this.explanation = '',
    this.repetitions = 0,
    this.easeFactor = 2.5,
    this.interval = 1,
    required this.nextReviewDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deck_id': deckId,
      'question': question,
      'answer': answer,
      'explanation': explanation,
      'repetitions': repetitions,
      'ease_factor': easeFactor,
      'interval': interval,
      'next_review_date': nextReviewDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Flashcard.fromMap(Map<String, dynamic> map) {
    return Flashcard(
      id: map['id'],
      deckId: map['deck_id'],
      question: map['question'],
      answer: map['answer'],
      explanation: map['explanation'] ?? '',
      repetitions: map['repetitions'] ?? 0,
      easeFactor: map['ease_factor']?.toDouble() ?? 2.5,
      interval: map['interval'] ?? 1,
      nextReviewDate: DateTime.parse(map['next_review_date']),
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Flashcard copyWith({
    String? question,
    String? answer,
    String? explanation,
    int? repetitions,
    double? easeFactor,
    int? interval,
    DateTime? nextReviewDate,
  }) {
    return Flashcard(
      id: id,
      deckId: deckId,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      explanation: explanation ?? this.explanation,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      createdAt: createdAt,
    );
  }
}
