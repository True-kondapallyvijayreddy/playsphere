import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/announcement.dart';
import '../../../core/models/organization.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/section_header.dart';
import '../../../shared/ui_kit.dart';
import '../../home/home_providers.dart';
import 'match_rsvp_card.dart';

/// "Upcoming club matches & availability", on the home screen.
///
/// ## Why it stacks instead of listing
///
/// A player in four clubs during a busy week can have six live availability
/// calls at once. Listed in full they are six tall cards — each with a roster,
/// a vote row and a chat toggle — between the greeting and everything else on
/// the dashboard, which is how a useful section becomes the thing people
/// scroll past.
///
/// So the one that needs answering first is open, and the rest collapse to a
/// count. That is the same judgement the live-matches ticker above makes by
/// capping at three, with one difference: nothing here is truncated away. The
/// `+N` expands in place, because unlike a live score these are questions
/// addressed to this person and every one of them wants an answer.
class MatchRsvpSection extends ConsumerStatefulWidget {
  const MatchRsvpSection({super.key});

  @override
  ConsumerState<MatchRsvpSection> createState() => _MatchRsvpSectionState();
}

class _MatchRsvpSectionState extends ConsumerState<MatchRsvpSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(myMatchRsvpsProvider);
    final calls = callsAsync.valueOrNull ?? const <Announcement>[];
    final clashes = ref.watch(myRsvpClashesProvider);

    // The clubs where this person could post one. Same gate the "New event"
    // action uses: offering the button to somebody who cannot create one is
    // offering them a permission error.
    final organizingOrgIds = <String>[
      for (final m in ref.watch(myActiveMembershipsProvider).valueOrNull ??
          const <Membership>[])
        if (ref.watch(myCapabilitiesProvider(m.orgId)).any((c) =>
            c == Capability.manageCompetitions ||
            c == Capability.manageOrganization))
          m.orgId,
    ];

    // Nothing to show and nothing to create: the section does not exist. An
    // empty state here would be a permanent apology on the dashboard of every
    // member whose club does not use this.
    if (calls.isEmpty && organizingOrgIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final shown = _expanded || calls.length <= 1 ? calls : calls.take(1);
    final hidden = calls.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          icon: Icons.event_available_outlined,
          title: 'Upcoming club matches',
          subtitle: 'Say if you are free — your club is counting heads',
        ),
        AsyncErrorStrip(value: callsAsync, what: 'match availability'),
        if (organizingOrgIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => showCreateMatchRsvpSheet(
                  context: context,
                  ref: ref,
                  orgIds: organizingOrgIds,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Match RSVP'),
              ),
            ),
          ),
        if (calls.isEmpty)
          const QuietCard(
            icon: Icons.event_note_outlined,
            title: 'No matches called yet',
            message: 'Ask your club who is free and the answers land here.',
          )
        else ...[
          for (final call in shown)
            MatchRsvpCard(
              // Keyed by document id so expanding the stack re-parents the
              // existing cards rather than rebuilding them — otherwise an open
              // chat thread closes itself the moment somebody votes.
              key: ValueKey(call.id),
              announcement: call,
              canOrganize: ref
                  .watch(myCapabilitiesProvider(call.orgId))
                  .contains(Capability.manageCompetitions),
              clashesWith: clashes[call.id] ?? const [],
            ),
          if (hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = true),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                  '+$hidden more match${hidden == 1 ? '' : 'es'} to answer',
                ),
              ),
            ),
          if (_expanded && calls.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = false),
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('Show fewer'),
              ),
            ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Asks the four things a match call cannot do without, and nothing else.
///
/// Deliberately not the event wizard. An organizer standing in a car park
/// deciding to call Sunday's game has four facts and thirty seconds; asking
/// them for a registration window, a participation model and a schedule
/// configuration is how the WhatsApp poll wins.
Future<void> showCreateMatchRsvpSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<String> orgIds,
}) async {
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheet).bottom,
      ),
      child: _CreateSheet(orgIds: orgIds, authorUid: uid),
    ),
  );
}

class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet({required this.orgIds, required this.authorUid});

  final List<String> orgIds;
  final String authorUid;

  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  late String _orgId = widget.orgIds.first;
  SportSpec _sport = SportCatalog.byId('cricket');
  final _title = TextEditingController();
  final _venue = TextEditingController();
  final _note = TextEditingController();
  DateTime _when = _nextEvening();
  int _maxPlayers = 0;
  bool _busy = false;

  /// Tomorrow evening, which is when a club game most often is, rather than
  /// "now" — a default of now is always wrong and always has to be changed.
  static DateTime _nextEvening() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18);
  }

  @override
  void dispose() {
    _title.dispose();
    _venue.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (!mounted) return;
    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      final me = ref.read(currentUserProvider).valueOrNull;
      await ref.read(communityRepositoryProvider).createMatchRsvp(
            orgId: _orgId,
            authorUid: widget.authorUid,
            authorName: me?.displayName ?? 'Organizer',
            title: _title.text.trim().isEmpty
                ? '${_sport.name} match'
                : _title.text.trim(),
            content: _note.text.trim(),
            match: MatchCall(
              sportId: _sport.id,
              matchDate: _when,
              venue: _venue.text.trim(),
              maxPlayers: _maxPlayers,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(myActiveMembershipsProvider).valueOrNull ?? const [];
    final names = {
      for (final m in clubs)
        m.orgId: ref.watch(organizationProvider(m.orgId)).valueOrNull?.name ??
            'Club',
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Call a match',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Ps.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your members get one tap to say In, Maybe or Out.',
              style: TextStyle(fontSize: 13, color: Ps.muted),
            ),
            const SizedBox(height: 16),
            if (widget.orgIds.length > 1) ...[
              DropdownButtonFormField<String>(
                value: _orgId,
                decoration: const InputDecoration(
                  labelText: 'Club',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final id in widget.orgIds)
                    DropdownMenuItem(value: id, child: Text(names[id] ?? 'Club')),
                ],
                onChanged: (v) => setState(() => _orgId = v ?? _orgId),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              value: _sport.id,
              decoration: const InputDecoration(
                labelText: 'Sport',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final s in SportCatalog.all)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(
                () => _sport = SportCatalog.byId(v ?? _sport.id),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: '${_sport.name} match',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickWhen,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'When',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  '${_when.day}/${_when.month}/${_when.year}  ·  '
                  '${TimeOfDay.fromDateTime(_when).format(context)}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _venue,
              decoration: const InputDecoration(
                labelText: 'Where',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Anything else',
                hintText: 'Bring whites. Ground fee ₹50.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // How many the organizer is trying to field, ALL SIDES TOGETHER.
            // Zero is a real answer and the default: plenty of clubs poll
            // first and work out the format once they know the numbers.
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Players needed',
                    style: TextStyle(fontSize: 13, color: Ps.muted),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove one',
                  onPressed: _maxPlayers == 0
                      ? null
                      : () => setState(() => _maxPlayers -= 2),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  _maxPlayers == 0 ? 'Any' : '$_maxPlayers',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                IconButton(
                  tooltip: 'Add one',
                  onPressed: () => setState(() => _maxPlayers += 2),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _post,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_outlined),
              label: Text(_busy ? 'Posting…' : 'Ask the club'),
            ),
          ],
        ),
      ),
    );
  }
}
