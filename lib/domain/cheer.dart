import 'package:flutter/material.dart';

/// The ways a person watching can make a noise.
///
/// ## Why this is not a like button
///
/// A grassroots match has an audience of eleven people on their phones in
/// other places — a parent at work, a clubmate on a bus, a cousin in another
/// city. They can already see the score. What they cannot do is be heard, and
/// the difference between following a scoreboard and supporting a team is
/// entirely whether the players know anyone is watching.
///
/// So a cheer is addressed to a SIDE, not to the match. "Someone is cheering"
/// is a fact about a match; "fourteen people are behind you" is a fact about
/// your team, and it is the second one a fifteen-year-old at the crease
/// actually wants.
///
/// Kept small on purpose. Five reactions that mean recognisably different
/// things beat twenty that blur — and every one has to read at a glance on a
/// ₹8k phone in sunlight, which rules out anything subtle.
enum Cheer {
  clap('clap', '👏', 'Well played'),
  fire('fire', '🔥', 'On fire'),
  strong('strong', '💪', 'Keep going'),
  heart('heart', '❤️', 'With you'),
  wow('wow', '😮', 'Unbelievable');

  const Cheer(this.wire, this.emoji, this.label);

  final String wire;
  final String emoji;

  /// What it means in words, for the tooltip and for screen readers — an
  /// emoji-only control is unusable to anyone who cannot see it.
  final String label;

  static Cheer? fromWire(String? w) {
    for (final c in Cheer.values) {
      if (c.wire == w) return c;
    }
    return null;
  }
}

/// A live tally of who is cheering for whom in one match.
///
/// Counts per side per reaction, plus what THIS viewer sent, because the
/// button has to be able to show that your own cheer landed. Without that the
/// only feedback is a number that may not visibly move in a crowd.
@immutable
class CheerTally {
  const CheerTally({
    this.forA = const {},
    this.forB = const {},
    this.mine,
    this.mineSide,
  });

  final Map<Cheer, int> forA;
  final Map<Cheer, int> forB;

  /// This viewer's own reaction, if they have sent one.
  final Cheer? mine;

  /// Which side they sent it to — 'a' or 'b'.
  final String? mineSide;

  int get totalA => forA.values.fold(0, (a, b) => a + b);
  int get totalB => forB.values.fold(0, (a, b) => a + b);
  int get total => totalA + totalB;

  Map<Cheer, int> countsFor(String side) => side == 'a' ? forA : forB;

  /// The loudest reaction for a side, for the compact summary a match row
  /// shows. Null when nobody has cheered for them.
  Cheer? topFor(String side) {
    final counts = countsFor(side);
    if (counts.isEmpty) return null;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
  }
}
