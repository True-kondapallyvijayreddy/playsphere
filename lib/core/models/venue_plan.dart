import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';
import 'venue.dart';

/// One playing window inside a day — "Morning, 08:00–12:00".
///
/// ## Why a session and not just an opening hour
///
/// A ground that says it is available 08:00–19:00 is not available 08:00–19:00.
/// It is available in the morning, shut for lunch and the heat, and open again
/// in the evening. A scheduler told only the outer bounds will cheerfully call
/// a match for 13:00, and the organizer discovers it when nobody turns up.
///
/// Minutes from midnight rather than an hour, because a session that starts at
/// 08:30 is completely ordinary and an integer hour cannot say it.
class DaySession {
  const DaySession({
    required this.startMinute,
    required this.endMinute,
    this.label = '',
  });

  /// Minutes from local midnight, inclusive.
  final int startMinute;

  /// Minutes from local midnight, exclusive.
  final int endMinute;

  /// "Morning", "Evening" — shown to the organizer, never parsed.
  final String label;

  int get minutes => endMinute - startMinute;

  bool get isValid =>
      startMinute >= 0 && endMinute > startMinute && endMinute <= 24 * 60;

  /// This session on a particular date, as a real pair of instants.
  ({DateTime start, DateTime end}) on(DateTime day) => (
        start: DateTime(day.year, day.month, day.day)
            .add(Duration(minutes: startMinute)),
        end: DateTime(day.year, day.month, day.day)
            .add(Duration(minutes: endMinute)),
      );

  String get timeLabel =>
      '${formatMinutes(startMinute)}–${formatMinutes(endMinute)}';

  /// "08:30" from 510. Public because every editor that lets an organizer set
  /// a session or a blackout has to print the same clock, and three private
  /// copies of this drifted apart the first time one of them was localised.
  static String formatMinutes(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final min = (m % 60).toString().padLeft(2, '0');
    return '$h:$min';
  }

  static DaySession fromMap(Map<String, dynamic> m) => DaySession(
        startMinute: Fs.integer(m['startMinute'], 9 * 60),
        endMinute: Fs.integer(m['endMinute'], 19 * 60),
        label: Fs.str(m['label']),
      );

  Map<String, Object?> toMap() => {
        'startMinute': startMinute,
        'endMinute': endMinute,
        'label': label,
      };

  static List<DaySession> listFrom(Object? v) => v is List
      ? v
          .whereType<Map>()
          .map((m) => DaySession.fromMap(Map<String, dynamic>.from(m)))
          .where((s) => s.isValid)
          .toList(growable: false)
      : const [];
}

/// A period this venue cannot be used, on one named date.
///
/// Whole-day when both times are null — which is how "June 13 ✕" on the
/// availability calendar is stored. There is deliberately no separate
/// "available dates" list: two ways to say a ground is shut is two ways for
/// them to disagree.
class VenueBlackout {
  const VenueBlackout({
    required this.date,
    this.startMinute,
    this.endMinute,
    this.reason,
  });

  /// Local midnight of the affected day. Only the date part is read.
  final DateTime date;

  /// Minutes from midnight. Both null means the whole day is gone.
  final int? startMinute;
  final int? endMinute;

  /// "School exams", "Ground being re-laid" — shown beside the date so an
  /// organizer looking at a hole in the timetable knows why it is there.
  final String? reason;

  bool get isWholeDay => startMinute == null || endMinute == null;

  bool coversDay(DateTime day) =>
      date.year == day.year && date.month == day.month && date.day == day.day;

  /// The instants this blackout removes on its own date.
  ({DateTime start, DateTime end}) get window {
    final midnight = DateTime(date.year, date.month, date.day);
    if (isWholeDay) {
      return (start: midnight, end: midnight.add(const Duration(days: 1)));
    }
    return (
      start: midnight.add(Duration(minutes: startMinute!)),
      end: midnight.add(Duration(minutes: endMinute!)),
    );
  }

  String get timeLabel => isWholeDay
      ? 'All day'
      : '${DaySession.formatMinutes(startMinute!)}–'
          '${DaySession.formatMinutes(endMinute!)}';

  static VenueBlackout? fromMap(Map<String, dynamic> m) {
    final date = Fs.dateOrNull(m['date']);
    if (date == null) return null;
    return VenueBlackout(
      date: DateTime(date.year, date.month, date.day),
      startMinute: Fs.intOrNull(m['startMinute']),
      endMinute: Fs.intOrNull(m['endMinute']),
      reason: Fs.strOrNull(m['reason']),
    );
  }

  Map<String, Object?> toMap() => {
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'startMinute': startMinute,
        'endMinute': endMinute,
        'reason': reason,
      };

  static List<VenueBlackout> listFrom(Object? v) => v is List
      ? v
          .whereType<Map>()
          .map((m) => VenueBlackout.fromMap(Map<String, dynamic>.from(m)))
          .whereType<VenueBlackout>()
          .toList(growable: false)
      : const [];
}

/// How one season is using one venue, at
/// `orgs/{orgId}/tournaments/{tournamentId}/venuePlans/{venueId}`.
///
/// ## Why this is not on the [Venue] document
///
/// A venue is a building: its name, its courts and the hours its gate is
/// unlocked are facts that outlive any one season. *Which days of June a
/// school lends its ground, how long a match of this competition runs on it,
/// and how many the organizer is willing to run in a day* are facts about the
/// season, and writing them onto the building would mean the August season
/// silently inherits the June season's blackouts.
///
/// So the plan is season-scoped and every field falls back to the venue when
/// it is left unset. A season that never opens the venue planner schedules
/// exactly as it did before this existed.
class VenuePlan {
  const VenuePlan({
    required this.venueId,
    this.venueName = '',
    this.sportIds = const {},
    this.courtIds = const {},
    this.sessions = const [],
    this.blackouts = const [],
    this.matchMinutes,
    this.turnaroundMinutes,
    this.maxMatchesPerCourtPerDay = 0,
    this.firstDay,
    this.lastDay,
  });

  final String venueId;

  /// Denormalized so a planner screen can list venues without a read per row.
  final String venueName;

  /// The sports allowed here. Empty means any.
  ///
  /// This is the constraint an organizer states as "the TT hall is for table
  /// tennis" — and it is a different statement from an event naming its
  /// grounds. Both are enforced: the event says where it may go, the venue
  /// says what it will take, and a match needs both to agree.
  final Set<String> sportIds;

  /// The playing areas of this venue that this season may use — court ids
  /// into [Venue.courts]. Empty means every usable court.
  ///
  /// The half of a hall lent to a school for a week is exactly this: the
  /// building has six tables, the season has four of them.
  final Set<String> courtIds;

  /// The playing windows inside a day. Empty falls back to the venue's own
  /// opening hours as one session.
  final List<DaySession> sessions;

  final List<VenueBlackout> blackouts;

  /// How long one match takes here. Null falls back to the event's own
  /// `ScheduleConfig.matchMinutes`.
  ///
  /// On the venue rather than only on the event because the constraint is
  /// often physical — the cricket ground runs three-hour matches whichever
  /// competition is on it.
  final int? matchMinutes;

  /// Court reset between two matches on the same playing area. Null falls back
  /// to the event's changeover.
  final int? turnaroundMinutes;

  /// The organizer's own ceiling on matches per playing area per day. Zero
  /// means they did not name one.
  ///
  /// Deliberately *not* the same thing as what fits: see
  /// `VenueCapacity.effectiveMaxPerCourtPerDay`, which takes the stricter of
  /// this and the arithmetic. An organizer who types 4 into a window that
  /// holds 3 has stated a preference, not created a fourth slot.
  final int maxMatchesPerCourtPerDay;

  /// The first and last day this venue is lent to the season, inclusive.
  /// Null on either end falls back to the season's own span.
  final DateTime? firstDay;
  final DateTime? lastDay;

  bool get isUnrestricted =>
      sportIds.isEmpty &&
      courtIds.isEmpty &&
      sessions.isEmpty &&
      blackouts.isEmpty &&
      matchMinutes == null &&
      turnaroundMinutes == null &&
      maxMatchesPerCourtPerDay == 0 &&
      firstDay == null &&
      lastDay == null;

  /// Whether an event of [sportId] may use this venue at all.
  bool allowsSport(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);

  /// Whether [court] is one of the playing areas this season has here.
  bool allowsCourt(Court court) =>
      court.isAvailable && (courtIds.isEmpty || courtIds.contains(court.id));

  /// The sessions to schedule inside on any given day, falling back to the
  /// building's own hours when the organizer named none.
  List<DaySession> sessionsFor(Venue venue) {
    if (sessions.isNotEmpty) return sessions;
    return [
      DaySession(
        startMinute: venue.openHour * 60,
        endMinute: venue.closeHour * 60,
        label: 'All day',
      ),
    ];
  }

  /// Whether this venue is lent to the season on [day] at all — its own date
  /// range, and no whole-day blackout.
  bool servesDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final first = firstDay;
    if (first != null && d.isBefore(DateTime(first.year, first.month, first.day))) {
      return false;
    }
    final last = lastDay;
    if (last != null && d.isAfter(DateTime(last.year, last.month, last.day))) {
      return false;
    }
    for (final b in blackouts) {
      if (b.isWholeDay && b.coversDay(d)) return false;
    }
    return true;
  }

  factory VenuePlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return VenuePlan(
      venueId: doc.id,
      venueName: Fs.str(d['venueName']),
      sportIds: Fs.strList(d['sportIds']).toSet(),
      courtIds: Fs.strList(d['courtIds']).toSet(),
      sessions: DaySession.listFrom(d['sessions']),
      blackouts: VenueBlackout.listFrom(d['blackouts']),
      matchMinutes: Fs.intOrNull(d['matchMinutes']),
      turnaroundMinutes: Fs.intOrNull(d['turnaroundMinutes']),
      maxMatchesPerCourtPerDay: Fs.integer(d['maxMatchesPerCourtPerDay']),
      firstDay: Fs.dateOrNull(d['firstDay']),
      lastDay: Fs.dateOrNull(d['lastDay']),
    );
  }

  Map<String, Object?> toMap() => {
        'venueName': venueName,
        'sportIds': sportIds.toList()..sort(),
        'courtIds': courtIds.toList()..sort(),
        'sessions': [for (final s in sessions) s.toMap()],
        'blackouts': [for (final b in blackouts) b.toMap()],
        'matchMinutes': matchMinutes,
        'turnaroundMinutes': turnaroundMinutes,
        'maxMatchesPerCourtPerDay': maxMatchesPerCourtPerDay,
        'firstDay': Fs.ts(firstDay),
        'lastDay': Fs.ts(lastDay),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// The same terms, pointing at a different venue id.
  ///
  /// The counterpart of [Venue.withId] and used in the same one place: a
  /// ground added on the season create form carries a local id, and once the
  /// venue is actually written the plan built against it has to be re-keyed
  /// to the real one. Kept out of [copyWith] for the same reason the venue
  /// keeps it out — the id is the document, not a field.
  VenuePlan rekeyed(String venueId) => VenuePlan(
        venueId: venueId,
        venueName: venueName,
        sportIds: sportIds,
        courtIds: courtIds,
        sessions: sessions,
        blackouts: blackouts,
        matchMinutes: matchMinutes,
        turnaroundMinutes: turnaroundMinutes,
        maxMatchesPerCourtPerDay: maxMatchesPerCourtPerDay,
        firstDay: firstDay,
        lastDay: lastDay,
      );

  VenuePlan copyWith({
    String? venueName,
    Set<String>? sportIds,
    Set<String>? courtIds,
    List<DaySession>? sessions,
    List<VenueBlackout>? blackouts,
    int? matchMinutes,
    int? turnaroundMinutes,
    int? maxMatchesPerCourtPerDay,
    DateTime? firstDay,
    DateTime? lastDay,
    bool clearMatchMinutes = false,
    bool clearTurnaround = false,
    bool clearFirstDay = false,
    bool clearLastDay = false,
  }) =>
      VenuePlan(
        venueId: venueId,
        venueName: venueName ?? this.venueName,
        sportIds: sportIds ?? this.sportIds,
        courtIds: courtIds ?? this.courtIds,
        sessions: sessions ?? this.sessions,
        blackouts: blackouts ?? this.blackouts,
        matchMinutes:
            clearMatchMinutes ? null : (matchMinutes ?? this.matchMinutes),
        turnaroundMinutes: clearTurnaround
            ? null
            : (turnaroundMinutes ?? this.turnaroundMinutes),
        maxMatchesPerCourtPerDay:
            maxMatchesPerCourtPerDay ?? this.maxMatchesPerCourtPerDay,
        firstDay: clearFirstDay ? null : (firstDay ?? this.firstDay),
        lastDay: clearLastDay ? null : (lastDay ?? this.lastDay),
      );
}
