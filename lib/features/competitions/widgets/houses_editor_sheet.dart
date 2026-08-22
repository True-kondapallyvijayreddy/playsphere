import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers.dart';
import '../../../data/competition_repository.dart';
import '../../../domain/tournament/house_roster.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';
import 'house_list_editor.dart';

/// Lets an organizer author the houses, sections or batches their event is
/// split into, instead of being handed Red/Blue/Green/Yellow and left to cope.
///
/// See [HouseRoster] for why the list belongs to the organizer, and why saving
/// it has to carry the already-registered students across a rename. This
/// screen's job is to make both of those visible: every row shows how many
/// students are standing in it, so "rename" and "delete" stop being
/// indistinguishable taps.
class HousesEditorSheet extends ConsumerStatefulWidget {
  const HousesEditorSheet({super.key, required this.competition});

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => HousesEditorSheet(competition: competition),
      );

  @override
  ConsumerState<HousesEditorSheet> createState() => _HousesEditorSheetState();
}

class _HousesEditorSheetState extends ConsumerState<HousesEditorSheet> {
  late final List<HouseDraft> _drafts =
      HouseRoster.draftsFrom(widget.competition.presetHouses);

  /// One controller per row, keyed by row identity rather than index — a
  /// delete shifts every index below it, and a controller list indexed by
  /// position would move the text of the deleted row onto its neighbour.
  final Map<HouseDraft, TextEditingController> _controllers = {};

  bool _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(HouseDraft d) =>
      _controllers.putIfAbsent(d, () => TextEditingController(text: d.name));

  HouseRosterPlan get _plan => HouseRoster.plan(
        drafts: _drafts,
        current: widget.competition.presetHouses,
      );

  /// Whether the edited list is identical to the one saved on the
  /// competition — no renames, no removals, nothing added.
  bool get _savedListIsOnScreen {
    final plan = _plan;
    return !plan.touchesEntries &&
        plan.names.length == widget.competition.presetHouses.length;
  }

  void _applyTemplate(List<String> names) {
    setState(() {
      // Existing rows are matched by name so a template that overlaps what is
      // already there does not orphan the students in the overlap. Applying
      // "1st–4th Year" over a list that already has "3rd Year" keeps that
      // house and the people in it exactly where they were.
      final byName = {
        for (final d in _drafts)
          if (d.originalName != null) d.originalName!.toLowerCase(): d,
      };
      final next = <HouseDraft>[];
      for (final n in names) {
        final existing = byName[n.toLowerCase()];
        if (existing != null) {
          existing.name = n;
          _controllerFor(existing).text = n;
          next.add(existing);
        } else {
          final fresh = HouseDraft.fresh(n);
          _controllerFor(fresh).text = n;
          next.add(fresh);
        }
      }
      // Rows the template dropped take their controllers with them.
      for (final gone in _drafts.where((d) => !next.contains(d))) {
        _controllers.remove(gone)?.dispose();
      }
      _drafts
        ..clear()
        ..addAll(next);
    });
  }

  /// Places the field into houses from what the club already knows about its
  /// members — see [HouseAssigner].
  ///
  /// Runs against the SAVED house list, not the one being edited: placing
  /// students into houses that only exist in an unsaved text box would write
  /// registrations pointing at names the competition does not have. So this is
  /// offered only once there is nothing pending.
  Future<void> _autoPlace() async {
    final c = widget.competition;
    final regs = ref
        .read(registrationsProvider(CompRef(c.orgId, c.id)))
        .valueOrNull;
    final members =
        ref.read(orgMembersProvider(c.orgId)).valueOrNull;

    if (regs == null || members == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still loading the roster — try again.')),
      );
      return;
    }

    final preview = CompetitionRepository.previewHousePlacement(
      registrations: regs,
      members: members.where((m) => m.isActive).toList(),
      houses: c.presetHouses,
    );

    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Place students into houses'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewLine(
                count: preview.placements.length,
                label: 'will be placed from the club roster',
                emphasis: true,
              ),
              if (preview.alreadyPlaced.isNotEmpty)
                _PreviewLine(
                  count: preview.alreadyPlaced.length,
                  label: 'already have a house — left as they are',
                ),
              if (preview.unplaced.isNotEmpty)
                _PreviewLine(
                  count: preview.unplaced.length,
                  label: 'have no house, department or class recorded yet',
                  detail: preview.unplaced.take(6).join(', '),
                ),
              if (preview.outsiders.isNotEmpty)
                _PreviewLine(
                  count: preview.outsiders.length,
                  label: 'are not members of this club, so they cannot be '
                      'placed from your roster',
                  detail: preview.outsiders.take(6).join(', '),
                ),
              if (preview.unplaced.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Fill in houses and classes on the Members screen, then run '
                  'this again. Anyone left over stays in the pool for you to '
                  'place in the Team Builder.',
                  style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed:
                preview.hasWork ? () => Navigator.of(ctx).pop(true) : null,
            child: Text(
              preview.hasWork
                  ? 'Place ${preview.placements.length}'
                  : 'Nothing to place',
            ),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final n = await ref.read(competitionRepositoryProvider).applyHousePlacement(
            orgId: c.orgId,
            compId: c.id,
            preview: preview,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n students placed into their houses.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    if (!plan.isValid) return;

    // A deletion that strands people is confirmed, not just warned about. The
    // count in the row is the warning; this is the decision.
    if (plan.removed.isNotEmpty) {
      final counts = _counts;
      final stranded = plan.removed.fold<int>(
        0,
        (sum, h) => sum + (counts[h] ?? 0),
      );
      if (stranded > 0) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove these houses?'),
            content: Text(
              '${plan.removed.join(', ')} '
              '${plan.removed.length == 1 ? 'is' : 'are'} being removed, and '
              '$stranded ${stranded == 1 ? 'student is' : 'students are'} '
              'registered under ${plan.removed.length == 1 ? 'it' : 'them'}.\n\n'
              'They stay in the event and keep their entry, but they will have '
              'no house until you place them in the Team Builder.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Remove anyway'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    setState(() => _busy = true);
    final c = widget.competition;
    try {
      await ref.read(competitionRepositoryProvider).saveHouses(
            orgId: c.orgId,
            compId: c.id,
            plan: plan,
            // On a team event, naming houses IS choosing the house model:
            // the house is the entrant, so `EntrantPromoter` has to fold the
            // registrations into one side per house, and an event left on
            // "pre-formed teams" would promote squads that do not exist.
            // Individual events need no flip — there the house is an
            // affiliation carried on the registration, and the entry dialog
            // offers it off `presetHouses` alone.
            entryMode: c.entrantType == EntrantType.team &&
                    c.teamEntryMode != TeamEntryMode.houseBatch
                ? TeamEntryMode.houseBatch
                : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            plan.renames.isEmpty
                ? '${plan.names.length} houses saved.'
                : '${plan.names.length} houses saved. '
                    '${plan.renames.length} renamed — everyone already '
                    'registered moved with them.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  Map<String, int> _counts = const {};

  @override
  Widget build(BuildContext context) {
    final c = widget.competition;
    final regs = ref
        .watch(registrationsProvider(CompRef(c.orgId, c.id)))
        .valueOrNull;
    _counts = regs == null
        ? const {}
        : CompetitionRepository.houseCounts(regs);

    final plan = _plan;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.holiday_village_outlined, color: Ps.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Houses & Groups',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Text(
            'What students pick from when they enter. Name them however your '
            'institution actually splits — houses, departments, years, '
            'sections.',
            style: TextStyle(fontSize: 12.5, color: Ps.muted),
          ),
          const SizedBox(height: 12),

          HouseTemplateChips(onPicked: _applyTemplate),
          const SizedBox(height: 4),
          const Divider(height: 20),

          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _drafts.length,
              itemBuilder: (ctx, i) {
                final d = _drafts[i];
                final registered = _counts[d.originalName ?? d.name] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controllerFor(d),
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            hintText: 'e.g. ECE — 3rd Year',
                            labelText: 'House ${i + 1}',
                            // The one thing an organizer cannot see from the
                            // name alone: that editing this box moves people.
                            helperText: d.isRenamed && registered > 0
                                ? 'Renaming — $registered '
                                    '${registered == 1 ? 'entry moves' : 'entries move'} with it'
                                : null,
                          ),
                          onChanged: (v) => setState(() => d.name = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (registered > 0)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('$registered'),
                          avatar: const Icon(Icons.person_outline, size: 14),
                        ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() {
                          _controllers.remove(d)?.dispose();
                          _drafts.removeAt(i);
                        }),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _drafts.add(HouseDraft.fresh())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a house'),
            ),
          ),

          if (plan.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                plan.error!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),

          // Offered only once the list on screen matches the list on the
          // competition: placing people into names that exist in a text box
          // and nowhere else would point registrations at houses the event
          // does not have. Disabled with the reason rather than hidden — a
          // button that disappears on a keystroke reads as a bug.
          if (widget.competition.presetHouses.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _busy || !_savedListIsOnScreen ? null : _autoPlace,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
              label: Text(
                _savedListIsOnScreen
                    ? 'Place students from the club roster'
                    : 'Save the houses first, then place students',
              ),
            ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _busy || !plan.isValid ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              _busy ? 'Saving…' : 'Save ${plan.names.length} houses',
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the placement preview — a count, what it means, and a few of
/// the names behind it.
///
/// The names matter: "12 have nothing recorded" is a statistic, and
/// "12 have nothing recorded — Aarav, Diya, Ishaan…" is a list an admin can go
/// and fix.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.count,
    required this.label,
    this.detail,
    this.emphasis = false,
  });

  final int count;
  final String label;
  final String? detail;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count ${count == 1 ? 'student' : 'students'} $label',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
              color: emphasis ? Ps.ink : Ps.muted,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: const TextStyle(fontSize: 12, color: Ps.faint),
            ),
        ],
      ),
    );
  }
}
