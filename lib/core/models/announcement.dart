import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// A post board update / notice inside a club (`orgs/{orgId}/announcements/{announcementId}`).
class Announcement {
  const Announcement({
    required this.id,
    required this.orgId,
    required this.authorUid,
    required this.authorName,
    required this.title,
    required this.content,
    this.isPinned = false,
    this.createdAt,
    this.poll,
  });

  final String id;
  final String orgId;
  final String authorUid;
  final String authorName;
  final String title;
  final String content;
  final bool isPinned;
  final DateTime? createdAt;

  /// Turns this post into a poll.
  ///
  /// A poll is an announcement with options rather than a separate kind of
  /// document, because in a club it is the same act — an admin asking the
  /// group something — and splitting it would give a club two feeds to read
  /// and two places to look for the question about Sunday's ground.
  final Poll? poll;

  bool get isPoll => poll != null;

  factory Announcement.fromDoc(Map<String, dynamic> d, String docId) =>
      Announcement(
        id: docId,
        orgId: Fs.str(d['orgId']),
        authorUid: Fs.str(d['authorUid']),
        authorName: Fs.str(d['authorName'], 'Admin'),
        title: Fs.str(d['title']),
        content: Fs.str(d['content']),
        isPinned: Fs.boolean(d['isPinned']),
        createdAt: Fs.dateOrNull(d['createdAt']),
        poll: Poll.fromMap(
          d['poll'] is Map ? Map<String, dynamic>.from(d['poll'] as Map) : null,
        ),
      );

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'authorUid': authorUid,
        'authorName': authorName,
        'title': title,
        'content': content,
        'isPinned': isPinned,
        'createdAt': FieldValue.serverTimestamp(),
        'poll': poll?.toMap(),
      };
}

/// A question put to the club, with the answers.
///
/// ## Why votes live on the poll rather than in a subcollection
///
/// A club poll is "who is coming on Sunday" answered by thirty people, not a
/// national election. Keeping the votes in one map means rendering the whole
/// poll — question, options, tallies, and whether *you* have voted — costs the
/// single document read the feed already does, instead of a second query per
/// post. The cost is that a poll is bounded by the document size limit, which
/// at one short uid per voter is thousands of people: far past the point where
/// a club would want a different tool anyway.
///
/// Votes are public by design. In a club, who is coming to the match is the
/// entire point of asking.
class Poll {
  const Poll({
    required this.options,
    this.votes = const {},
    this.closed = false,
  });

  /// The answers, in the order the author wrote them. Order is meaningful —
  /// it is how the question reads — so it is preserved rather than sorted.
  final List<String> options;

  /// uid -> the index in [options] they chose. One vote each, and changing
  /// your mind replaces it rather than adding a second.
  final Map<String, int> votes;

  final bool closed;

  int countFor(int optionIndex) =>
      votes.values.where((v) => v == optionIndex).length;

  int get totalVotes => votes.length;

  /// What [uid] chose, or null if they have not answered.
  int? voteOf(String uid) => votes[uid];

  /// Share of the vote for an option, 0..1. Zero when nobody has voted, which
  /// keeps the bars empty rather than dividing by zero.
  double shareFor(int optionIndex) =>
      totalVotes == 0 ? 0 : countFor(optionIndex) / totalVotes;

  static Poll? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final options = Fs.strList(d['options']);
    if (options.isEmpty) return null;
    final rawVotes = d['votes'];
    return Poll(
      options: options,
      votes: rawVotes is Map
          ? {
              for (final e in rawVotes.entries)
                if (e.value is num) e.key.toString(): (e.value as num).toInt(),
            }
          : const {},
      closed: Fs.boolean(d['closed']),
    );
  }

  Map<String, Object?> toMap() => {
        'options': options,
        'votes': votes,
        'closed': closed,
      };
}
