import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// "Let me score this one."
///
/// The missing half of the scorer flow. Getting the pen used to require an
/// admin to open the match list and add you, from a shortlist of members who
/// already held the Judge / Scorer role — which assumes the admin is at the
/// ground, has the app open, and knows who turned up. On a village pitch none
/// of those is reliably true, so an umpire who arrived ready to score had no
/// way to say so and the match went unscored.
///
/// This renders nothing at all for anyone who already holds the pen, and
/// nothing once a match is over — asking to score a finished match is not a
/// thing anyone means to do.
class AskToScoreButton extends ConsumerStatefulWidget {
  const AskToScoreButton({
    super.key,
    required this.fixture,
    this.expanded = false,
  });

  final Fixture fixture;

  /// Fills the width and reads as a primary action. Used where this IS the
  /// screen's point — the scoring pad's "you are not assigned" state — as
  /// opposed to one option among several on the spectator view.
  final bool expanded;

  @override
  ConsumerState<AskToScoreButton> createState() => _AskToScoreButtonState();
}

class _AskToScoreButtonState extends ConsumerState<AskToScoreButton> {
  bool _busy = false;

  Future<void> _ask() async {
    final uid = ref.read(currentUidProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (uid == null || _busy) return;

    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _AskDialog(),
    );
    if (note == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(competitionRepositoryProvider).requestToScore(
            fixture: widget.fixture,
            uid: uid,
            displayName: me?.displayName ?? 'A member',
            note: note.trim().isEmpty ? null : note.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asked. An admin of this club will see it.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final f = widget.fixture;

    // Already holds the pen, or there is nothing left to score.
    if (uid == null || f.scorerUids.contains(uid)) return const SizedBox.shrink();
    if (!f.status.acceptsScoring) return const SizedBox.shrink();

    final request = ref
        .watch(myScoringRequestProvider(FixtureRef(f.orgId, f.compId, f.id)))
        .valueOrNull;

    if (request != null && request.isPending) {
      return const _Note(
        icon: Icons.hourglass_top_outlined,
        text: 'You have asked to score this match. Waiting for an admin.',
      );
    }
    if (request != null && request.isDeclined) {
      return const _Note(
        icon: Icons.do_not_disturb_on_outlined,
        text: 'Your request to score this match was not granted.',
      );
    }

    final button = FilledButton.tonalIcon(
      onPressed: _busy ? null : _ask,
      icon: const Icon(Icons.sports_outlined),
      label: Text(_busy ? 'Asking…' : 'Ask to score this match'),
    );

    return widget.expanded
        ? SizedBox(width: double.infinity, child: button)
        : Align(alignment: Alignment.centerLeft, child: button);
  }
}

/// Collects the one sentence that decides most of these requests.
///
/// Optional on purpose. An admin approving from a ground with one bar of
/// signal mostly needs to know "who is this and why" — but requiring it would
/// put a keyboard between a willing scorer and a match about to start, which
/// is the exact friction this feature exists to remove.
class _AskDialog extends StatefulWidget {
  const _AskDialog();

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ask to score this match'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'An admin of the club has to agree before you can score. They '
            'will see your name and this note.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Anything they should know? (optional)',
              hintText: 'I am the umpire today',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.hintColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
