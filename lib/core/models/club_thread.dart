import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// What a club has pinned to a message, beyond the words.
///
/// A club owner who opens a conversation with another club is almost never
/// there to chat — they are there to say "we are running this, come". So the
/// thing being talked about travels WITH the message rather than as a pasted
/// link: the receiving owner sees the season's name, its dates and its sport
/// in the bubble and can open it in one tap, without leaving the app, and
/// without the sender having to remember what the public URL of their own
/// season is.
enum ThreadShareKind {
  /// A season or tournament — `orgs/{orgId}/tournaments/{refId}`.
  season('season'),

  /// One event inside a season — `orgs/{orgId}/competitions/{refId}`.
  event('event'),

  /// The club itself. What "have a look at us" sends.
  club('club');

  const ThreadShareKind(this.wire);

  final String wire;

  static ThreadShareKind fromWire(String? w) => ThreadShareKind.values
      .firstWhere((e) => e.wire == w, orElse: () => ThreadShareKind.club);
}

/// The denormalized card attached to a message.
///
/// Deliberately a copy and not a reference. The receiving club's owner can
/// read the sending club's public documents, but a thread is read months
/// later — after entries closed, after a season was renamed, sometimes after
/// it was deleted — and a bubble that renders as an empty box because the
/// thing it points at moved is worse than one that says what was said at the
/// time. [route] is the live link; everything else is the record.
class ThreadShare {
  const ThreadShare({
    required this.kind,
    required this.orgId,
    required this.refId,
    required this.title,
    this.subtitle,
    this.sportId,
    this.startsAt,
    this.route,
  });

  final ThreadShareKind kind;

  /// Which club owns the thing being shared. Not necessarily the sender's
  /// club — forwarding a third club's open season is a real and useful move.
  final String orgId;

  /// The tournament / competition / org id, depending on [kind].
  final String refId;

  final String title;
  final String? subtitle;
  final String? sportId;
  final DateTime? startsAt;

  /// An in-app router path, stored so an older build never has to guess how a
  /// newer one addresses a thing it has never heard of.
  final String? route;

  static ThreadShare? fromMap(Map<String, dynamic> m) {
    if (m.isEmpty) return null;
    final refId = Fs.str(m['refId']);
    if (refId.isEmpty) return null;
    return ThreadShare(
      kind: ThreadShareKind.fromWire(Fs.str(m['kind'])),
      orgId: Fs.str(m['orgId']),
      refId: refId,
      title: Fs.str(m['title'], 'Shared'),
      subtitle: Fs.strOrNull(m['subtitle']),
      sportId: Fs.strOrNull(m['sportId']),
      startsAt: Fs.dateOrNull(m['startsAt']),
      route: Fs.strOrNull(m['route']),
    );
  }

  Map<String, Object?> toMap() => Fs.prune({
        'kind': kind.wire,
        'orgId': orgId,
        'refId': refId,
        'title': title,
        'subtitle': subtitle,
        'sportId': sportId,
        'startsAt': Fs.ts(startsAt),
        'route': route,
      });
}

/// One club's own row for one conversation, at
/// `orgs/{myOrgId}/clubThreads/{threadId}`.
///
/// ## Why the id is derived and not generated
///
/// Two owners must never end up in two different conversations with each
/// other — that is how a message gets missed, and a missed fixture offer is
/// the whole value of this feature gone. Firestore has no unique constraint,
/// so uniqueness is bought the same way `playerCodes` and `tournamentInvites`
/// buy it: the sorted pair IS the id ([idFor]), so a second attempt to open
/// the same conversation resolves to the row that already exists rather than
/// creating a rival. The rules check the derivation, so a client cannot mint
/// a row whose id disagrees with its participants.
///
/// ## Why it is between CLUBS and not between people
///
/// Ownership changes. A club whose founder hands over to a successor must not
/// lose the conversation that arranged next season's fixtures, and the new
/// owner must not have to be re-introduced to every club their predecessor
/// knew. So the parties are clubs, and the sender's name on a message is a
/// courtesy rather than an address.
///
/// ## Why each club has its own row rather than sharing one document
///
/// The messages ARE shared — one top-level collection both clubs read, so
/// there is exactly one record of what was said. The summary is not, and that
/// split is forced by how Firestore authorises a query: a `list` is checked
/// against the query with a resource synthesised from its constraints, never
/// against the documents it would return, so an inbox over a top-level
/// collection cannot be allowed by any rule that reads the document. Putting
/// the club id in the path is what makes the inbox readable at all. See
/// `firestore.rules`.
///
/// The read marker gets the same benefit for free: [lastReadAt] lives on a
/// document only this club may write, so no club can stamp another's marker
/// and slip a message past its unread badge.
class ClubThread {
  const ClubThread({
    required this.id,
    required this.myOrgId,
    required this.orgIds,
    required this.otherOrgId,
    this.otherOrgName = 'A club',
    this.otherOrgLogoUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderOrgId,
    this.lastReadAt,
  });

  /// The thread id — the sorted pair, and the id of the shared message
  /// collection this row summarises.
  final String id;

  /// Whose inbox this row was read from.
  final String myOrgId;

  /// Both clubs, in the order [idFor] sorts them. The order is the derivation
  /// and carries no other meaning — neither side is "first".
  final List<String> orgIds;

  /// The club on the other side. Stored rather than derived so a row renders
  /// without the reader having to know which half of the pair it is.
  final String otherOrgId;

  /// Their name and crest, copied in so an inbox renders from one query.
  /// Refreshed by whoever sends next, which is as fresh as an inbox needs.
  final String otherOrgName;
  final String? otherOrgLogoUrl;

  final String? lastMessage;
  final DateTime? lastMessageAt;

  /// Which club sent [lastMessage]. What keeps a club's own outgoing message
  /// from marking its own inbox unread.
  final String? lastSenderOrgId;

  /// When this club last opened the conversation.
  ///
  /// A read marker rather than an unread COUNT, deliberately. A count has to
  /// be incremented by the sender, which means giving one club write access
  /// to a number the other club's badge depends on, and a single dropped
  /// write leaves a badge that never clears. A timestamp each club writes
  /// only for itself cannot drift: [isUnread] derives the badge from two
  /// facts that are already true.
  final DateTime? lastReadAt;

  /// The deterministic id for the conversation between [a] and [b].
  ///
  /// Sorted, so that whichever owner writes first, both clubs' rows and the
  /// shared message collection agree on one id.
  static String idFor(String a, String b) {
    final pair = [a, b]..sort();
    return '${pair[0]}__${pair[1]}';
  }

  static List<String> pairOf(String a, String b) => [a, b]..sort();

  /// Whether this club has something waiting.
  ///
  /// False for a conversation whose last message this club sent itself —
  /// otherwise every club would carry a permanent badge for its own outgoing
  /// messages until it re-opened a thread it has nothing to read in.
  bool get isUnread {
    final at = lastMessageAt;
    if (at == null) return false;
    if (lastSenderOrgId == myOrgId) return false;
    final read = lastReadAt;
    return read == null || at.isAfter(read);
  }

  factory ClubThread.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String myOrgId,
  }) {
    final d = doc.data() ?? const {};
    final orgIds = Fs.strList(d['orgIds']);
    return ClubThread(
      id: doc.id,
      myOrgId: myOrgId,
      orgIds: orgIds,
      otherOrgId: Fs.str(
        d['otherOrgId'],
        orgIds.firstWhere((id) => id != myOrgId, orElse: () => ''),
      ),
      otherOrgName: Fs.str(d['otherOrgName'], 'A club'),
      otherOrgLogoUrl: Fs.strOrNull(d['otherOrgLogoUrl']),
      lastMessage: Fs.strOrNull(d['lastMessage']),
      lastMessageAt: Fs.dateOrNull(d['lastMessageAt']),
      lastSenderOrgId: Fs.strOrNull(d['lastSenderOrgId']),
      lastReadAt: Fs.dateOrNull(d['lastReadAt']),
    );
  }
}

/// One message in a thread, at `clubThreads/{threadId}/messages/{messageId}`.
class ClubMessage {
  const ClubMessage({
    required this.id,
    required this.senderOrgId,
    required this.senderUid,
    required this.senderName,
    this.text = '',
    this.share,
    this.createdAt,
  });

  final String id;

  /// The club this was said on behalf of — what decides which side of the
  /// thread it renders on.
  final String senderOrgId;

  /// The person who actually typed it. Shown in small type above the bubble,
  /// because "Warangal Warriors said" is a club's position and "Ramesh said"
  /// is who to reply to.
  final String senderUid;
  final String senderName;

  final String text;
  final ThreadShare? share;
  final DateTime? createdAt;

  bool get isEmpty => text.trim().isEmpty && share == null;

  factory ClubMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ClubMessage(
      id: doc.id,
      senderOrgId: Fs.str(d['senderOrgId']),
      senderUid: Fs.str(d['senderUid']),
      senderName: Fs.str(d['senderName'], 'A club owner'),
      text: Fs.str(d['text']),
      share: ThreadShare.fromMap(Fs.map(d['share'])),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  /// What the inbox shows as the thread's last line.
  String get preview {
    final t = text.trim();
    if (t.isNotEmpty) return t;
    final s = share;
    if (s == null) return '';
    return switch (s.kind) {
      ThreadShareKind.season => 'Shared a season · ${s.title}',
      ThreadShareKind.event => 'Shared an event · ${s.title}',
      ThreadShareKind.club => 'Shared a club · ${s.title}',
    };
  }
}
