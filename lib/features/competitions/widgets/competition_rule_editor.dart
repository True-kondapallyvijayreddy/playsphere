import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/providers.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';

/// Lets an organizer change the rules of an event after it has been created.
///
/// ## Why this is edit-in-place rather than a creation-time-only choice
///
/// Grassroots events change shape on the day. Rain takes an hour out of a
/// morning and a 20-over game becomes 12; a school hall is needed back at four
/// and best-of-five becomes best-of-three. Before this, the only rules an event
/// could have were the ones its sport shipped with, so the organizer's actual
/// decision lived on a WhatsApp message and the scoreboard kept insisting the
/// innings ran to twenty.
///
/// ## What it can and cannot reach
///
/// It writes [Competition.scoringConfig], which is layered over the sport's
/// preset when a fixture is CREATED. So it changes matches not yet drawn, and
/// deliberately cannot touch a fixture that already exists — those froze their
/// rules at creation, per CLAUDE.md §3, and rewriting them would retroactively
/// change how a played match was scored. The dialog says so rather than
/// leaving the organizer to discover it.
///
/// Every field here is a key some plugin reads through `ctx.intConfig`. None
/// of them are constants in engine code — that is §12.2, and this screen is
/// what that rule was for.
class CompetitionRuleEditor extends ConsumerStatefulWidget {
  const CompetitionRuleEditor({
    super.key,
    required this.competition,
  });

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CompetitionRuleEditor(competition: competition),
    );
  }

  @override
  ConsumerState<CompetitionRuleEditor> createState() =>
      _CompetitionRuleEditorState();
}

class _CompetitionRuleEditorState extends ConsumerState<CompetitionRuleEditor> {
  final _formKey = GlobalKey<FormState>();

  /// The rules currently in force — sport preset with the organizer's existing
  /// overrides already applied. Every field seeds from here, so the dialog
  /// opens showing what the event actually does rather than a blank box.
  late final Map<String, dynamic> _current = widget.competition
      .effectiveScoringConfig(
        SportCatalog.byId(widget.competition.sportId).config,
      );

  late final _matchMinutes = TextEditingController(
    text: '${widget.competition.scheduleConfig.matchMinutes}',
  );
  late final _overs = TextEditingController(text: _int('oversPerInnings', 20));
  late final _ballsPerOver = TextEditingController(
    text: _int('ballsPerOver', 6),
  );
  late final _setsToWin = TextEditingController(text: _int('setsToWin', 2));
  late final _pointsPerSet = TextEditingController(
    text: _int('pointsPerSet', 21),
  );

  bool _busy = false;

  String _int(String key, int fallback) =>
      '${_current[key] is num ? (_current[key] as num).toInt() : fallback}';

  bool get _isCricket => widget.competition.scoringPluginKey == 'cricket';

  /// Sports whose engine reads `setsToWin` / `pointsPerSet` — the set-based
  /// family, asked of the registry rather than listed by id here so a new
  /// racket sport does not have to be remembered in two places.
  bool get _isSetBased => const {
        'badminton',
        'table_tennis',
        'volleyball',
        'tennis',
      }.contains(widget.competition.scoringPluginKey);

  @override
  void dispose() {
    _matchMinutes.dispose();
    _overs.dispose();
    _ballsPerOver.dispose();
    _setsToWin.dispose();
    _pointsPerSet.dispose();
    super.dispose();
  }

  /// Records only what the organizer actually CHANGED.
  ///
  /// A value equal to the sport's own default is left out rather than written
  /// as an override. Otherwise every event edited once would pin a full copy
  /// of its sport's rules, and improving a preset later would silently skip
  /// every event that had ever been opened in this dialog.
  void _put(Map<String, dynamic> into, String key, int? value, int preset) {
    if (value == null) return;
    if (value == preset) {
      into.remove(key);
    } else {
      into[key] = value;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      final c = widget.competition;
      final sportPreset = SportCatalog.byId(c.sportId).config;
      int presetOf(String key, int fallback) =>
          sportPreset[key] is num ? (sportPreset[key] as num).toInt() : fallback;

      final overrides = Map<String, dynamic>.from(c.scoringConfig);

      if (_isCricket) {
        _put(overrides, 'oversPerInnings',
            int.tryParse(_overs.text.trim()), presetOf('oversPerInnings', 20));
        _put(overrides, 'ballsPerOver',
            int.tryParse(_ballsPerOver.text.trim()), presetOf('ballsPerOver', 6));
      }
      if (_isSetBased) {
        _put(overrides, 'setsToWin',
            int.tryParse(_setsToWin.text.trim()), presetOf('setsToWin', 2));
        _put(overrides, 'pointsPerSet',
            int.tryParse(_pointsPerSet.text.trim()),
            presetOf('pointsPerSet', 21));
      }

      final minutes = int.tryParse(_matchMinutes.text.trim()) ??
          c.scheduleConfig.matchMinutes;

      await ref.read(competitionRepositoryProvider).updateCompetition(
            c.withRules(
              scoringConfig: overrides,
              scheduleConfig: c.scheduleConfig.copyWith(matchMinutes: minutes),
            ),
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rules updated. Matches not yet drawn will use them.'),
        ),
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
    final c = widget.competition;

    return AlertDialog(
      title: Text('Rules — ${c.sportName}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Applies to matches not yet drawn. Fixtures that already '
                  'exist keep the rules they were created with, so a match '
                  'already played is never re-scored.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _NumberField(
                  controller: _matchMinutes,
                  label: 'Match duration (minutes)',
                  helper: 'Used by the timetable, not by the scoreboard',
                  min: 5,
                ),
                if (_isCricket) ...[
                  const SizedBox(height: 16),
                  _NumberField(
                    controller: _overs,
                    label: 'Overs per innings',
                    helper: 'e.g. 20 for T20, or 8 for an evening game',
                    min: 1,
                  ),
                  const SizedBox(height: 16),
                  _NumberField(
                    controller: _ballsPerOver,
                    label: 'Balls per over',
                    helper: 'Standard is 6',
                    min: 1,
                  ),
                ],
                if (_isSetBased) ...[
                  const SizedBox(height: 16),
                  _NumberField(
                    controller: _setsToWin,
                    label: 'Sets to win',
                    helper: 'Best of 3 means 2 sets to win',
                    min: 1,
                  ),
                  const SizedBox(height: 16),
                  _NumberField(
                    controller: _pointsPerSet,
                    label: 'Points per set',
                    helper: 'Badminton 21, table tennis 11, volleyball 25',
                    min: 1,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save rules'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.min,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final int min;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n == null) return 'Enter a number';
        return n < min ? 'Minimum $min' : null;
      },
    );
  }
}
