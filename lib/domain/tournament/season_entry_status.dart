import '../../core/models/competition.dart';
import '../../core/models/enums.dart';

/// What a season's Register button should say to the person looking at it.
///
/// ## Why this is a type and not an `if` on each screen
///
/// "Register for this season" was drawn whenever any draw in the season was
/// taking entries, and it kept being drawn afterwards, because nothing on the
/// page ever asked whether the person had already entered. A club would enter,
/// the host would confirm them, and the season would go on inviting them to
/// register — which reads as "it did not work", and the honest guess after
/// that is to press it again.
///
/// Three screens ask the question — the season page, the register page, and
/// each event's own entry card — so the answer is computed once, here, from
/// two facts: which draws are open, and which draws this person already holds
/// a live entry in (see `profileEntryRefsProvider`, which counts an entry as
/// theirs if they entered, are in the squad that entered, or filed it).
///
/// Withdrawn and rejected entries are deliberately NOT live: somebody who
/// pulled out is not registered, and a page that tells them they are has taken
/// away their way back in.
class SeasonEntryStatus {
  const SeasonEntryStatus({
    required this.open,
    required this.entered,
    required this.clubEntersForMe,
  });

  /// The empty answer, for a season whose events have not loaded yet. Draws
  /// nothing rather than flashing a Register button that may be wrong.
  static const none = SeasonEntryStatus(
    open: [],
    entered: [],
    clubEntersForMe: false,
  );

  /// Draws currently taking entries — `registrationIsOpen`, which already
  /// accounts for a passed deadline, a suspended event and a full field.
  final List<Competition> open;

  /// Draws in this season this person already holds a live entry in, open or
  /// not. An entry in a draw whose entries have since closed still counts:
  /// they are in it, and that is what they came to the page to find out.
  final List<Competition> entered;

  /// True when this person is in a club the host invited and is not one of
  /// its organizers — the entry is the club's to make, so a personal Register
  /// button is not merely redundant, it is the wrong instruction. The
  /// invited-club block says what they can do instead.
  final bool clubEntersForMe;

  /// Open draws they have not entered yet — what a Register button would
  /// actually take them to.
  List<Competition> get openAndNotEntered {
    final done = {for (final c in entered) c.id};
    return [
      for (final c in open)
        if (!done.contains(c.id)) c,
    ];
  }

  bool get hasEntry => entered.isNotEmpty;

  /// Nothing left to enter, because they are in everything that is open.
  bool get inEverythingOpen => hasEntry && openAndNotEntered.isEmpty;

  /// Whether to offer a way in at all.
  bool get canStillEnter => !clubEntersForMe && openAndNotEntered.isNotEmpty;

  /// The line the button or chip carries. Short, and specific about how many
  /// draws are involved, because a season is several tournaments under one
  /// roof and "registered" without a count is the ambiguity that makes an
  /// organizer re-enter a side they have already entered.
  String label({required String seasonNoun}) {
    if (inEverythingOpen) {
      return entered.length == 1
          ? 'Already registered'
          : 'Already registered · ${entered.length} events';
    }
    if (hasEntry) {
      final left = openAndNotEntered.length;
      return 'Registered for ${entered.length} · '
          '$left more ${left == 1 ? 'event' : 'events'} open';
    }
    return 'Register for this $seasonNoun';
  }

  /// Builds the answer for one season.
  ///
  /// [entryRefs] is the `orgId/compId` set of live entries this profile holds
  /// anywhere — passing the whole set rather than filtering upstream keeps one
  /// definition of "a live entry" in one place.
  static SeasonEntryStatus of({
    required List<Competition> events,
    required Set<String> entryRefs,
    bool clubEntersForMe = false,
  }) {
    final open = <Competition>[];
    final entered = <Competition>[];
    for (final c in events) {
      // A single match names both sides when it is created and has no
      // registration phase at all — see `CompetitionFormat.isSingleMatch`.
      if (c.format.isSingleMatch) continue;
      if (c.status == CompetitionStatus.cancelled) continue;
      if (entryRefs.contains('${c.orgId}/${c.id}')) {
        entered.add(c);
      } else if (c.registrationIsOpen) {
        open.add(c);
      }
    }
    // Entered draws that are still open belong in both lists, so that
    // "3 entered, 1 more open" adds up the way a reader expects.
    for (final c in entered) {
      if (c.registrationIsOpen) open.add(c);
    }
    return SeasonEntryStatus(
      open: open,
      entered: entered,
      clubEntersForMe: clubEntersForMe,
    );
  }
}
