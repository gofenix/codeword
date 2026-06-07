/// A built-in or user-added vocabulary collection.
class VocabList {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final String domainColor;
  final int level;
  final int wordCount;

  const VocabList({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.domainColor,
    required this.level,
    required this.wordCount,
  });

  factory VocabList.fromJson(Map<String, dynamic> json) => VocabList(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        emoji: (json['emoji'] as String?) ?? '📘',
        domainColor: (json['domainColor'] as String?) ?? '#10B981',
        level: (json['level'] as int?) ?? 1,
        wordCount: (json['wordCount'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'emoji': emoji,
        'domainColor': domainColor,
        'level': level,
        'wordCount': wordCount,
      };
}

/// A user's review progress on a single word.
class ReviewState {
  final String wordId;
  final int easiness;
  final int interval;
  final int repetitions;
  final DateTime? dueAt;
  final DateTime? lastReviewedAt;

  const ReviewState({
    required this.wordId,
    required this.easiness,
    required this.interval,
    required this.repetitions,
    this.dueAt,
    this.lastReviewedAt,
  });

  factory ReviewState.fresh(String wordId) => ReviewState(
        wordId: wordId,
        easiness: 250, // SM-2 starts at 2.5; store as int*100 to avoid float
        interval: 0,
        repetitions: 0,
      );

  Map<String, dynamic> toJson() => {
        'wordId': wordId,
        'easiness': easiness,
        'interval': interval,
        'repetitions': repetitions,
        'dueAt': dueAt?.toIso8601String(),
        'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      };

  factory ReviewState.fromJson(Map<String, dynamic> json) => ReviewState(
        wordId: json['wordId'] as String,
        easiness: json['easiness'] as int,
        interval: json['interval'] as int,
        repetitions: json['repetitions'] as int,
        dueAt: json['dueAt'] != null ? DateTime.parse(json['dueAt']) : null,
        lastReviewedAt: json['lastReviewedAt'] != null
            ? DateTime.parse(json['lastReviewedAt'])
            : null,
      );
}
