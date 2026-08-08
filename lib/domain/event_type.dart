import 'package:flutter/material.dart';

/// What kind of thing an organizer is about to create.
///
/// ## Why this is the FIRST question
///
/// "New event" used to open straight onto one form — a name, a sport, a
/// format, a participation model — which quietly assumed every event is a
/// single-sport competition that fills by registration. Three of the four
/// things clubs actually create do not fit that shape:
///
/// - a **season** spans several sports and is the thing a school or a village
///   community runs, with a separate entry list per sport;
/// - a **single match** has both sides named on the spot and no field to
///   assemble, so every registration question on the form is discarded;
/// - a **challenge** is addressed to another club and does not have entries at
///   all until they accept.
///
/// Asking the type first means each flow can ask only what its own shape
/// needs, instead of one form asking the union of all four and ignoring the
/// answers that do not apply.
enum EventType {
  season(
    wire: 'season',
    label: 'Season',
    tagline: 'Several sports, one calendar',
    description:
        'For a school, college, community or village running many sports '
        'together. You pick the sports, set how many entries each takes, and '
        'decide whether clubs outside yours may enter.',
    icon: Icons.calendar_month_outlined,
  ),

  tournament(
    wire: 'tournament',
    label: 'Tournament',
    tagline: 'One sport, open for registrations',
    description:
        'A single-sport competition — a badminton championship, a cricket '
        'knockout. Create it and ask for registrations.',
    icon: Icons.emoji_events_outlined,
  ),

  singleMatch(
    wire: 'single_match',
    label: 'Single match',
    tagline: 'One match, sides named now',
    description:
        'One match against a person or a club, played now or scheduled. No '
        'registration and no draw — it still counts towards everyone\'s '
        'record.',
    icon: Icons.sports_score_outlined,
  ),

  challenge(
    wire: 'challenge',
    label: 'Challenge another club',
    tagline: 'Propose a match to someone else',
    description:
        'Send a challenge to another club or person. They accept, decline or '
        'counter-propose a time, and the fixture is created when they agree.',
    icon: Icons.sports_kabaddi_outlined,
  );

  const EventType({
    required this.wire,
    required this.label,
    required this.tagline,
    required this.description,
    required this.icon,
  });

  final String wire;
  final String label;

  /// One line under the name in the chooser.
  final String tagline;

  /// The paragraph that says what this type is FOR, in the words a club
  /// secretary would use rather than the product's own vocabulary.
  final String description;

  final IconData icon;

  static EventType fromWire(String? w) => EventType.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => EventType.tournament,
      );

  /// Whether this type gathers a field through registration.
  ///
  /// False for a single match and a challenge, where both sides are known by
  /// the time anything is written — which is precisely why showing them a
  /// capacity, a waitlist and a participation model was asking questions
  /// whose answers get thrown away.
  bool get takesRegistrations =>
      this == EventType.season || this == EventType.tournament;

  /// Whether this type spans more than one sport.
  bool get isMultiSport => this == EventType.season;
}
