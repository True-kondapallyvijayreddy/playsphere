import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/organization.dart';
import '../../../core/models/tournament.dart';
import '../../../core/models/tournament_invite.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Inviting other clubs into a tournament.
///
/// ## Why this exists alongside the share button
///
/// The public link is for broadcast — a poster, a WhatsApp group, a parent who
/// wants the scores. It cannot do the thing an organizer running an open
/// tournament actually needs, which is to ask eleven named clubs and then know
/// which of them answered. A link that has been sent leaves no record: you
/// cannot list it, count it, or tell a refusal apart from a school that never
/// saw it.
///
/// So this sends an invitation per club. Each one reaches that club's
/// organizers as a notification, and each one comes back with an answer the
/// host can read off the same sheet.
///
/// ## Why clubs already invited stay visible
///
/// They are shown, with their answer, and cannot be picked again. Hiding them
/// would make the sheet lie: an organizer who invited a school last week and
/// does not see it in the list concludes they forgot, and sends again.
class InviteClubsSheet extends ConsumerStatefulWidget {
  const InviteClubsSheet({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<InviteClubsSheet> createState() => _InviteClubsSheetState();
}

class _InviteClubsSheetState extends ConsumerState<InviteClubsSheet> {
  final _search = TextEditingController();
  final _message = TextEditingController();
  final _picked = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.tournament;
    final key = (orgId: t.orgId, tournamentId: t.id);

    final invitesAsync = ref.watch(tournamentInvitesProvider(key));
    final invites = invitesAsync.valueOrNull ?? const <TournamentInvite>[];
    final invitedById = {for (final i in invites) i.toOrgId: i};

    final orgsAsync = ref.watch(publicOrgsProvider);
    final query = _search.text.trim().toLowerCase();
    final candidates = [
      for (final o in orgsAsync.valueOrNull ?? const <Organization>[])
        // Never the host itself: the rules reject it, and a club inviting
        // itself to its own tournament is not a thing.
        if (o.id != t.orgId &&
            !invitedById.containsKey(o.id) &&
            (query.isEmpty || o.name.toLowerCase().contains(query)))
          o,
    ].take(40).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Invite other clubs', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Each club you pick gets this tournament in front of its '
              'organizers, and their answer comes back here.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            if (invites.isNotEmpty) ...[
              Text('Already invited', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final i in invites)
                    Chip(
                      avatar: Icon(_answerIcon(i), size: 16),
                      label: Text('${i.toOrgName} · ${_answerLabel(i)}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Find a club',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            AsyncErrorStrip(value: orgsAsync, what: 'the club directory'),
            AsyncErrorStrip(
              value: invitesAsync,
              what: 'the clubs already invited',
            ),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: candidates.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        orgsAsync.isLoading
                            ? 'Looking for clubs…'
                            : query.isEmpty
                                ? 'No other clubs are listed publicly yet.'
                                : 'No club matches “${_search.text.trim()}”.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final o in candidates)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _picked.contains(o.id),
                            title: Text(o.name),
                            subtitle: Text(_where(o)),
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                _picked.add(o.id);
                              } else {
                                _picked.remove(o.id);
                              }
                            }),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _message,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'A line to send with it (optional)',
                hintText: 'Bring your U-14s — we are two teams short.',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _picked.isEmpty || _busy ? null : _send,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(
                    _picked.isEmpty
                        ? 'Invite'
                        : 'Invite ${_picked.length} '
                            '${_picked.length == 1 ? 'club' : 'clubs'}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _where(Organization o) {
    final parts = [
      o.orgType.label,
      if ((o.city ?? '').isNotEmpty) o.city!,
      if ((o.district ?? '').isNotEmpty) o.district!,
    ];
    return parts.join(' · ');
  }

  static IconData _answerIcon(TournamentInvite i) => switch (i.status) {
        'accepted' => Icons.check_circle_outline,
        'declined' => Icons.cancel_outlined,
        'withdrawn' => Icons.undo,
        _ => Icons.schedule_outlined,
      };

  static String _answerLabel(TournamentInvite i) => switch (i.status) {
        'accepted' => 'coming',
        'declined' => 'declined',
        'withdrawn' => 'withdrawn',
        _ => 'no reply yet',
      };

  Future<void> _send() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final host = ref.read(organizationProvider(widget.tournament.orgId))
        .valueOrNull;
    final directory =
        ref.read(publicOrgsProvider).valueOrNull ?? const <Organization>[];
    final chosen = [
      for (final o in directory)
        if (_picked.contains(o.id)) (orgId: o.id, name: o.name),
    ];
    if (chosen.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(tournamentRepositoryProvider).inviteClubs(
            tournament: widget.tournament,
            // The host's own name, read from its org document rather than
            // assumed: it is what the invited club sees as the sender, and
            // "A club has invited you" is not an invitation anybody acts on.
            hostOrgName: host?.name ?? 'A club',
            clubs: chosen,
            invitedByUid: uid,
            message: _message.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              chosen.length == 1
                  ? 'Invitation sent to ${chosen.single.name}.'
                  : '${chosen.length} clubs invited.',
            ),
          ),
        );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}
