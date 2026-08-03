import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dispute.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Raising and deciding a protest against a result.
///
/// The event log is append-only and the scorer is locked, which makes the
/// record tamper-proof but not right — a scorer can press the wrong button and
/// a player can be a year too old for the category. Without a path to say so
/// the argument happens on WhatsApp, and the app becomes the thing people
/// argue about rather than the thing that settles it.
class DisputeCard extends ConsumerWidget {
  const DisputeCard({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!fixture.hasResult && fixture.status != FixtureStatus.disputed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final key = (
      orgId: fixture.orgId,
      compId: fixture.compId,
      fixtureId: fixture.id,
    );
    final disputes =
        ref.watch(disputesProvider(key)).valueOrNull ?? const <Dispute>[];
    final open = [
      for (final d in disputes)
        if (d.status == DisputeStatus.open) d,
    ];

    final canReferee = ref
        .watch(myCapabilitiesProvider(fixture.orgId))
        .contains(Capability.manageCompetitions);
    final stillOpen = withinProtestWindow(fixture.completedAt);

    if (disputes.isEmpty && !stillOpen) return const SizedBox.shrink();

    return Card(
      color: open.isEmpty ? null : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gavel_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  open.isEmpty ? 'Result' : 'Result under protest',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              stillOpen
                  ? 'This result can be protested for one hour after it was '
                      'recorded. After that it is final — a bracket cannot '
                      'advance while an earlier match might be overturned.'
                  : 'The protest window has closed.',
              style: theme.textTheme.bodySmall,
            ),

            for (final d in disputes) ...[
              const Divider(height: 20),
              Text(
                '${d.reason.label} · ${d.raisedByName}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (d.detail != null)
                Text(d.detail!, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                d.status.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: d.status == DisputeStatus.open
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (d.resolutionNote != null)
                Text(
                  '"${d.resolutionNote!}"',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              // A referee decides somebody else's protest, never their own.
              if (d.status == DisputeStatus.open &&
                  canReferee &&
                  d.raisedByUid != ref.watch(currentUidProvider))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _decide(context, ref, d, false),
                        child: const Text('Reject — result stands'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _decide(context, ref, d, true),
                        child: const Text('Uphold — reopen for correction'),
                      ),
                    ],
                  ),
                ),
            ],

            if (stillOpen && open.isEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _raise(context, ref),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Protest this result'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _raise(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final result = await showDialog<({DisputeReason reason, String detail})>(
      context: context,
      builder: (_) => const _RaiseDisputeDialog(),
    );
    if (result == null) return;

    try {
      await ref.read(competitionRepositoryProvider).raiseDispute(
            fixture: fixture,
            raisedByUid: uid,
            raisedByName: me?.displayName ?? 'A competitor',
            reason: result.reason,
            detail: result.detail.isEmpty ? null : result.detail,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Dispute dispute,
    bool upheld,
  ) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final note = await showDialog<String>(
      context: context,
      builder: (_) => _DecisionDialog(upheld: upheld),
    );
    if (note == null || note.trim().isEmpty) return;

    try {
      await ref.read(competitionRepositoryProvider).resolveDispute(
            dispute: dispute,
            refereeUid: uid,
            upheld: upheld,
            note: note,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _RaiseDisputeDialog extends StatefulWidget {
  const _RaiseDisputeDialog();

  @override
  State<_RaiseDisputeDialog> createState() => _RaiseDisputeDialogState();
}

class _RaiseDisputeDialogState extends State<_RaiseDisputeDialog> {
  DisputeReason _reason = DisputeReason.wrongScore;
  final _detail = TextEditingController();

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Protest this result'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<DisputeReason>(
            value: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [
              for (final r in DisputeReason.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detail,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What happened',
              hintText: 'Third set was 21-19, recorded as 21-18.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is recorded against your name and can be read by anyone who '
            'can see the match. An anonymous protest is not one a referee can '
            'act on.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (reason: _reason, detail: _detail.text.trim()),
          ),
          child: const Text('Raise it'),
        ),
      ],
    );
  }
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.upheld});

  final bool upheld;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.upheld ? 'Uphold the protest' : 'Reject the protest'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.upheld
                ? 'The match reopens so the correction can be appended as a '
                    'reversal. The log is append-only — nothing is overwritten, '
                    'and the original record stays readable.'
                : 'The result stands exactly as it is.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Why',
              hintText: 'Scorecard matches the event log; result stands.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _note.text),
          child: const Text('Record the decision'),
        ),
      ],
    );
  }
}
