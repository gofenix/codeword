/// A vocabulary word from a built-in or user-added word list.
class VocabWord {
  final String id;
  final String word;
  final String phonetic;
  final String pos;
  final String translation;
  final List<String> translations;
  final String exampleEn;
  final String exampleCn;
  final String domain;
  final String level;
  final List<String> synonyms;
  final List<String> antonyms;

  const VocabWord({
    required this.id,
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.translation,
    this.translations = const [],
    required this.exampleEn,
    required this.exampleCn,
    required this.domain,
    required this.level,
    this.synonyms = const [],
    this.antonyms = const [],
  });

  factory VocabWord.fromJson(Map<String, dynamic> json) => VocabWord(
        id: json['id'] as String,
        word: json['word'] as String,
        phonetic: (json['phonetic'] as String?) ?? '',
        pos: (json['pos'] as String?) ?? '',
        translation: json['translation'] as String,
        translations: ((json['translations'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        exampleEn: (json['exampleEn'] as String?) ?? '',
        exampleCn: (json['exampleCn'] as String?) ?? '',
        domain: json['domain'] as String,
        level: (json['level'] as String?) ?? '',
        synonyms: ((json['synonyms'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        antonyms: ((json['antonyms'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'word': word,
        'phonetic': phonetic,
        'pos': pos,
        'translation': translation,
        'translations': translations,
        'exampleEn': exampleEn,
        'exampleCn': exampleCn,
        'domain': domain,
        'level': level,
        'synonyms': synonyms,
        'antonyms': antonyms,
      };
}
