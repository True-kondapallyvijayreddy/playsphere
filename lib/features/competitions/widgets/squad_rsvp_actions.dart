import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/announcement.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/squad_entry.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';
import '../../home/home_providers.dart';

/// The join between "who is free on Sunday" and one club's side of a match.
///
/// ## The step that was missing
///
/// A club could ask its members who was available, and a club could fill its
/// side of a challenge. Nothing connected the two. `MatchCall` carried a
/// sport, a date, a venue and a headcount — and no fixture — so an organizer
/// read the poll with their eyes and retyped every name into the team sheet.
/// That is the manual step the availability call exists to remove, still
/// there for the one kind of match where two clubs cannot help each other
/// with it.
///
/// Worse than the typing: the two lists then drifted. Somebody who pulled out
/// of the poll stayed on the sheet, because nothing joined them.
///
/// ## What this does
///
/// Two buttons and no form. "Ask who's free" posts an ordinary availability
/// call on this club's own board, prefilled from the fixture and tagged with
/// [FixtureCallTarget] so the answers know which match and which side they
/// belong to. Members see the same card they always see and tap "In". Then
/// "Add the N who said In" moves them onto this side's squad in one write.
///
/// Both clubs do this independently on their own boards. Neither needs the
/// other's phone numbers, and neither can touch the other's squad — the side
/// is derived from the club, here and in `firestore.rules`.
class SquadRsvpActions extends ConsumerStatefulWidget {
  const SquadRsvpActions({
    super.key,
    required this.fixture,
    required this.orgId,
    required this.side,
    required this.entries,
  });

  final Fixture fixture;

  /// The club acting — always the caller's own side of the match.
  final String orgId;
  final String side;

  /// This side's squad as it stands, so the button can count who is genuinely
  /// new rather than offering to add people who are already in.
  final List<SquadEntry> entries;

  @override
  ConsumerState<SquadRsvpActions> createState() => _SquadRsvpActionsState();
}

class _SquadRsvpActionsState extends ConsumerState<SquadRsvpActions> {
  bool _busy = false;

  /// The availability calls this club has posted about THIS match.
  ///
  /// Matched on the fixture id rather than on the date: a club may well have
  /// two calls out for the same evening, and pulling the wrong one's yeses
  /// onto a team sheet is the failure this whole widget exists to prevent.
  ///
  /// The second clause is the one that makes the challenge flow whole. A club
  /// that asked "we have challenged them, who is in?" did so BEFORE this
  /// fixture existed, so that call can carry no fixture id — it carries the
  /// challenge's, through [ChallengeCallTarget]. `acceptChallenge` stamps the
  /// same id onto the fixture as its `sourceId`, so the two ends meet here and
  /// an organizer who asked a fortnight ago does not have to ask again.
  ///
  /// No side test on that clause, and none is needed: a challenge call sits on
  /// the board of the club that posted it, this widget only ever reads its own
  /// club's board, and a club is on exactly one side of a challenge.
  List<Announcement> _callsForThisMatch(WidgetRef ref) {
    final f = widget.fixture;
    final challengeId =
        f.sourceType == MatchSource.challenge ? f.sourceId : null;
    return [
      for (final a in ref.watch(matchRsvpsProvider(widget.orgId)).valueOrNull ??
          const <Announcement>[])
        if ((a.match?.forFixture?.fixtureId == f.id &&
                a.match?.forFixture?.side == widget.side) ||
            (challengeId != null &&
                a.match?.forChallenge?.challengeId == challengeId))
          a,
    ];
  }

  Future<void> _ask() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    final uid = ref.read(currentUidProvider);
    if (me == null || uid == null) return;

    final f = widget.fixture;
    final opponent =
        widget.side == 'a' ? f.entrantBName : f.entrantAName;

    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).createSquadCallRsvp(
            orgId: widget.orgId,
            authorUid: uid,
            authorName: me.displayName,
            title: 'Who is in against $opponent?',
            content: 'Tap In if you can play. The squad is picked from '
                'whoever says yes.',
            match: MatchCall(
              sportId: f.sport,
              // The match already has a date and a ground; asking the
              // organizer to type them again is how the two records end up
              // disagreeing about when kick-off is.
              matchDate: f.scheduledAt ?? DateTime.now(),
              venue: f.venue ?? '',
              // Per SIDE, not both sides together — unlike a club kickabout,
              // where one call fills two teams. Zero when the club set no
              // capacity, which means "as many as turn up".
              maxPlayers: f.squadCallFor(widget.side).capacity ?? 0,
            ),
            target: FixtureCallTarget(
              orgId: f.orgId,
              compId: f.compId,
              fixtureId: f.id,
              side: widget.side,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Asked your club. Answers land here and on their feed.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pullIn(List<Membership> members, Set<String> uids) async {
    final byUid = {for (final m in members) m.uid: m};
    final players = [
      for (final uid in uids)
        if (byUid[uid] != null)
          (
            uid: uid,
            displayName: byUid[uid]!.displayName,
            photoUrl: byUid[uid]!.photoUrl,
          ),
    ];
    if (players.isEmpty) return;

    setState(() => _busy = true);
    try {
      final added = await ref.read(competitionRepositoryProvider).addToSquad(
            fixture: widget.fixture,
            forOrgId: widget.orgId,
            players: players,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added == 0
                ? 'Everyone who said In is already in the squad.'
                : '$added added to your squad.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calls = _callsForThisMatch(ref);
    final members = (ref.watch(orgMembersProvider(widget.orgId)).valueOrNull ??
            const <Membership>[])
        .where((m) => m.isActive)
        .toList();

    // Everyone who said "In" across every call this club posted for this
    // side, minus the people already on the sheet. A club that asked twice —
    // once a fortnight out and once on the Friday — means both answers, not
    // whichever it asked last.
    final alreadyIn = {
      for (final e in widget.entries)
        if (e.status.occupiesSlot) e.uid,
    };
    final waiting = <String>{
      for (final c in calls) ...?c.poll?.votersFor(Rsvp.yes),
    }..removeAll(alreadyIn);

    // A member who has left the club since answering is dropped: they are on
    // the poll but they are not this club's player any more.
    final known = {for (final m in members) m.uid};
    final addable = waiting.where(known.contains).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (calls.isEmpty)
          OutlinedButton.icon(
            onPressed: _busy ? null : _ask,
            icon: const Icon(Icons.how_to_reg_outlined, size: 18),
            label: const Text("Ask our members who's free"),
          )
        else ...[
          if (addable.isEmpty)
            Text(
              waiting.isEmpty
                  ? 'Asked your club — nobody new has said In yet.'
                  : 'Everyone who said In is already in the squad.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _pullIn(members, addable),
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: Text(
                'Add the ${addable.length} who said In',
              ),
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : _ask,
            child: const Text('Ask again'),
          ),
        ],
      ],
    );
  }
}
