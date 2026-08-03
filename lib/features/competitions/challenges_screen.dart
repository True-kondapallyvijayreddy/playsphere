import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/challenge.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// Inter-club challenges — school v school, village v village, club v club.
///
/// CLAUDE.md calls this the heart of the OS alongside scoring, and it is the
/// one flow that crosses a tenant boundary. Two things about the previous
/// version of this screen made it unusable rather than merely unfinished:
///
/// 1. It asked the organizer to **type the opponent's raw Firestore document
///    id** into a text field. Nobody outside this repository knows their
///    club's document id, so in practice no challenge could ever be addressed
///    correctly. Opponents are now picked from the public club directory.
/// 2. Accepting called a repository method that Firestore rejected every time
///    (it wrote into the *challenger's* tenant), and the failure was invisible
///    because the screen ignored errors. Both halves are fixed — see
///    `CommunityRepository.acceptChallenge`.
///
/// It was also never routed, so none of this was reachable at all.
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenges = ref.watch(challengesProvider(orgId));
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Challenges',
      subtitle: 'Play another club, school or village',
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openIssueSheet(context, ref),
              icon: const Icon(Icons.sports_kabaddi),
              label: const Text('Challenge a club'),
            ),
      body: AsyncView(
        value: challenges,
        onRetry: () => ref.invalidate(challengesProvider(orgId)),
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.sports_kabaddi_outlined,
              title: 'No challenges yet',
              message: canManage
                  ? 'Challenge a rival school, village or club and agree a '
                      'date. Once they accept, the match appears for both '
                      'sides ready to score.'
                  : 'An event manager can challenge another club.',
              action: !canManage
                  ? null
                  : FilledButton.icon(
                      onPressed: () => _openIssueSheet(context, ref),
                      icon: const Icon(Icons.sports_kabaddi),
                      label: const Text('Challenge a club'),
                    ),
            );
          }

          // Incoming pending first: those are the only ones carrying an
          // obligation, and burying them under your own outgoing challenges is
          // how a village team ends up looking rude.
          final incoming =
              all.where((c) => c.isIncomingFor(orgId) && c.isPending).toList();
          final outgoing =
              all.where((c) => !c.isIncomingFor(orgId) && c.isPending).toList();
          final settled = all.where((c) => !c.isPending).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0)));

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ContentBounds(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (incoming.isNotEmpty)
                      _Section(
                        title: 'Waiting for your answer',
                        subtitle: 'Pick a date to accept, or decline.',
                        children: [
                          for (final c in incoming)
                            _ChallengeCard(
                              challenge: c,
                              orgId: orgId,
                              canManage: canManage,
                            ),
                        ],
                      ),
                    if (outgoing.isNotEmpty)
                      _Section(
                        title: 'Sent, awaiting reply',
                        children: [
                          for (final c in outgoing)
                            _ChallengeCard(
                              challenge: c,
                              orgId: orgId,
                              canManage: canManage,
                            ),
                        ],
                      ),
                    if (settled.isNotEmpty)
                      _Section(
                        title: 'Answered',
                        children: [
                          for (final c in settled)
                            _ChallengeCard(
                              challenge: c,
                              orgId: orgId,
                              canManage: canManage,
                            ),
                        ],
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

  void _openIssueSheet(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _IssueChallengeDialog(orgId: orgId),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _ChallengeCard extends ConsumerStatefulWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.orgId,
    required this.canManage,
  });

  final Challenge challenge;
  final String orgId;
  final bool canManage;

  @override
  ConsumerState<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends ConsumerState<_ChallengeCard> {
  bool _busy = false;

  Future<void> _accept(DateTime slot) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || _busy) return;
    setState(() => _busy = true);
    try {
      final comp = await ref.read(communityRepositoryProvider).acceptChallenge(
            challenge: widget.challenge,
            selectedSlot: slot,
            acceptedByUid: uid,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accepted. The match is ready to score.')),
      );
      // Straight to the match. An "accepted" toast that leaves the organizer
      // hunting for the fixture is where this flow used to lose people.
      context.push(Routes.competition(comp.orgId, comp.id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(communityRepositoryProvider)
          .declineChallenge(widget.challenge);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Challenge declined.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    if (_busy) return;
    // Confirmed because the other club has already been notified and may have
    // booked a ground around it — and because the challenge cannot be
    // un-withdrawn, only issued again.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this challenge?'),
        content: Text(
          '${widget.challenge.toOrgName} will see that you have taken it '
          'back. You can challenge them again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(communityRepositoryProvider)
          .withdrawChallenge(widget.challenge);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Challenge withdrawn.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Lets the accepting club choose among the dates the challenger proposed.
  Future<void> _chooseSlotAndAccept() async {
    final slots = widget.challenge.proposedSlots;
    if (slots.isEmpty) return;
    if (slots.length == 1) {
      await _accept(slots.first);
      return;
    }

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Which date suits you?'),
        children: [
          for (final s in slots)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text(_formatSlot(s)),
            ),
        ],
      ),
    );
    if (picked != null) await _accept(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final theme = Theme.of(context);
    final incoming = c.isIncomingFor(widget.orgId);
    final sport = SportCatalog.byId(c.sportId);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sport.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.opponentNameFor(widget.orgId),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusChip(challenge: c, incoming: incoming),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              incoming
                  ? '${sport.name} · they challenged you'
                  : '${sport.name} · you challenged them',
              style: theme.textTheme.bodySmall,
            ),
            if (c.venue != null && c.venue!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('At ${c.venue}', style: theme.textTheme.bodySmall),
            ],
            if (c.agreedSlot != null) ...[
              const SizedBox(height: 2),
              Text(
                'Agreed for ${_formatSlot(c.agreedSlot!)}',
                style: theme.textTheme.bodySmall,
              ),
            ] else if (c.proposedSlots.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Proposed: '
                '${c.proposedSlots.map(_formatSlot).join(' · ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),

            // Once accepted, BOTH clubs get the same door into the match. The
            // security rules grant the visiting club read access through
            // `participantOrgIds`, so this link works from either side.
            if (c.isAccepted && c.hasMatch)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.push(
                    Routes.competition(c.hostOrgId!, c.createdCompId!),
                  ),
                  icon: const Icon(Icons.sports_score),
                  label: const Text('Open the match'),
                ),
              )
            else if (incoming && c.isPending && widget.canManage)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _chooseSlotAndAccept,
                    icon: const Icon(Icons.check),
                    label: Text(_busy ? 'Working…' : 'Accept'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _decline,
                    child: const Text('Decline'),
                  ),
                ],
              )
            // The other half of the negotiation. Until this existed, a club
            // whose ground flooded could only wait for the opponent to
            // decline an offer both sides knew was dead.
            else if (c.canBeWithdrawnBy(widget.orgId) && widget.canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _withdraw,
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(_busy ? 'Working…' : 'Withdraw'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.challenge, required this.incoming});

  final Challenge challenge;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg) = switch (challenge.status) {
      'accepted' => ('Accepted', scheme.primaryContainer),
      'declined' => ('Declined', scheme.surfaceContainerHighest),
      // Reads from the perspective of whoever is looking: the club that took
      // it back sees that it did, the club that was offered sees that the
      // offer is gone rather than still owing them an answer.
      'withdrawn' => (
          incoming ? 'Withdrawn' : 'You withdrew',
          scheme.surfaceContainerHighest,
        ),
      _ => (incoming ? 'Your move' : 'Awaiting reply', scheme.tertiaryContainer),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: bg,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

/// Issues a challenge, picking the opponent from the public club directory.
class _IssueChallengeDialog extends ConsumerStatefulWidget {
  const _IssueChallengeDialog({required this.orgId});
  final String orgId;

  @override
  ConsumerState<_IssueChallengeDialog> createState() =>
      _IssueChallengeDialogState();
}

class _IssueChallengeDialogState
    extends ConsumerState<_IssueChallengeDialog> {
  final _search = TextEditingController();
  final _venue = TextEditingController();
  Organization? _opponent;
  String _sportId = 'cricket';
  final List<DateTime> _slots = [];
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _venue.dispose();
    super.dispose();
  }

  Future<void> _addSlot() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now.add(const Duration(days: 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (!mounted) return;
    final slot = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 9,
      time?.minute ?? 0,
    );
    setState(() => _slots.add(slot));
  }

  Future<void> _send() async {
    final opponent = _opponent;
    final me = ref.read(organizationProvider(widget.orgId)).valueOrNull;
    if (opponent == null || me == null || _slots.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).createChallenge(
            Challenge(
              id: '',
              fromOrgId: me.id,
              toOrgId: opponent.id,
              fromOrgName: me.name,
              toOrgName: opponent.name,
              sportId: _sportId,
              status: 'pending',
              proposedSlots: List.of(_slots),
              venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Challenge sent to ${opponent.name}.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgsAsync = ref.watch(publicOrgsProvider);
    final query = _search.text.trim().toLowerCase();

    // Never offer yourself as an opponent — the rules reject it and a club
    // playing itself is not a thing.
    final candidates = (orgsAsync.valueOrNull ?? const <Organization>[])
        .where((o) => o.id != widget.orgId)
        .where((o) => query.isEmpty || o.name.toLowerCase().contains(query))
        .take(40)
        .toList();

    final canSend = _opponent != null && _slots.isNotEmpty && !_busy;

    return AlertDialog(
      title: const Text('Challenge a club'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _sportId,
                decoration: const InputDecoration(
                  labelText: 'Sport',
                  border: OutlineInputBorder(),
                ),
                // Every sport the app can score, not the five that happened to
                // be typed into this dialog before.
                items: [
                  for (final s in SportCatalog.all)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.icon}  ${s.name}'),
                    ),
                ],
                onChanged: (v) => setState(() => _sportId = v ?? _sportId),
              ),
              const SizedBox(height: 12),

              if (_opponent != null)
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(_opponent!.name),
                    subtitle: Text(_subtitleFor(_opponent!)),
                    trailing: IconButton(
                      tooltip: 'Choose someone else',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _opponent = null),
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search public clubs, schools and villages',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                AsyncErrorStrip(
                  value: orgsAsync,
                  what: 'the club directory',
                ),
                SizedBox(
                  height: 200,
                  child: orgsAsync.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : candidates.isEmpty
                          ? Center(
                              child: Text(
                                query.isEmpty
                                    ? 'No other public clubs yet.'
                                    : 'No club matches “$query”.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : ListView(
                              children: [
                                for (final o in candidates)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.groups_outlined),
                                    title: Text(o.name),
                                    subtitle: Text(_subtitleFor(o)),
                                    onTap: () =>
                                        setState(() => _opponent = o),
                                  ),
                              ],
                            ),
                ),
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _venue,
                decoration: const InputDecoration(
                  labelText: 'Venue (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Propose one or more dates',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Offering a choice is what stops a challenge dying in a '
                'WhatsApp thread.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _slots)
                    InputChip(
                      label: Text(_formatSlot(s)),
                      onDeleted: () => setState(() => _slots.remove(s)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add a date'),
                    onPressed: _addSlot,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSend ? _send : null,
          child: Text(_busy ? 'Sending…' : 'Send challenge'),
        ),
      ],
    );
  }

  String _subtitleFor(Organization o) {
    final where = o.geo.district ?? o.district;
    final type = o.orgType.label;
    return where == null || where.isEmpty ? type : '$type · $where';
  }
}

String _formatSlot(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'am' : 'pm';
  final min = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '${d.day} ${months[d.month - 1]}, $h$min$ampm';
}
