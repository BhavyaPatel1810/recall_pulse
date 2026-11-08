class Deck {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;

  Deck({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Deck.fromMap(Map<String, dynamic> map) {
    return Deck(
      id: map['id'],
      title: map['title'],
      description: map['description'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
