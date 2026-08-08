import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/fixture.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';

/// "It is Tuesday's match and we want to play it now."
///
/// ## Why this asks anything at all
///
/// The obvious implementation of "start early" is a button that opens the
/// scoring pad. That is what was here, behind three checkboxes that could not
/// be unticked and were never read — the dialog looked like it was gathering
/// agreement and was in fact gathering nothing.
///
/// A match pulled forward is genuinely a different match. It may be played
/// with a different ball, under different light, by a side missing the two
/// players who were coming after work. Every one of those changes what the
/// resulting figures mean, and the questions worth asking are not the same in
/// cricket as in badminton — which is why they come from
/// [PreMatchChecks.forSport] rather than being written here.
///
/// The answers are stored on the fixture, and the fixture's scheduled time is
/// moved to now. That second part is what stops every "running late" banner in
/// the product from reporting the match as three days overdue afterwards.
class StartEarlySheet extends ConsumerStatefulWidget {
  const StartEarlySheet({
    super.key,
    required this.fixture,
    required this.sportId,
  });

  final Fixture fixture;
  final String sportId;

  static Future<void> show(
    BuildContext context, {
    required Fixture fixture,
    required String sportId,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => StartEarlySheet(fixture: fixture, sportId: sportId),
      );

  @override
  ConsumerState<StartEarlySheet> createState() => _StartEarlySheetState();
}

class _StartEarlySheetState extends ConsumerState<StartEarlySheet> {
  late final List<PreMatchCheck> _checks =
      PreMatchChecks.forSport(widget.sportId);

  /// Everything starts UNticked.
  ///
  /// Pre-ticking would make the fastest path through this screen — open, tap
  /// Start — record every question as answered yes without anybody having read
  /// one, which is worse than not asking. The organizer ticks what is true.
  late final Map<String, bool> _answers = {
    for (final c in _checks) c.id: false,
  };

  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// A "no" is allowed, and is the interesting answer.
  ///
  /// Refusing to start unless everything is ticked would teach organizers to
  /// tick everything. The match can start with a different ball and a borrowed
  /// player — it just has to SAY so, which is the whole point of recording the
  /// answers rather than gating on them.
  int get _unmet => _answers.values.where((v) => !v).length;

  Future<void> _start() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _busy = true);

    final f = widget.fixture;
    try {
      await ref.read(competitionRepositoryProvider).startMatchEarly(
            fixture: f,
            checks: _answers,
            byUid: uid,
            note: _note.text,
          );

      if (!mounted) return;
      Navigator.of(context).pop();

      final canManage = ref
          .read(myCapabilitiesProvider(f.orgId))
          .contains(Capability.manageCompetitions);
      context.push(
        f.canBeScoredBy(uid, isOrgManager: canManage)
            ? Routes.scoring(f.orgId, f.compId, f.id)
            : Routes.watch(f.orgId, f.compId, f.id),
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
    final theme = Theme.of(context);
    final f = widget.fixture;
    final scheduled = f.scheduledAt;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Play this match now?',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${f.displayNameA()} v ${f.displayNameB()}',
                style: theme.textTheme.bodyMedium,
              ),
              if (scheduled != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Scheduled for ${_when(scheduled)} — starting now moves it '
                  'to today.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (final c in _checks)
                CheckboxListTile(
                  value: _answers[c.id] ?? false,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _answers[c.id] = v ?? false),
                  title: Text(c.label),
                  subtitle: c.detail == null ? null : Text(c.detail!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                enabled: !_busy,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Anything different about this match?',
                  hintText: _unmet == 0
                      ? 'Optional'
                      : 'Say what changed — it is kept with the result',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _unmet == 0
                    ? 'All confirmed. This is recorded against the match.'
                    : '$_unmet not confirmed. The match can still start — '
                        'the answers are kept with the result either way.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _start,
                      child: Text(_busy ? 'Starting…' : 'Start match'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} $hh:$mm ${d.hour < 12 ? 'am' : 'pm'}';
  }
}
