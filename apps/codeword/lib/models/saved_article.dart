import 'dart:convert';

class SavedArticle {
  final String id;
  final DateTime createdAt;
  final String title;
  final String articleText;
  final String translationText;
  final String level;
  final String vocabId;
  final String vocabName;
  final List<Map<String, String>> wordPool;
  final List<Map<String, dynamic>>? questions;

  const SavedArticle({
    required this.id,
    required this.createdAt,
    this.title = '',
    required this.articleText,
    this.translationText = '',
    this.level = '',
    required this.vocabId,
    required this.vocabName,
    required this.wordPool,
    this.questions,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'title': title,
    'articleText': articleText,
    'translationText': translationText,
    'level': level,
    'vocabId': vocabId,
    'vocabName': vocabName,
    'wordPool': wordPool,
    'questions': questions,
  };

  factory SavedArticle.fromJson(Map<String, dynamic> json) {
    return SavedArticle(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      title: json['title'] as String? ?? '',
      articleText: json['articleText'] as String,
      translationText: json['translationText'] as String? ?? '',
      level: json['level'] as String? ?? '',
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
