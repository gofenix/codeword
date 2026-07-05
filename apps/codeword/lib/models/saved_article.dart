import 'dart:convert';

class SavedArticle {
  final String id;
  final DateTime createdAt;
  final String articleText;
  final String vocabId;
  final String vocabName;
  final List<Map<String, String>> wordPool;
  final List<Map<String, dynamic>>? questions;

  const SavedArticle({
    required this.id,
    required this.createdAt,
    required this.articleText,
    required this.vocabId,
    required this.vocabName,
    required this.wordPool,
    this.questions,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'articleText': articleText,
        'vocabId': vocabId,
        'vocabName': vocabName,
        'wordPool': wordPool,
        'questions': questions,
      };

  factory SavedArticle.fromJson(Map<String, dynamic> json) {
    return SavedArticle(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      articleText: json['articleText'] as String,
      vocabId: json['vocabId'] as String,
      vocabName: json['vocabName'] as String? ?? '',
      wordPool: (json['wordPool'] as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
      questions: json['questions'] == null
          ? null
          : (json['questions'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
    );
  }

  static String listToJson(List<SavedArticle> articles) =>
      jsonEncode(articles.map((a) => a.toJson()).toList());

  static List<SavedArticle> listFromJson(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => SavedArticle.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
