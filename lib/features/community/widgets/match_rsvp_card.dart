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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          if (_a.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                _a.content,
                style: const TextStyle(fontSize: 13, color: Ps.muted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                for (final (index, label, icon, colour) in const [
                  (Rsvp.yes, 'In', Icons.check_circle, Ps.primary),
                  (Rsvp.maybe, 'Maybe', Icons.help, Color(0xFFF59E0B)),
                  (Rsvp.no, 'Out', Icons.cancel, Ps.live),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: visual.color,
              borderRadius: BorderRadius.circular(Ps.radiusSm),
            ),
            child: Icon(visual.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (club != null) club.name,
                    _when(match.matchDate),
                    if (match.venue.isNotEmpty) match.venue,
                  ].join('  ·  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Ps.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          height: 44,
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
          else ...[
            if (surplus)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$confirmed said In and this match seats ${match.maxPlayers}. '
                  'A mini-tournament fits everybody.',
                  style: const TextStyle(fontSize: 12, color: Ps.muted),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _draftTeams(context, ref),
                    icon: const Icon(Icons.groups_2_outlined, size: 18),
                    label: const Text('Draft teams & play'),
                  ),
                ),
                if (surplus) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _miniTournament(context, ref),
                      icon: const Icon(Icons.emoji_events_outlined, size: 18),
                      label: const Text('Mini-tournament'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Hands the confirmed roster to the quick-match screen.
  ///
  /// The uids travel in the route rather than the names: a player added by
  /// name is a stranger with that name and nothing accrues to them, which is
  /// the distinction `QuickMatchScreen` already exists to protect. Resolving
  /// them to real members is that screen's job, and it already knows how.
  void _draftTeams(BuildContext context, WidgetRef ref) {
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

  void _miniTournament(BuildContext context, WidgetRef ref) {
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
}
