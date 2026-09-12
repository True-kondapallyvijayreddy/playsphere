import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/announcement.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';
import '../../home/home_providers.dart';

/// "Who is free on Sunday", answerable in one tap.
///
/// ## What this replaces
///
/// A WhatsApp poll for availability, a WhatsApp thread to argue about the
/// ground, a photo of a paper team sheet, and a separate app to score in. Four
/// tools, none of which know about each other, and a captain who ends up
/// transcribing names between them. The whole point of this card is that the
/// answer to "who is coming" becomes the team sheet becomes the match, without
/// anybody retyping a name.
///
/// ## Why the call to action changes shape
///
/// A club's turnout is not a number the organizer controls. Eleven-a-side
/// cricket wants 22 and gets 14 or 33; badminton wants 4 and gets 10. Those
/// are not the same situation and must not offer the same button:
///
///  * **At or under the target** — one match. Draft the sides and play.
///  * **Over it** — one match cannot seat everybody, and the honest options
///    are to run a mini-tournament or to play one match anyway and leave
///    people out. Both are offered; neither is chosen for the organizer.
///
/// Only ever an organizer's decision. A member sees the roster and the chat
/// and their own vote, which is everything they need and nothing they cannot
/// act on.
class MatchRsvpCard extends ConsumerStatefulWidget {
  const MatchRsvpCard({
    super.key,
    required this.announcement,
    this.canOrganize = false,
    this.clashesWith = const [],
  });

  final Announcement announcement;

  /// Whether this viewer may draft the teams and start the match.
  final bool canOrganize;

  /// Other calls this person has said yes to at the same hour. Non-empty means
  /// the card carries a warning — see [_ClashBanner].
  final List<Announcement> clashesWith;

  @override
  ConsumerState<MatchRsvpCard> createState() => _MatchRsvpCardState();
}

class _MatchRsvpCardState extends ConsumerState<MatchRsvpCard> {
  bool _chatOpen = false;

  /// Everything past the question itself: the note, the roster, the
  /// discussion, and the alternatives to one straight match.
  ///
  /// Shut by default. See the class doc — the card has to answer "what am I
  /// being asked, and what do I say" inside about 140pt, or a member with five
  /// calls waiting is scrolling instead of answering.
  bool _open = false;

  final _chat = TextEditingController();

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  Announcement get _a => widget.announcement;
  MatchCall get _match => _a.match!;
  Poll get _poll => _a.poll!;

  /// Casting or withdrawing this member's answer.
  ///
  /// Goes through the repository's existing `voteInPoll` unchanged — a single
  /// dotted-field write that two members can make at the same moment without
  /// erasing each other. Nothing about a match call needed a second way to
  /// record a vote.
  Future<void> _vote(int index) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final mine = _poll.voteOf(uid);
    // Tapping your own answer again takes it back, exactly as the club poll
    // behaves. Somebody who said they were coming and now cannot must be able
    // to say so without hunting for a different control.
    final next = mine == index ? null : index;

    // The clash check happens BEFORE the write, and only on the way in to a
    // yes. Warning somebody as they withdraw would be nonsense, and warning
    // them after the fact would mean the team sheet already has them on it.
    if (next == Rsvp.yes) {
      final all = ref.read(myMatchRsvpsProvider).valueOrNull ?? const [];
      final clashes = clashesFor(candidate: _a, against: all, uid: uid);
      if (clashes.isNotEmpty && mounted) {
        final proceed = await _confirmClash(clashes);
        if (proceed != true) return;
      }
    }

    if (!mounted) return;
    try {
      await ref.read(communityRepositoryProvider).voteInPoll(
            orgId: _a.orgId,
            announcementId: _a.id,
            uid: uid,
            optionIndex: next,
          );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<bool?> _confirmClash(List<Announcement> clashes) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
          title: const Text('You are already booked'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have said you are In for '
                '${clashes.length == 1 ? 'another match' : '${clashes.length} '
                    'other matches'} at about the same time:',
              ),
              const SizedBox(height: 10),
              for (final c in clashes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${c.title} — ${_when(c.match!.matchDate)}'
                    '${c.match!.venue.isEmpty ? '' : ' at ${c.match!.venue}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'Saying In here does not withdraw you from the other one. '
                'Both captains will be counting on you.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Say In anyway'),
            ),
          ],
        ),
      );

  Future<void> _send() async {
    final uid = ref.read(currentUidProvider);
    final text = _chat.text.trim();
    if (uid == null || text.isEmpty) return;
    _chat.clear();
    try {
      await ref.read(communityRepositoryProvider).sendMatchComment(
            orgId: _a.orgId,
            announcementId: _a.id,
            senderUid: uid,
            senderName: ref.read(currentUserProvider).valueOrNull?.displayName ??
                'Member',
            text: text,
          );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final myVote = uid == null ? null : _poll.voteOf(uid);
    final sport = SportCatalog.byId(_match.sportId);
    final confirmed = _poll.countFor(Rsvp.yes);
    final target = _match.maxPlayers;
    final surplus = _match.hasSurplus(confirmed);
    // Whoever put the call out. See the doc on [_OrganizerActions].
    final isAuthor = uid != null && uid == _a.authorUid;
    final forward = widget.canOrganize && confirmed >= 2
        ? _ForwardAction.of(_a)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(
          color: widget.clashesWith.isEmpty
              ? Ps.border
              : const Color(0xFFF59E0B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            sport: sport,
            title: _a.title,
            orgId: _a.orgId,
            match: _match,
            confirmed: confirmed,
            target: target,
          ),
          if (widget.clashesWith.isNotEmpty)
            _ClashBanner(clashes: widget.clashesWith),

          // The question. Always visible, never behind a tap — this is the
          // one thing every recipient of the card has to do.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final (index, label, icon, colour) in const [
                  (Rsvp.yes, 'In', Icons.check_circle, Ps.primary),
                  (Rsvp.maybe, 'Maybe', Icons.help, Color(0xFFF59E0B)),
                  (Rsvp.no, 'Out', Icons.cancel, Ps.live),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _VoteButton(
                        label: label,
                        icon: icon,
                        colour: colour,
                        count: _poll.countFor(index),
                        selected: myVote == index,
                        onTap: _poll.closed ? null : () => _vote(index),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          _FooterBar(
            open: _open,
            onToggle: () => setState(() => _open = !_open),
            poll: _poll,
            hasNote: _a.content.trim().isNotEmpty,
            // The forward action, one tap from the collapsed card. Getting
            // from "who is free" to a match being played is the whole reason
            // the call exists, and burying it behind an expand is what made
            // the old card feel like a form.
            //
            // WHERE it goes depends on what the call belongs to — see
            // [_ForwardAction].
            forward: forward,
            // Author-only, and the only place these two live now. See the
            // class doc on [_OrganizerActions].
            onEdit: isAuthor ? () => editCall(context, ref, _a) : null,
            onCancel:
                isAuthor ? () => cancelCall(context, ref, _a, confirmed) : null,
          ),

          if (_open) ...[
            if (_a.content.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                child: Text(
                  _a.content,
                  style: const TextStyle(fontSize: 13, color: Ps.muted),
                ),
              ),
            _CalledBy(announcement: _a, isAuthor: isAuthor),
            _Roster(orgId: _a.orgId, poll: _poll),
            _ChatSection(
              open: _chatOpen,
              onToggle: () => setState(() => _chatOpen = !_chatOpen),
              orgId: _a.orgId,
              announcementId: _a.id,
              controller: _chat,
              onSend: _send,
            ),
            if (widget.canOrganize)
              _OrganizerActions(
                announcement: _a,
                confirmed: confirmed,
                surplus: surplus,
              ),
          ],
        ],
      ),
    );
  }
}

/// The strip along the bottom: what the club has answered, and what to do next.
///
/// One 38pt row carrying four things that each used to cost a row of their
/// own — the tally, the way into the detail, the forward action, and the
/// author's own controls. That collapse is most of what takes the card from
/// roughly 300pt to under 150.
class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.open,
    required this.onToggle,
    required this.poll,
    required this.hasNote,
    required this.forward,
    required this.onEdit,
    required this.onCancel,
  });

  final bool open;
  final VoidCallback onToggle;
  final Poll poll;
  final bool hasNote;

  /// Null unless this viewer may run the club's matches AND enough people
  /// have said In to do anything with.
  final _ForwardAction? forward;

  /// Both null unless this viewer wrote the call.
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final yes = poll.countFor(Rsvp.yes);
    final maybe = poll.countFor(Rsvp.maybe);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
      child: Row(
        children: [
          // The whole left half is the expand target, not just the chevron —
          // a 16pt caret is a dart-throw on a phone.
          Flexible(
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(Ps.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Ps.muted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        open
                            ? 'Hide'
                            : [
                                'Who is in',
                                if (maybe > 0) '$yes + $maybe maybe',
                                if (hasNote) 'note',
                              ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Ps.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (forward != null)
            Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => forward!.go(context, ref),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(forward!.label),
              ),
            ),
          if (onEdit != null || onCancel != null)
            PopupMenuButton<int>(
              tooltip: 'Your call',
              icon: const Icon(Icons.more_vert, size: 18, color: Ps.muted),
              padding: EdgeInsets.zero,
              onSelected: (v) => v == 0 ? onEdit?.call() : onCancel?.call(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 0,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined, size: 18),
                    title: Text('Edit call'),
                  ),
                ),
                PopupMenuItem(
                  value: 1,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.event_busy_outlined, size: 18, color: Ps.live),
                    title: Text(
                      'Cancel match',
                      style: TextStyle(color: Ps.live),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Where "this call is answered, now what" actually leads.
///
/// ## Why this is not always "make teams"
///
/// A call is put out for one of three reasons, and only one of them ends in
/// splitting the people who said yes into two sides:
///
///  * **A club's own Sunday game.** Nothing exists yet. The yeses ARE both
///    teams, and drafting them is the next step — [Routes.quickMatch], seeded
///    with their uids.
///  * **A challenge to another club.** The yeses are ONE side; the opponent is
///    the other club, and the fixture is created by accepting the challenge,
///    not here. Dealing these people into two teams would produce a second,
///    private match that the other club is not in and nobody is expecting —
///    which is precisely the "hiccup" this class exists to remove. It goes to
///    the challenge board instead.
///  * **A fixture that already exists.** Same again: there is a match, this
///    club has a side in it, and the answers belong on that side's squad
///    sheet. `SquadRsvpActions` on the fixture does that move in one write.
///
/// The old card offered "Draft teams & play" for all three, so the two
/// club-versus-club paths — the ones the product is actually for — each had a
/// button on them that quietly built the wrong thing.
class _ForwardAction {
  const _ForwardAction._(this.label, this._go);

  final String label;
  final void Function(BuildContext, WidgetRef) _go;

  void go(BuildContext context, WidgetRef ref) => _go(context, ref);

  static _ForwardAction of(Announcement a) {
    final match = a.match!;

    if (match.isForChallenge) {
      return _ForwardAction._(
        'Open challenge',
        (context, _) => context.push(Routes.challenges(a.orgId)),
      );
    }

    final fixture = match.forFixture;
    if (fixture != null) {
      return _ForwardAction._(
        'Open match',
        (context, _) => context.push(
          Routes.watch(fixture.orgId, fixture.compId, fixture.fixtureId),
        ),
      );
    }

    return _ForwardAction._(
      // Named for what it does to the people, not for the screen it opens.
      'Make teams',
      (context, ref) => draftTeams(context, ref, a),
    );
  }
}

/// Whose call this is — and, for everybody else, why they cannot touch it.
class _CalledBy extends StatelessWidget {
  const _CalledBy({required this.announcement, required this.isAuthor});

  final Announcement announcement;
  final bool isAuthor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Text(
        isAuthor
            ? 'Your call.'
            : '${announcement.authorName} called this match — only they can '
                'edit or cancel it.',
        style: const TextStyle(fontSize: 11.5, color: Ps.faint),
      ),
    );
  }
}

/// A human date that a person standing at a ground can read without arithmetic.
String _when(DateTime when) {
  final now = DateTime.now();
  final local = when.toLocal();
  final days = DateTime(local.year, local.month, local.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  final time = TimeOfDay.fromDateTime(local);
  final hh = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final mm = time.minute.toString().padLeft(2, '0');
  final period = time.period == DayPeriod.am ? 'am' : 'pm';
  final clock = '$hh:$mm$period';
  return switch (days) {
    0 => 'Today $clock',
    1 => 'Tomorrow $clock',
    _ when days > 1 && days < 7 => '${_weekday(local.weekday)} $clock',
    _ => '${local.day}/${local.month} $clock',
  };
}

String _weekday(int w) => const [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ][(w - 1).clamp(0, 6)];

class _Header extends ConsumerWidget {
  const _Header({
    required this.sport,
    required this.title,
    required this.orgId,
    required this.match,
    required this.confirmed,
    required this.target,
  });

  final SportSpec sport;
  final String title;
  final String orgId;
  final MatchCall match;
  final int confirmed;
  final int target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(organizationProvider(orgId)).valueOrNull;
    final visual = SportVisual.of(sport.id);
    // Enough, not enough, or too many — the one number the organizer is
    // actually waiting on, stated as a ratio when there is a target to state
    // it against.
    final full = target > 0 && confirmed >= target;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: visual.color,
              borderRadius: BorderRadius.circular(Ps.radiusSm),
            ),
            child: Icon(visual.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 2),
                // Kick-off first. A member scanning five calls is deciding by
                // WHEN before anything else, and the club's name is the least
                // distinguishing thing on a screen that is already scoped to
                // the clubs they are in.
                Text(
                  [
                    _when(match.matchDate),
                    if (match.venue.isNotEmpty) match.venue,
                    if (club != null) club.name,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: (full ? Ps.primary : Ps.muted).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              target > 0 ? '$confirmed/$target' : '$confirmed in',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: full ? Ps.primary : Ps.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says the quiet part out loud: you have promised to be in two places.
class _ClashBanner extends StatelessWidget {
  const _ClashBanner({required this.clashes});

  final List<Announcement> clashes;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              clashes.length == 1
                  ? 'Clashes with "${clashes.first.title}"'
                  : 'Clashes with ${clashes.length} other matches you said '
                      'In for',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.icon,
    required this.colour,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colour : colour.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            border: Border.all(
              color: selected ? Colors.transparent
                  : colour.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16,
                  color: selected ? Colors.white : colour),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$label $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : colour,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is coming, by name.
///
/// Names and not a count, because the count is not what decides whether you
/// come — "is Ravi playing" is. Only the yeses and maybes: a list of people
/// who declined is a wall of shame nobody asked for.
class _Roster extends ConsumerWidget {
  const _Roster({required this.orgId, required this.poll});

  final String orgId;
  final Poll poll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(orgMembersProvider(orgId)).valueOrNull ?? const [];
    final names = {for (final m in members) m.uid: m.displayName};

    List<String> named(int index) => [
          for (final uid in poll.votersFor(index)) names[uid] ?? 'Member',
        ];

    final yes = named(Rsvp.yes);
    final maybe = named(Rsvp.maybe);
    if (yes.isEmpty && maybe.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Text(
          'Nobody has answered yet.',
          style: TextStyle(fontSize: 12, color: Ps.faint),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (yes.isNotEmpty)
            _RosterLine(colour: Ps.primary, label: 'In', names: yes),
          if (maybe.isNotEmpty)
            _RosterLine(
              colour: const Color(0xFFF59E0B),
              label: 'Maybe',
              names: maybe,
            ),
        ],
      ),
    );
  }
}

class _RosterLine extends StatelessWidget {
  const _RosterLine({
    required this.colour,
    required this.label,
    required this.names,
  });

  final Color colour;
  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Ps.muted),
          children: [
            TextSpan(
              text: '$label · ',
              style: TextStyle(fontWeight: FontWeight.w800, color: colour),
            ),
            TextSpan(text: names.join(', ')),
          ],
        ),
      ),
    );
  }
}

/// The coordination that used to happen in a separate WhatsApp thread.
///
/// Collapsed by default, and that is the design rather than a saving: the card
/// exists to be answered in one tap, and a chat open by default pushes the
/// buttons off the screen for the majority who only ever vote.
class _ChatSection extends ConsumerWidget {
  const _ChatSection({
    required this.open,
    required this.onToggle,
    required this.orgId,
    required this.announcementId,
    required this.controller,
    required this.onSend,
  });

  final bool open;
  final VoidCallback onToggle;
  final String orgId;
  final String announcementId;
  final TextEditingController controller;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = open
        ? ref.watch(matchCommentsProvider((
            orgId: orgId,
            announcementId: announcementId,
          ))).valueOrNull
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, size: 16, color: Ps.muted),
                const SizedBox(width: 8),
                Text(
                  open ? 'Hide discussion' : 'Discussion',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Ps.muted,
                  ),
                ),
                const Spacer(),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Ps.muted,
                ),
              ],
            ),
          ),
        ),
        if (open) ...[
          if (messages == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (messages.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                'No messages yet. Sort the ground out here.',
                style: TextStyle(fontSize: 12, color: Ps.faint),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                children: [
                  for (final m in messages) _Bubble(message: m),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Message the group',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded),
                  color: Ps.primary,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});

  final MatchChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = message.senderUid == ref.watch(currentUidProvider);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: mine ? Ps.primary.withValues(alpha: 0.12) : Ps.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Ps.border),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                message.senderName,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Ps.muted,
                ),
              ),
            Text(
              message.text,
              style: const TextStyle(fontSize: 13, color: Ps.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the organizer does once enough people have answered.
///
/// ## Why calling it off is narrower than the rest
///
/// Drafting the sides is a club job: any organizer who can run a competition
/// can turn a full call into a fixture, and a captain who is at the ground
/// while the person who put the call out is not should not be blocked from
/// starting the game.
///
/// **Editing the call and cancelling it are not.** Both rewrite or destroy
/// something a specific person asked the club — and cancelling deletes it
/// outright, discussion and all (see `CommunityRepository.cancelMatchCall`).
/// A club with four admins had four people able to delete each other's
/// Saturday, silently, from a card that gave no hint whose call it was. So
/// those two are the author's alone; everybody else, admins included, gets the
/// vote row like any other member.
class _OrganizerActions extends ConsumerWidget {
  const _OrganizerActions({
    required this.announcement,
    required this.confirmed,
    required this.surplus,
  });

  final Announcement announcement;
  final int confirmed;

  /// More people said yes than this match seats.
  final bool surplus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = announcement.match!;
    // Nothing to draft out of nobody. Two is the floor for any sport in the
    // catalogue — a match needs two sides — and offering the button below it
    // leads to a screen that cannot be submitted.
    final enough = confirmed >= 2;

    // A call attached to a challenge or an existing fixture has no "how shall
    // we split these people" question in it — they are one side of a match
    // that already has an opponent. See [_ForwardAction].
    final ownGame = !match.isForChallenge && !match.isForFixture;
    if (!ownGame) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Ps.border)),
        ),
        child: Text(
          match.isForChallenge
              ? 'Everybody who says In is your side for this challenge. The '
                  'match itself is created on the challenge board.'
              : 'Everybody who says In goes onto your side of a match that '
                  'already exists. Open it to move them onto the squad.',
          style: const TextStyle(fontSize: 12, color: Ps.faint),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ps.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!enough)
            const Text(
              'Two people have to be In before you can draft sides.',
              style: TextStyle(fontSize: 12, color: Ps.faint),
            )
          else if (surplus) ...[
            Text(
              '$confirmed said In and this match seats ${match.maxPlayers}. '
              '"Make teams" plays one match and leaves the rest out; a '
              'mini-tournament fits everybody.',
              style: const TextStyle(fontSize: 12, color: Ps.muted),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => miniTournament(context, announcement),
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: const Text('Mini-tournament instead'),
            ),
          ] else
            const Text(
              'Everybody who said In fits one match. "Make teams" deals the '
              'sides and starts it.',
              style: TextStyle(fontSize: 12, color: Ps.faint),
            ),

        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The four things that can be done to a call.
//
// Library-level rather than methods on one widget: the footer bar offers
// "Make teams", the author's menu offers edit and cancel, and the expanded
// block offers the mini-tournament. Three call sites, one implementation
// each. WHO may invoke them is decided at those call sites — see the doc on
// [_OrganizerActions] — and deliberately not re-checked here, so there is one
// place to read the rule rather than four.
// ---------------------------------------------------------------------------

/// Changes the facts of a call that is already out, keeping the answers.
///
/// See `CommunityRepository.updateMatchCall` for why the votes survive. The
/// sheet says plainly that nobody is re-notified, because the alternative —
/// pushing the whole club again on every typo — is worse, and an organizer
/// who has just moved a kick-off by three hours needs to know to say so in
/// the discussion.
Future<void> editCall(
  BuildContext context,
  WidgetRef ref,
  Announcement announcement,
) async {
  final result = await showModalBottomSheet<_CallEdits>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: _EditCallSheet(announcement: announcement),
    ),
  );
  if (result == null || !context.mounted) return;

  try {
    await ref.read(communityRepositoryProvider).updateMatchCall(
          orgId: announcement.orgId,
          announcementId: announcement.id,
          title: result.title,
          content: result.content,
          matchDate: result.matchDate,
          venue: result.venue,
          maxPlayers: result.maxPlayers,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Call updated. Nobody was re-notified — say what changed in the '
          'discussion.',
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Calls the match off, after saying out loud how many people it strands.
///
/// The count is in the question rather than in a toast afterwards: "nine
/// people have said they are In" is the single fact that decides whether an
/// organizer should be cancelling or editing, and it belongs in front of
/// them while the decision is still reversible.
Future<void> cancelCall(
  BuildContext context,
  WidgetRef ref,
  Announcement announcement,
  int confirmed,
) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.event_busy_outlined, color: Ps.live),
      title: const Text('Call this match off?'),
      content: Text(
        confirmed == 0
            ? 'The call comes off everyone\'s home screen. Nobody has '
                'answered it yet.'
            : '$confirmed ${confirmed == 1 ? 'person has' : 'people have'} '
                'said they are In. The call and its discussion come off '
                'everyone\'s home screen, and they are not told why — tell '
                'them yourself first if the match is only moving.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Ps.live),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Call it off'),
        ),
      ],
    ),
  );
  if (sure != true || !context.mounted) return;

  try {
    await ref.read(communityRepositoryProvider).cancelMatchCall(
          orgId: announcement.orgId,
          announcementId: announcement.id,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Match called off.')),
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Hands the confirmed roster to the quick-match screen.
///
/// The uids travel in the route rather than the names: a player added by
/// name is a stranger with that name and nothing accrues to them, which is
/// the distinction `QuickMatchScreen` already exists to protect. Resolving
/// them to real members is that screen's job, and it already knows how.
void draftTeams(
  BuildContext context,
  WidgetRef ref,
  Announcement announcement,
) {
  final match = announcement.match!;
  context.push(
    Routes.quickMatch(
      announcement.orgId,
      name: announcement.title,
      sportId: match.sportId,
      venue: match.venue,
      playerUids: announcement.poll!.votersFor(Rsvp.yes),
    ),
  );
}

void miniTournament(BuildContext context, Announcement announcement) {
  final match = announcement.match!;
  context.push(
    Routes.quickTournament(
      announcement.orgId,
      name: announcement.title,
      sportId: match.sportId,
      venue: match.venue,
      playerUids: announcement.poll!.votersFor(Rsvp.yes),
    ),
  );
}

/// What the organizer changed about a call that is already out.
class _CallEdits {
  const _CallEdits({
    required this.title,
    required this.content,
    required this.matchDate,
    required this.venue,
    required this.maxPlayers,
  });

  final String title;
  final String content;
  final DateTime matchDate;
  final String venue;
  final int maxPlayers;
}

/// The four facts of a call an organizer can be wrong about.
///
/// The sport is not among them, and that is deliberate rather than an
/// omission: changing it would silently invalidate every answer already given
/// — somebody free for badminton on Sunday has not agreed to play cricket —
/// and it would strand a call attached to a challenge or a fixture on a sport
/// its match is not being played in. A call for the wrong sport is a call to
/// cancel, not to edit.
class _EditCallSheet extends StatefulWidget {
  const _EditCallSheet({required this.announcement});

  final Announcement announcement;

  @override
  State<_EditCallSheet> createState() => _EditCallSheetState();
}

class _EditCallSheetState extends State<_EditCallSheet> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _venue;
  late DateTime _at;
  late int _players;

  @override
  void initState() {
    super.initState();
    final a = widget.announcement;
    _title = TextEditingController(text: a.title);
    _content = TextEditingController(text: a.content);
    _venue = TextEditingController(text: a.match!.venue);
    _at = a.match!.matchDate.toLocal();
    _players = a.match!.maxPlayers;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _venue.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      // Backwards as well as forwards. A call whose date was typed as next
      // month when it meant this one is a real correction, and a picker that
      // only moves forward cannot make it.
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (!mounted) return;
    setState(() {
      _at = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _at.hour,
        time?.minute ?? _at.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = widget.announcement.poll?.votes.length ?? 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edit this call',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              answered == 0
                  ? 'Nobody has answered yet, so nothing is lost.'
                  : '$answered ${answered == 1 ? 'answer stays' : 'answers stay'} '
                      'as given. Nobody is notified of the change — post it in '
                      'the discussion if it matters.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickWhen,
              borderRadius: BorderRadius.circular(Ps.radiusSm),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'When',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.event),
                ),
                child: Text(_when(_at)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _venue,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ground',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Players needed')),
                IconButton(
                  tooltip: 'Remove one',
                  onPressed:
                      _players == 0 ? null : () => setState(() => _players -= 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  _players == 0 ? 'Any' : '$_players',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                IconButton(
                  tooltip: 'Add one',
                  onPressed: () => setState(() => _players += 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _content,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        _CallEdits(
                          title: _title.text.trim(),
                          content: _content.text.trim(),
                          matchDate: _at,
                          venue: _venue.text.trim(),
                          maxPlayers: _players,
                        ),
                      ),
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
