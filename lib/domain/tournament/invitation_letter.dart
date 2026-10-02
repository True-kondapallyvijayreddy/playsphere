import '../../core/models/tournament.dart';

/// The words one club sends another when it asks them to come and play.
///
/// ## Why the app writes the first draft
///
/// An organizer inviting twenty clubs writes the same paragraph twenty times
/// in WhatsApp, and every copy is missing something — the dates in one, the
/// ground in another, the link in most. The facts are all already on the
/// season: who is hosting, which sports, from when to when, and where. So the
/// letter is composed from them, the organizer edits it if they want to, and
/// every club receives the same complete invitation.
///
/// ## Why the registration link is not part of the editable text
///
/// It is appended by [shareText] and rendered as a button in the app, never
/// typed into the letter. A link inside a free-text box is one stray keystroke
/// from pointing nowhere, and a broken registration link is an invitation
/// nobody can accept.
///
/// Pure and free of Flutter, so the wording is pinned by a test rather than by
/// somebody reading a screenshot.
class InvitationLetter {
  const InvitationLetter._();

  static const greeting = 'Dear sports enthusiasts,';

  /// The full letter, greeting included.
  ///
  /// "We from Adibatla Sports Club are conducting Summer Games 2026 — a season
  /// for Cricket, Table Tennis and Badminton — from 12 Aug to 24 Aug 2026 at
  /// Adibatla, Hyderabad."
  ///
  /// Every fact is optional except the two names, and a missing one drops its
  /// clause rather than printing "from null".
  static String compose({
    required String hostClubName,
    required String seasonName,
    required SeasonKind kind,
    List<String> sports = const [],
    DateTime? startDate,
    DateTime? endDate,
    String? place,
  }) {
    final host = hostClubName.trim().isEmpty ? 'our club' : hostClubName.trim();
    final name = seasonName.trim();
    final what = StringBuffer('a ${kind.noun}');
    final sportLine = sportList(sports);
    if (sportLine.isNotEmpty) what.write(' for $sportLine');

    final sentence = StringBuffer('We from $host are conducting ');
    if (name.isEmpty) {
      sentence.write(what);
    } else {
      sentence.write('$name — $what —');
    }
    final when = dateSpan(startDate, endDate);
    if (when.isNotEmpty) sentence.write(' $when');
    final where = place?.trim() ?? '';
    if (where.isNotEmpty) sentence.write(' at $where');

    // "— a season —." reads as a typo; the dash closes the aside only when
    // something follows it.
    var body = sentence.toString();
    if (body.endsWith(' —')) body = body.substring(0, body.length - 2);

    return '$greeting\n\n$body.\n\n'
        'Please participate. Register your club using the link below.';
  }

  /// The letter as it travels outside the app — WhatsApp, SMS, email — with
  /// the registration link on its own line at the end.
  static String shareText({
    required String letter,
    required String registrationUrl,
  }) =>
      '${letter.trimRight()}\n\nRegister here: $registrationUrl';

  /// "Cricket", "Cricket and Kabaddi", "Cricket, Kabaddi and Chess".
  ///
  /// Duplicates collapse, in first-seen order: a season with U-14 and U-17
  /// cricket runs cricket once, as far as a club deciding whether to come is
  /// concerned.
  static String sportList(Iterable<String> sports) {
    final seen = <String>{};
    final names = [
      for (final s in sports)
        if (s.trim().isNotEmpty && seen.add(s.trim().toLowerCase())) s.trim(),
    ];
    return switch (names.length) {
      0 => '',
      1 => names.single,
      _ => '${names.sublist(0, names.length - 1).join(', ')} '
          'and ${names.last}',
    };
  }

  /// "from 12 Aug to 24 Aug 2026", "on 12 Aug 2026", "from 28 Dec 2026 to
  /// 3 Jan 2027", or empty when there is no start.
  ///
  /// The year is written once when both ends share it. Not `intl`'s
  /// DateFormat on purpose: this is the whole of the formatting it needs, and
  /// a domain file that pulls in locale data is a domain file that cannot be
  /// tested without initialising it.
  static String dateSpan(DateTime? start, DateTime? end) {
    if (start == null) return '';
    String day(DateTime d) => '${d.day} ${_months[d.month - 1]}';
    if (end == null || _sameDay(start, end) || end.isBefore(start)) {
      return 'on ${day(start)} ${start.year}';
    }
    if (start.year == end.year) {
      return 'from ${day(start)} to ${day(end)} ${end.year}';
    }
    return 'from ${day(start)} ${start.year} to ${day(end)} ${end.year}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
