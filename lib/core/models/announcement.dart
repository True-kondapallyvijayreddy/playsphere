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
    this.match,
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

  /// Turns this poll into a match availability call.
  ///
  /// ## Why this is an announcement and not a new kind of document
  ///
  /// The same argument [poll] makes, one step further along. "Who is free
  /// Sunday at 6?" IS a club poll — the options are In, Maybe and Out, the
  /// votes are the answers, and the club already reads one feed. Giving it its
  /// own collection would mean a second feed, a second set of rules, a second
  /// place to look, and a duplicate of the vote-merging write that
  /// [CommunityRepository.voteInPoll] already gets right.
  ///
  /// What a match call needs that a poll does not is the four facts you cannot
  /// hold a match without: when, where, which sport, and how many it takes.
  /// Those live here.
  final MatchCall? match;

  /// Whether this is a match availability call rather than an ordinary notice.
  ///
  /// Requires the poll as well as the metadata: a match call with no options
  /// is a notice about a match, which is a different thing and must not draw
  /// voting buttons that write nowhere.
  bool get isMatchRsvp => match != null && poll != null;

  /// Whether [uid] is one of the people this post is asking.
  ///
  /// True for every member of an ordinary notice or an open call — see
  /// [MatchCall.invitedUids] for why a call may name its audience instead.
  /// The author is always addressed even when they did not put themselves on
  /// the list: they are the one waiting on the answers, and a captain who asks
  /// twelve players and then cannot find their own call is looking at a bug.
  bool isAddressedTo(String uid) =>
      uid == authorUid || (match?.isAddressedTo(uid) ?? true);

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
        match: MatchCall.fromMap(
          d['match'] is Map
              ? Map<String, dynamic>.from(d['match'] as Map)
              : null,
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
        'match': match?.toMap(),
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

  /// Everybody who chose [optionIndex].
  ///
  /// Sorted, so the roster a card draws does not reshuffle itself every time
  /// the snapshot arrives — a list of names that reorders under the reader is
  /// unreadable, and map iteration order is not a promise.
  List<String> votersFor(int optionIndex) => [
        for (final e in votes.entries)
          if (e.value == optionIndex) e.key,
      ]..sort();

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


/// The three answers a match call puts, and the only three it may put.
///
/// The indexes are STORED — `Poll.votes` maps a uid to a position in
/// `Poll.options` — so these constants are wire format and reordering them
/// would silently turn every recorded "In" into a "Maybe". Named here so the
/// card, the clash check and the team draft all read the same one.
class Rsvp {
  const Rsvp._();

  static const int yes = 0;
  static const int maybe = 1;
  static const int no = 2;

  /// The options a match call is created with, in index order.
  static const List<String> options = ['In', 'Maybe', 'Out'];
}

/// The four facts an availability call cannot do without: when, where, which
/// sport, and how many it takes.
///
/// Deliberately a nested map on the announcement rather than four loose
/// fields. `isMatchRsvp` is then "does this key exist", which is one test
/// rather than four, and an ordinary notice carries no match keys at all
/// instead of four nulls that every reader has to interpret.
class MatchCall {
  const MatchCall({
    required this.sportId,
    required this.matchDate,
    this.venue = '',
    this.maxPlayers = 0,
    this.forFixture,
    this.forChallenge,
    this.invitedUids = const [],
  });

  /// The sport, by catalogue id. Drives the icon, the squad arithmetic and
  /// which pad the match eventually opens.
  final String sportId;

  /// Kick-off. The whole point of the call — and the field the clash check
  /// reads, since two matches at the same hour are two matches one person
  /// cannot play.
  final DateTime matchDate;

  /// Ground or court, in the club's own words. Empty when not settled yet,
  /// which is a real state: plenty of clubs poll availability first and book
  /// the ground once they know the numbers.
  final String venue;

  /// How many the organizer is trying to field, ALL SIDES TOGETHER — 22 for
  /// eleven-a-side cricket, 4 for badminton doubles.
  ///
  /// Zero means "as many as turn up", which is the honest default for a club
  /// kickabout and stops the card drawing a capacity bar against a number
  /// nobody chose. It is the threshold the card uses to decide whether a
  /// turnout fills one match or wants a mini-tournament.
  final int maxPlayers;

  /// The match this call is asking about, when it is asking about a real one.
  ///
  /// ## Why a call needed to know
  ///
  /// A club poll — "who is free Sunday at 6?" — and a fixture that exists and
  /// needs eleven names were two unconnected things. The organizer of a
  /// challenge match read the poll with their eyes and retyped every name
  /// into the team sheet, which is the manual step the availability call was
  /// supposed to remove. Worse, the two lists then drifted: somebody who
  /// pulled out of the poll stayed on the sheet, because nothing joined them.
  ///
  /// Null for an ordinary club call, which is still the common case — plenty
  /// of clubs poll availability BEFORE there is a match to attach it to, and
  /// requiring a fixture first would forbid the order most clubs work in.
  final FixtureCallTarget? forFixture;

  bool get isForFixture => forFixture != null;

  /// The challenge this call is asking about, before there is a match to ask
  /// about.
  ///
  /// ## Why a challenge needed its own target
  ///
  /// [forFixture] can only be set once a challenge has been ACCEPTED — that is
  /// the moment a fixture exists. But the question a club wants to put to its
  /// members is older than that: "we have challenged Gachibowli for the 26th,
  /// who is in?". Asking it before the opponent replies is what lets a captain
  /// answer with a real squad instead of a guess, and it is what stops a club
  /// accepting a fixture it turns out it cannot field eleven for.
  ///
  /// The two targets are not alternatives so much as two ends of the same
  /// thread. `Fixture.sourceId` carries the challenge id, so once the match
  /// exists `SquadRsvpActions` finds this call by matching that id and moves
  /// the yeses onto the team sheet — no second call, and nobody retyped.
  final ChallengeCallTarget? forChallenge;

  bool get isForChallenge => forChallenge != null;

  /// The members this call is addressed to. Empty means the whole club, which
  /// is the default and the common case.
  ///
  /// ## Why a call needed an audience
  ///
  /// A village club with 120 members that challenges another club does not
  /// want 120 answers to a question about an eleven-a-side match — it wants
  /// the twenty people who might actually travel on Saturday. Asking everyone
  /// produces a poll nobody trusts, and a captain who then has to explain to
  /// eighty people why they said In and are not playing.
  ///
  /// This is ADDRESSING, not access control. The announcement is still
  /// readable by the club, as `firestore.rules` has always allowed and as a
  /// notice board should be — a member who hears about the match can go and
  /// look. What it changes is whose home screen it lands on, whose phone it
  /// notifies and whose RSVP count it raises, which is the part that was
  /// costing people their attention.
  final List<String> invitedUids;

  bool get isTargeted => invitedUids.isNotEmpty;

  /// Whether [uid] is one of the people being asked. See [Announcement.isAddressedTo],
  /// which is what callers should use — it also lets the author through.
  bool isAddressedTo(String uid) =>
      invitedUids.isEmpty || invitedUids.contains(uid);

  /// Whether more people have said yes than this match can seat.
  ///
  /// False whenever no target was set: without a number there is no such
  /// thing as a surplus, and offering to split a group into a tournament
  /// because eight people answered an open invitation would be inventing a
  /// problem.
  bool hasSurplus(int confirmed) => maxPlayers > 0 && confirmed > maxPlayers;

  static MatchCall? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final when = Fs.dateOrNull(d['matchDate']);
    // A call with no kick-off is not a call. Returning null degrades it to an
    // ordinary poll rather than rendering a card with a blank date on it.
    if (when == null) return null;
    return MatchCall(
      sportId: Fs.str(d['sportId']),
      matchDate: when,
      venue: Fs.str(d['venue']),
      maxPlayers: Fs.integer(d['maxPlayers']),
      forFixture: FixtureCallTarget.fromMap(
        d['forFixture'] is Map
            ? Map<String, dynamic>.from(d['forFixture'] as Map)
            : null,
      ),
      forChallenge: ChallengeCallTarget.fromMap(
        d['forChallenge'] is Map
            ? Map<String, dynamic>.from(d['forChallenge'] as Map)
            : null,
      ),
      invitedUids: Fs.strList(d['invitedUids']),
    );
  }

  Map<String, Object?> toMap() => {
        'sportId': sportId,
        'matchDate': Timestamp.fromDate(matchDate),
        'venue': venue,
        'maxPlayers': maxPlayers,
        'forFixture': forFixture?.toMap(),
        'forChallenge': forChallenge?.toMap(),
        'invitedUids': invitedUids,
      };
}

/// Which challenge an availability call is asking about.
///
/// Deliberately thinner than [FixtureCallTarget]. A challenge is a top-level
/// document — `challenges/{challengeId}` — so one id addresses it, and there
/// is no side to name yet because there is no team sheet to have sides on.
/// The club asking is the one whose board the call sits on, which is the only
/// club that can post there.
///
/// [opponentName] is denormalized so a card can say "against Gachibowli Club"
/// without a second read from a screen that has the announcement and nothing
/// else — the same reason `Challenge` carries both clubs' names.
class ChallengeCallTarget {
  const ChallengeCallTarget({
    required this.challengeId,
    required this.opponentName,
  });

  final String challengeId;
  final String opponentName;

  static ChallengeCallTarget? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final id = Fs.str(d['challengeId']);
    // A target that cannot address a challenge is not a target — the same
    // degradation [FixtureCallTarget] makes, and for the same reason: better
    // an ordinary availability call than a card whose buttons lead nowhere.
    if (id.isEmpty) return null;
    return ChallengeCallTarget(
      challengeId: id,
      opponentName: Fs.str(d['opponentName'], 'the other club'),
    );
  }

  Map<String, Object?> toMap() => {
        'challengeId': challengeId,
        'opponentName': opponentName,
      };
}

/// Which match, and whose side of it, an availability call is filling.
///
/// All four ids, because a fixture is not addressable with fewer: it lives at
/// `orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}`, and in an
/// inter-club match that path is under the HOSTING club — so the visiting
/// club's own call points at a document outside its own org. [side] is what
/// makes the answers land on the right half of the team sheet, and it is
/// derived from the club when the call is created rather than being anything
/// an organizer can type.
class FixtureCallTarget {
  const FixtureCallTarget({
    required this.orgId,
    required this.compId,
    required this.fixtureId,
    required this.side,
  });

  /// The club that HOSTS the fixture — not necessarily the club whose notice
  /// board this call is on.
  final String orgId;
  final String compId;
  final String fixtureId;

  /// 'a' or 'b'.
  final String side;

  static FixtureCallTarget? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final fixtureId = Fs.str(d['fixtureId']);
    // A target that cannot address a fixture is not a target. Degrading to
    // null makes the call an ordinary poll rather than one that renders a
    // "add them to the squad" button leading nowhere.
    if (fixtureId.isEmpty) return null;
    return FixtureCallTarget(
      orgId: Fs.str(d['orgId']),
      compId: Fs.str(d['compId']),
      fixtureId: fixtureId,
      side: Fs.str(d['side'], 'a'),
    );
  }

  Map<String, Object?> toMap() => {
        'orgId': orgId,
        'compId': compId,
        'fixtureId': fixtureId,
        'side': side,
      };
}

/// One line in a match call's discussion
/// (`orgs/{orgId}/announcements/{announcementId}/messages/{messageId}`).
///
/// ## Why this one IS a subcollection, when votes are not
///
/// Votes are bounded by the club's membership and are read every time the card
/// draws — so they ride on the document, and the card costs one read. Messages
/// are unbounded, arrive in bursts, and are only read when somebody opens the
/// thread. On the document they would grow the announcement for every member
/// who never expands it, and eventually past the 1MB ceiling. The two are
/// genuinely different shapes and are stored differently for that reason.
class MatchChatMessage {
  const MatchChatMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String text;

  /// Null for the instant between a local write and the server stamping it.
  /// The thread sorts nulls last, which puts your own just-sent line at the
  /// bottom where you expect it.
  final DateTime? createdAt;

  factory MatchChatMessage.fromDoc(Map<String, dynamic> d, String docId) =>
      MatchChatMessage(
        id: docId,
        senderUid: Fs.str(d['senderUid']),
        senderName: Fs.str(d['senderName'], 'Member'),
        text: Fs.str(d['text']),
        createdAt: Fs.dateOrNull(d['createdAt']),
      );

  Map<String, Object?> toCreate() => {
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
