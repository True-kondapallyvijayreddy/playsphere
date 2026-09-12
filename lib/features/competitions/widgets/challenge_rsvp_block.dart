import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/announcement.dart';
import '../../../core/models/challenge.dart';
import '../../../core/models/organization.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';
import '../../home/home_providers.dart';

/// "We have challenged them — who is in?", asked from the challenge itself.
///
/// ## The gap this fills
///
/// A challenge was a conversation between two admins. One issued it, the other
/// accepted, and the thirty people who would actually have to turn up found
/// out afterwards, usually on WhatsApp. Two things went wrong every time:
///
///  * The date was agreed before anybody knew who could make it, so a captain
///    who then could not raise eleven had to go back and apologise for a
///    fixture their own club had already committed to.
///  * The squad was assembled twice — once as a poll somebody read with their
///    eyes, and again as a team sheet somebody retyped.
///
/// Both halves already existed for matches that exist: an availability call is
/// an ordinary club poll (see [MatchCall]), and `SquadRsvpActions` moves its
/// yeses onto a team sheet. What was missing was the ability to ask BEFORE
/// there is a match — while the challenge is still an offer. That is what
/// [ChallengeCallTarget] adds, and this is where it is used.
///
/// The thread joins back up on its own: `acceptChallenge` stamps the challenge
/// id onto the fixture as its `sourceId`, so once the match exists the same
/// answers are found by the squad actions and moved onto the sheet with
/// nobody retyping a name.
///
/// ## Why the club chooses who to ask
///
/// A village club has a hundred and twenty members and an eleven-a-side match.
/// Asking all hundred and twenty produces a hundred and twenty notifications,
/// forty yeses, and a captain who now has to tell twenty-nine people they are
/// not playing — which is worse than never having asked them. So the sheet
/// offers both: ask everybody, which stays the default and is right for a club
/// of fifteen, or name the people who might actually travel. See
/// [MatchCall.invitedUids] for what naming them does and, importantly, does
/// not do.
class ChallengeRsvpBlock extends ConsumerStatefulWidget {
  const ChallengeRsvpBlock({
    super.key,
    required this.challenge,
    required this.orgId,
    required this.canManage,
  });

  final Challenge challenge;

  /// The club doing the asking — always the one whose screen this is. Both
  /// clubs can ask their own members independently, and neither ever sees the
  /// other's answers.
  final String orgId;

  /// Whether this viewer may put the question. Everybody sees the count; only
  /// an organizer can ask, or ask again.
  final bool canManage;

  @override
  ConsumerState<ChallengeRsvpBlock> createState() => _ChallengeRsvpBlockState();
}

class _ChallengeRsvpBlockState extends ConsumerState<ChallengeRsvpBlock> {
  bool _busy = false;

  Future<void> _ask(List<Membership> members) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    final uid = ref.read(currentUidProvider);
    if (me == null || uid == null) return;

    final c = widget.challenge;
    final opponent = c.opponentNameFor(widget.orgId);
    final incoming = c.isIncomingFor(widget.orgId);

    final result = await showModalBottomSheet<_AskTerms>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: _AskMembersSheet(
          challenge: c,
          orgId: widget.orgId,
          members: members,
          opponent: opponent,
          incoming: incoming,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).createChallengeRsvp(
            orgId: widget.orgId,
            authorUid: uid,
            authorName: me.displayName,
            title: incoming
                ? '$opponent have challenged us — who is in?'
                : 'We have challenged $opponent — who is in?',
            content: result.note,
            match: MatchCall(
              sportId: c.sportId,
              matchDate: _whenToAskAbout(c),
              venue: c.liveVenue ?? '',
              maxPlayers: result.playersNeeded,
            ),
            target: ChallengeCallTarget(
              challengeId: c.id,
              opponentName: opponent,
            ),
            invitedUids: result.invitedUids,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.invitedUids.isEmpty
                ? 'Asked the whole club. Answers land here and on their home '
                    'screen.'
                : 'Asked ${result.invitedUids.length} '
                    'member${result.invitedUids.length == 1 ? '' : 's'}. '
                    'Answers land here and on their home screen.',
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
    final c = widget.challenge;

    // A challenge nobody is going to play is not one to raise a squad for.
    // Accepted stays in, deliberately: the answers gathered before the match
    // existed are exactly what fills the team sheet after it does.
    if (c.isDeclined || c.isWithdrawn) return const SizedBox.shrink();

    final uid = ref.watch(currentUidProvider);
    final members =
        (ref.watch(orgMembersProvider(widget.orgId)).valueOrNull ??
                const <Membership>[])
            .where((m) => m.isActive)
            .toList();

    final calls = ref.watch(
      challengeRsvpsProvider((orgId: widget.orgId, challengeId: c.id)),
    );

    if (calls.isEmpty) {
      // Shown to ordinary members too, which it was not before. A member who
      // opens the challenge and finds no trace of a squad has no way to tell
      // "my club has not asked yet" from "this block is for organizers" — and
      // the first is a fact worth knowing, because it is the moment to say in
      // the club chat that you are free. The button stays organizers-only;
      // the state does not.
      return _Frame(
        children: [
          Text(
            widget.canManage
                ? 'Nobody in your club has been asked yet.'
                : 'Your club has not been asked who is in yet. When an '
                    'organizer puts the question, it lands on your home '
                    'screen.',
            style: theme.textTheme.bodySmall,
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy || members.isEmpty ? null : () => _ask(members),
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: const Text("Ask who's in"),
              ),
            ),
          ],
        ],
      );
    }

    final tally = _Tally.of(calls, members);
    final names = {for (final m in members) m.uid: m};

    // Whether this viewer was one of the people asked, and has not said. The
    // card is the place they are most likely to be standing when they think
    // about it — sending them off to another screen to find the question
    // their own club put to them is how an answer gets postponed.
    final asked = uid != null &&
        calls.any((a) => a.isAddressedTo(uid) && a.poll?.voteOf(uid) == null);

    return _Frame(
      children: [
        Text(tally.line, style: theme.textTheme.bodySmall),
        if (tally.yes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in tally.yes)
                Chip(
                  avatar: PsAvatar(
                    name: names[u]?.displayName ?? 'Member',
                    photoUrl: names[u]?.photoUrl,
                    seed: u,
                    size: 20,
                  ),
                  label: Text(names[u]?.displayName ?? 'Member'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (asked)
              FilledButton.tonalIcon(
                onPressed: () => context.push(Routes.matchRsvps),
                icon: const Icon(Icons.how_to_vote_outlined, size: 18),
                label: const Text('Answer'),
              ),
            if (widget.canManage)
              TextButton(
                onPressed: _busy || members.isEmpty ? null : () => _ask(members),
                child: const Text('Ask more members'),
              ),
            // For everybody, not just organizers. A member who already said In
            // and now cannot play was being shown no door at all from here —
            // the call is where the answer is changed, and it is also where
            // the discussion about the ground is.
            if (!asked)
              TextButton(
                onPressed: () => context.push(Routes.matchRsvps),
                child: const Text('Open the call'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Puts the question to the whole club, without waiting to be asked to.
///
/// ## Why this fires on its own
///
/// The block above has always been able to ask — but only when an organizer
/// remembered to tap it, and the moment they most reliably forgot was the one
/// that mattered: right after issuing the challenge, when the club still had
/// time to say no. Members found out there was a fixture when somebody
/// messaged them, which is the exact WhatsApp step this whole flow exists to
/// delete.
///
/// So the call now goes out with the challenge itself, open to everybody. An
/// organizer who wanted to ask twenty rather than a hundred and twenty still
/// can — "Ask more members" is unchanged, the tallies add up across calls, and
/// a second, narrower call takes nothing away from this one.
///
/// Silent on failure, and deliberately: the challenge is already written and
/// is the thing the organizer asked for. A red banner over a challenge that
/// WAS sent, because the poll beside it was not, would read as "the challenge
/// failed" and send them round the loop again. The block renders its
/// "nobody has been asked yet" state, which is both true and fixable in one
/// tap.
Future<void> postChallengeAvailabilityCall({
  required WidgetRef ref,
  required String orgId,
  required String challengeId,
  required String opponentName,
  required String sportId,
  required DateTime when,
  required String venue,
  required bool incoming,
}) async {
  try {
    // Read inside the guard, not before it. Every caller reaches this after
    // awaiting a write, so the screen may already have been disposed — and a
    // read from a dead WidgetRef throws exactly like a failed write, with the
    // same correct outcome: the challenge stands and the block shows "nobody
    // has been asked yet".
    final me = ref.read(currentUserProvider).valueOrNull;
    final uid = ref.read(currentUidProvider);
    if (me == null || uid == null) return;

    await ref.read(communityRepositoryProvider).createChallengeRsvp(
          orgId: orgId,
          authorUid: uid,
          authorName: me.displayName,
          title: incoming
              ? '$opponentName have challenged us — who is in?'
              : 'We have challenged $opponentName — who is in?',
          content: 'Tap In if you can play. The squad is picked from whoever '
              'says yes.',
          match: MatchCall(
            sportId: sportId,
            matchDate: when,
            venue: venue,
            // Left open. The headcount is the organizer's to set once they
            // know the format, and a number guessed here would show every
            // member a target the club never chose.
            maxPlayers: 0,
          ),
          target: ChallengeCallTarget(
            challengeId: challengeId,
            opponentName: opponentName,
          ),
        );
  } catch (_) {
    // See above.
  }
}

/// The date the club is asking its members about.
///
/// The agreed one once there is one. Before that the earliest date still on
/// the table, because a member deciding whether they are free needs A date to
/// decide against — and the earliest is the one that constrains them soonest.
/// The sheet says plainly when more than one is in play, so nobody reads a
/// provisional date as a fixed one.
DateTime _whenToAskAbout(Challenge c) {
  if (c.agreedSlot != null) return c.agreedSlot!;
  final slots = [...c.liveSlots]..sort();
  return slots.isEmpty ? DateTime.now().add(const Duration(days: 3)) : slots.first;
}

/// Where the club's answers have got to, across every call it has posted for
/// this challenge.
///
/// Across every call and not just the latest: a club that asked its
/// first-choice twenty a fortnight out and then opened it to everybody on the
/// Friday has asked twice, and a squad built from only the second question
/// would drop the people who answered the first.
class _Tally {
  const _Tally({
    required this.yes,
    required this.maybe,
    required this.no,
    required this.askedCount,
  });

  final List<String> yes;
  final Set<String> maybe;
  final Set<String> no;

  /// How many people the club put the question to. The whole active
  /// membership as soon as any one of the calls went out open.
  final int askedCount;

  static _Tally of(List<Announcement> calls, List<Membership> members) {
    final yes = <String>{};
    final maybe = <String>{};
    final no = <String>{};
    final askedUids = <String>{};
    var anyOpen = false;

    for (final a in calls) {
      final poll = a.poll;
      if (poll == null) continue;
      yes.addAll(poll.votersFor(Rsvp.yes));
      maybe.addAll(poll.votersFor(Rsvp.maybe));
      no.addAll(poll.votersFor(Rsvp.no));
      final invited = a.match?.invitedUids ?? const <String>[];
      if (invited.isEmpty) {
        anyOpen = true;
      } else {
        askedUids.addAll(invited);
      }
    }

    // Somebody who said In on the first call and Out on the second means Out:
    // the later answer is the one they stand by. Order the sets so a uid never
    // appears in two columns.
    maybe.removeAll(no);
    yes..removeAll(no)..removeAll(maybe);

    return _Tally(
      yes: yes.toList()..sort(),
      maybe: maybe,
      no: no,
      askedCount: anyOpen ? members.length : askedUids.length,
    );
  }

  int get answered => yes.length + maybe.length + no.length;

  /// How many were asked and have said nothing. Clamped, because a member who
  /// answered and then left the club can put the answered count above the
  /// asked count, and "-1 yet to reply" is not a thing anybody needs to read.
  int get silent => (askedCount - answered).clamp(0, askedCount);

  String get line => [
        'Asked $askedCount',
        '${yes.length} in',
        if (maybe.isNotEmpty) '${maybe.length} maybe',
        if (no.isNotEmpty) '${no.length} out',
        if (silent > 0) '$silent yet to reply',
      ].join('  ·  ');
}

/// The card's own box, so the block reads as one thing under the challenge
/// rather than as loose text after the buttons.
class _Frame extends StatelessWidget {
  const _Frame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Our squad',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Asking
// ---------------------------------------------------------------------------

/// What the organizer decided to ask, and of whom.
class _AskTerms {
  const _AskTerms({
    required this.invitedUids,
    required this.playersNeeded,
    required this.note,
  });

  /// Empty means the whole club — see [MatchCall.invitedUids].
  final List<String> invitedUids;
  final int playersNeeded;
  final String note;
}

/// Chooses the audience, the headcount and the note, and nothing else.
///
/// Deliberately not a form for the match: the sport, the date and the ground
/// are the challenge's and are shown read-only. An organizer who could retype
/// them here would be creating a second, disagreeing record of what was
/// offered — which is the bug this whole flow exists to avoid.
class _AskMembersSheet extends ConsumerStatefulWidget {
  const _AskMembersSheet({
    required this.challenge,
    required this.orgId,
    required this.members,
    required this.opponent,
    required this.incoming,
  });

  final Challenge challenge;
  final String orgId;
  final List<Membership> members;
  final String opponent;
  final bool incoming;

  @override
  ConsumerState<_AskMembersSheet> createState() => _AskMembersSheetState();
}

class _AskMembersSheetState extends ConsumerState<_AskMembersSheet> {
  /// Everybody, or a named list. Everybody is the default because it is right
  /// for the small club, and a small club is most clubs.
  bool _everyone = true;

  final _picked = <String>{};
  final _search = TextEditingController();
  final _note = TextEditingController();
  int _playersNeeded = 0;

  @override
  void initState() {
    super.initState();
    _note.text = 'Tap In if you can play. The squad is picked from whoever '
        'says yes.';
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.challenge;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final m in widget.members)
        if (query.isEmpty || m.displayName.toLowerCase().contains(query)) m,
    ];

    final canSend = _everyone || _picked.isNotEmpty;
    final slots = [...c.liveSlots]..sort();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.incoming
                  ? 'Ask before you accept'
                  : 'Ask who is in',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.incoming
                  ? 'Find out who can play ${widget.opponent} before you agree '
                      'a date. Answers land on their home screen.'
                  : 'Your members get one tap to say In, Maybe or Out. '
                      'Answers land on their home screen.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),

            // The match, as the challenge already records it. Read-only.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'v ${widget.opponent}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      for (final leg
                          in c.resolvedLegs((id) => SportCatalog.byId(id).name))
                        leg.sideFormatName.isEmpty ? leg.sportName : leg.label,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (c.liveVenue != null && c.liveVenue!.isNotEmpty)
                    Text('At ${c.liveVenue}',
                        style: theme.textTheme.bodySmall),
                  Text(
                    c.agreedSlot != null
                        ? 'Agreed for ${_slot(c.agreedSlot!)}'
                        : slots.isEmpty
                            ? 'No date proposed yet'
                            : slots.length == 1
                                ? 'Proposed for ${_slot(slots.first)}'
                                // Said plainly, because a member answering
                                // "In" for a date that is not settled is
                                // answering a different question from one who
                                // thinks it is.
                                : 'Date not fixed — asking about '
                                    '${_slot(slots.first)}, '
                                    '${slots.length - 1} other '
                                    '${slots.length == 2 ? 'date' : 'dates'} '
                                    'on the table',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Who should we ask?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            RadioListTile<bool>(
              value: true,
              groupValue: _everyone,
              onChanged: (v) => setState(() => _everyone = v ?? true),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Everyone (${widget.members.length})'),
              subtitle: const Text('The whole club gets the question'),
            ),
            RadioListTile<bool>(
              value: false,
              groupValue: _everyone,
              onChanged: (v) => setState(() => _everyone = v ?? false),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Only the people I pick'),
              subtitle: const Text(
                'For when the club is bigger than the squad',
              ),
            ),

            if (!_everyone) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search members',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      // Acts on what is on screen, not on the whole club — a
                      // captain who searched "u19" and tapped this means those
                      // people, and clearing the search would not un-mean it.
                      final ids = {for (final m in shown) m.uid};
                      if (ids.every(_picked.contains)) {
                        _picked.removeAll(ids);
                      } else {
                        _picked.addAll(ids);
                      }
                    }),
                    child: Text(
                      shown.isNotEmpty && shown.every((m) => _picked.contains(m.uid))
                          ? 'Clear'
                          : 'Select all',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_picked.length} selected',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          widget.members.isEmpty
                              ? 'This club has no active members yet.'
                              : 'No member matches “${_search.text.trim()}”.',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in shown)
                            CheckboxListTile(
                              value: _picked.contains(m.uid),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _picked.add(m.uid);
                                } else {
                                  _picked.remove(m.uid);
                                }
                              }),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              secondary: PsAvatar(
                                name: m.displayName,
                                photoUrl: m.photoUrl,
                                seed: m.uid,
                                size: 30,
                              ),
                              title: Text(m.displayName),
                              subtitle: Text(m.role.label),
                            ),
                        ],
                      ),
              ),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Players needed')),
                IconButton(
                  tooltip: 'Remove one',
                  onPressed: _playersNeeded == 0
                      ? null
                      : () => setState(() => _playersNeeded -= 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  _playersNeeded == 0 ? 'Any' : '$_playersNeeded',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                IconButton(
                  tooltip: 'Add one',
                  onPressed: () => setState(() => _playersNeeded += 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: canSend
                  ? () => Navigator.pop(
                        context,
                        _AskTerms(
                          invitedUids: _everyone ? const [] : _picked.toList(),
                          playersNeeded: _playersNeeded,
                          note: _note.text.trim(),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.campaign_outlined),
              label: Text(
                _everyone
                    ? 'Ask all ${widget.members.length}'
                    : 'Ask ${_picked.length} '
                        'member${_picked.length == 1 ? '' : 's'}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _slot(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'am' : 'pm';
  final min = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '${d.day} ${months[d.month - 1]}, $h$min$ampm';
}
