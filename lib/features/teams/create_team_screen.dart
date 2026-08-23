import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/announcement.dart';
import '../../core/models/enums.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_context_banner.dart';
import '../../shared/identity.dart';
import '../home/home_providers.dart';

/// Raising a squad out of a club's members list.
///
/// This is the "100 members, pick 11 for Sunday" flow: tick names off the
/// roster this club already has, name the side, and it exists as its own
/// document from the moment it's created — on [Routes.myTeams] for every
/// player ticked, and editable from here or from the team's own page for as
/// long as it plays.
class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  String? _sportId;
  final Set<String> _picked = {};
  bool _busy = false;

  /// Narrow the roster to the people who have said they are free.
  ///
  /// The step the product asks a club to take before picking a side — put out
  /// a match call, see who answers — produced an answer nobody could act on:
  /// the responses sat on the availability screen, and this screen, where the
  /// side is actually chosen, showed all 140 members in alphabetical order.
  /// So an admin read one screen and ticked names on another. This closes
  /// that: on, the list is whoever said "In" to a live call for this sport.
  bool _availableOnly = false;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Everyone who answered "In" to a live availability call for the chosen
  /// sport, or null before a sport has been chosen — there is no such thing
  /// as "available" until the question names a game.
  ///
  /// Maybes are not included. A squad picked from people who said maybe is a
  /// squad the captain has to chase, and the person who said "In" is the one
  /// who committed.
  Set<String>? _availableUids() {
    final sportId = _sportId;
    if (sportId == null) return null;
    final calls =
        ref.watch(matchRsvpsProvider(widget.orgId)).valueOrNull ?? const [];
    final uids = <String>{};
    for (final call in calls) {
      if (call.match?.sportId != sportId) continue;
      final poll = call.poll;
      if (poll == null) continue;
      for (final entry in poll.votes.entries) {
        if (entry.value == Rsvp.yes) uids.add(entry.key);
      }
    }
    return uids;
  }

  Future<void> _create() async {
    final uid = ref.read(currentUidProvider);
    final sportId = _sportId;
    if (uid == null || sportId == null) return;
    setState(() => _busy = true);
    try {
      final teamId = await ref.read(teamRepositoryProvider).createTeam(
            name: _name.text,
            sportId: sportId,
            createdByUid: uid,
            type: TeamType.permanent,
            clubId: widget.orgId,
            captainUid: uid,
            memberUids: _picked.toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_name.text.trim()} created.')),
      );
      context.pushReplacement(Routes.team(teamId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref
        .watch(myCapabilitiesProvider(widget.orgId))
        .contains(Capability.manageOrganization);

    if (!canCreate) {
      return Scaffold(
        appBar: AppBar(title: const Text('New team')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: "Only the club's owner can raise a team",
          message: 'Ask the owner to create it, or to make you a captain '
              'or manager on an existing one.',
        ),
      );
    }

    final members = ref.watch(orgMembersProvider(widget.orgId));
    final available = _availableUids();
    final query = _search.text.trim().toLowerCase();
    final canSubmit = !_busy &&
        _name.text.trim().isNotEmpty &&
        _sportId != null &&
        _picked.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('New team')),
      body: AsyncView(
        value: members,
        builder: (all) {
          final active = all.where((m) => m.isActive).toList();
          final shortlist = available == null || !_availableOnly
              ? active
              : [
                  for (final m in active)
                    if (available.contains(m.uid)) m,
                ];
          final candidates = query.isEmpty
              ? shortlist
              : shortlist
                  .where((m) => m.displayName.toLowerCase().contains(query))
                  .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentBounds(
                maxWidth: 720,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A team belongs to the club that raised it, and the
                    // roster below is drawn from that club's members — so the
                    // club is named before the first field rather than left
                    // to be inferred from whose faces are in the picker.
                    ClubContextBanner(orgId: widget.orgId),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Team name',
                        hintText: 'e.g. Warriors — Sunday XI',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _sportId,
                      decoration: const InputDecoration(
                        labelText: 'Sport',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in SportCatalog.all)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.icon}  ${s.name}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _sportId = v),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Pick players (${_picked.length} selected)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search members',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (available != null)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _availableOnly,
                        title: Text(
                          'Only who said they are free '
                          '(${available.length})',
                        ),
                        subtitle: const Text(
                          'From the live match calls for this sport.',
                        ),
                        onChanged: (v) =>
                            setState(() => _availableOnly = v ?? false),
                      ),
                    const SizedBox(height: 8),
                    if (candidates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _availableOnly
                                ? 'Nobody has said they are free yet.'
                                : 'No members match.',
                          ),
                        ),
                      )
                    else
                      for (final m in candidates)
                        CheckboxListTile(
                          value: _picked.contains(m.uid),
                          secondary: PsAvatar(
                            name: m.displayName,
                            photoUrl: m.photoUrl,
                            seed: m.uid,
                          ),
                          title: Text(m.displayName),
                          subtitle: Text(m.role.label),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _picked.add(m.uid);
                            } else {
                              _picked.remove(m.uid);
                            }
                          }),
                        ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: canSubmit ? _create : null,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shield_outlined),
                      label: Text(
                        _busy ? 'Creating…' : 'Create team',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
