/// How trustworthy a player's public performance numbers are, for the
/// purpose of a scout deciding whether to act on them.
///
/// This is the §5 core-data-model `verification_tier` column
/// (`self | scorer_verified | association_verified`) and the §6 Module C
/// "Verification tiers: self → scorer-verified → association-verified"
/// filter, given a Dart shape.
///
/// Deliberately **not** the same type as `VerificationTier` in
/// `core/models/enums.dart` (`casual` / `sanctioned`), even though both are
/// about trust. That one grades a single *match result* — was this fixture
/// officiated closely enough to move a rating aggressively. This one grades
/// a *player's whole profile* as a scout would read it: has anyone besides
/// the player themselves ever confirmed who they are and what they have
/// done. A player can have plenty of `sanctioned` matches scored by a
/// stranger with no relationship to them and still be `self` here if no
/// scorer or association has specifically vouched for their identity —
/// conflating the two would let a pile of casual friendly matches read as
/// scout-grade verification just because a scorer happened to be assigned.
enum PlayerVerificationTier {
  /// Everything about this profile — including the claimed identity — comes
  /// from the player (or their guardian) alone. Lowest trust; a scout
  /// should treat the numbers as a lead to follow up on, not a fact.
  self('self', 'Self-reported', 0),

  /// A scorer who ran at least one of this player's matches has vouched for
  /// them being who they claim to be.
  scorerVerified('scorer_verified', 'Scorer-verified', 1),

  /// A district/state sports association has verified the player, typically
  /// as part of registering them for a sanctioned trial or competition.
  /// Highest trust — the tier the SAI/SATS talent pipeline this module feeds
  /// (§6 Module C) ultimately needs before acting on a lead.
  associationVerified('association_verified', 'Association-verified', 2);

  const PlayerVerificationTier(this.wire, this.label, this.rank);

  final String wire;
  final String label;

  /// Ordinal for "at least this trustworthy" filtering — see
  /// `TalentSearchFilters.minVerificationTier`. Higher is more trusted.
  final int rank;

  bool atLeast(PlayerVerificationTier floor) => rank >= floor.rank;

  static PlayerVerificationTier fromWire(String? w) =>
      PlayerVerificationTier.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => PlayerVerificationTier.self,
      );
}
