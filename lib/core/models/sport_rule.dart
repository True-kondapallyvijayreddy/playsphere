import 'firestore_codec.dart';

/// Official Rule & Regulation document for a sport (ICC, FIFA, FIBA, PKL, BWF, FIDE, etc.).
class SportRule {
  const SportRule({
    required this.id,
    required this.sportId,
    required this.category,
    required this.title,
    required this.description,
    required this.officialSource,
    this.keywords = const [],
    this.updatedAt,
  });

  final String id;
  final String sportId;
  final String category;
  final String title;
  final String description;

  /// Official governing body citation — e.g. "ICC Law 21.5", "FIFA Law 11", "AKFI Rule 5".
  final String officialSource;

  final List<String> keywords;
  final DateTime? updatedAt;

  factory SportRule.fromDoc(Map<String, dynamic> d, String docId) => SportRule(
        id: docId,
        sportId: Fs.str(d['sportId'], 'cricket'),
        category: Fs.str(d['category'], 'General'),
        title: Fs.str(d['title'], 'Rule Title'),
        description: Fs.str(d['description']),
        officialSource: Fs.str(d['officialSource'], 'Official Rulebook'),
        keywords: Fs.strList(d['keywords']),
        updatedAt: Fs.dateOrNull(d['updatedAt']),
      );

  Map<String, Object?> toMap() => {
        'sportId': sportId,
        'category': category,
        'title': title,
        'description': description,
        'officialSource': officialSource,
        'keywords': keywords,
        'updatedAt': Fs.ts(updatedAt ?? DateTime.now()),
      };
}
