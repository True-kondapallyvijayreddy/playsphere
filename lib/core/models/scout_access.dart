import '../../domain/scout/talent_profile.dart';

/// One player's presence on a scout's watchlist or shortlist.
///
/// Carries [consentRecordId] — the `GuardianConsent.id` that was checked and
/// found active at the moment this player was added — so that even after
/// the entry has sat untouched for months, there is a permanent, auditable
/// answer to "what gave this scout permission to add this specific minor".
/// It is `null` for an adult player, for whom no guardian consent record
/// ever applies.
///
/// This field is a historical record of the check made *at add time*. It is
/// deliberately **not** treated as a standing guarantee that the player is
/// still visible today — consent can be revoked at any moment after an
/// entry is added, and per §2.7 that revocation must take effect
/// immediately. Anything that reads this list back for display must
/// re-run the consent check at read time (see `scout_access_ops.dart`'s
/// `visibleWatchlist`/`visibleShortlist`) rather than trusting that a player
/// who was visible when added is still visible now.
class ScoutListEntry {
  const ScoutListEntry({
    required this.playerId,
    required this.addedAt,
    this.consentRecordId,
    this.note,
  });

  final String playerId;
  final DateTime addedAt;
  final String? consentRecordId;
  final String? note;

  ScoutListEntry copyWith({String? note}) => ScoutListEntry(
        playerId: playerId,
        addedAt: addedAt,
        consentRecordId: consentRecordId,
        note: note ?? this.note,
      );

  Map<String, Object?> toMap() => {
        'playerId': playerId,
        'addedAt': addedAt.toIso8601String(),
        'consentRecordId': consentRecordId,
        'note': note,
      };

  @override
  bool operator ==(Object other) =>
      other is ScoutListEntry &&
      other.playerId == playerId &&
      other.addedAt == addedAt &&
      other.consentRecordId == consentRecordId &&
      other.note == note;

  @override
  int get hashCode => Object.hash(playerId, addedAt, consentRecordId, note);
}

enum TrialInviteStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  withdrawn('withdrawn');

  const TrialInviteStatus(this.wire);
  final String wire;

  static TrialInviteStatus fromWire(String? w) =>
      TrialInviteStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => TrialInviteStatus.pending,
      );
}

/// A scout's invitation for one player to attend a trial — the terminal step
/// of the §6 Module C talent-discovery funnel this module feeds into
/// `lib/domain/gov`'s "identified → trialed → selected" KPI.
///
/// Same audit posture as [ScoutListEntry]: [consentRecordId] records what
/// justified the invite at the moment it was sent, not a claim that consent
/// still holds — see [ScoutListEntry]'s doc for why that distinction
/// matters.
class TrialInvite {
  const TrialInvite({
    required this.id,
    required this.playerId,
    required this.invitedAt,
    this.status = TrialInviteStatus.pending,
    this.respondedAt,
    this.message,
    this.consentRecordId,
  });

  final String id;
  final String playerId;
  final DateTime invitedAt;
  final TrialInviteStatus status;
  final DateTime? respondedAt;
  final String? message;
  final String? consentRecordId;

  TrialInvite copyWith({
    TrialInviteStatus? status,
    DateTime? respondedAt,
  }) =>
      TrialInvite(
        id: id,
        playerId: playerId,
        invitedAt: invitedAt,
        status: status ?? this.status,
        respondedAt: respondedAt ?? this.respondedAt,
        message: message,
        consentRecordId: consentRecordId,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'playerId': playerId,
        'invitedAt': invitedAt.toIso8601String(),
        'status': status.wire,
        'respondedAt': respondedAt?.toIso8601String(),
        'message': message,
        'consentRecordId': consentRecordId,
      };
}

/// A scout's account state: the §5 `scout_access` entity — "scout_user_id,
/// scope filters, consent records (guardian consent for minors),
/// watchlists, shortlists, trial_invites".
///
/// A plain, immutable value object. All mutation happens through the pure
/// functions in `lib/domain/scout/scout_access_ops.dart`, which — critically
/// — are the functions responsible for enforcing that a minor is never
/// added to any list here without a currently-valid consent check (see that
/// file's doc comment). This class itself has no invariant-enforcing
/// constructor because it has no invariant to enforce beyond "these are
/// lists of entries" — the safety property lives in how entries get added,
/// not in the shape of the container.
class ScoutAccess {
  const ScoutAccess({
    required this.scoutUserId,
    this.defaultFilters = TalentSearchFilters.none,
    this.watchlist = const [],
    this.shortlist = const [],
    this.trialInvites = const [],
  });

  final String scoutUserId;

  /// The scout's saved default search filters, reapplied every time they
  /// open talent search. Filters alone never grant visibility — see
  /// `TalentSearchFilters`'s doc comment on why this type deliberately knows
  /// nothing about consent.
  final TalentSearchFilters defaultFilters;

  final List<ScoutListEntry> watchlist;
  final List<ScoutListEntry> shortlist;
  final List<TrialInvite> trialInvites;

  bool isWatchlisted(String playerId) =>
      watchlist.any((e) => e.playerId == playerId);

  bool isShortlisted(String playerId) =>
      shortlist.any((e) => e.playerId == playerId);

  ScoutAccess copyWith({
    TalentSearchFilters? defaultFilters,
    List<ScoutListEntry>? watchlist,
    List<ScoutListEntry>? shortlist,
    List<TrialInvite>? trialInvites,
  }) =>
      ScoutAccess(
        scoutUserId: scoutUserId,
        defaultFilters: defaultFilters ?? this.defaultFilters,
        watchlist: watchlist ?? this.watchlist,
        shortlist: shortlist ?? this.shortlist,
        trialInvites: trialInvites ?? this.trialInvites,
      );
}
