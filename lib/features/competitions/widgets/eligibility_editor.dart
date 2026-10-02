import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Lets an organizer set, change or clear an event's age bound after it has
/// already been created — TC-ADM-008's "Edit Live Event Parameters" and
/// TC-ADM-067's "Set a Minimum-Age Rule on an Event".
///
/// ## Why editing this is safe on a live event
///
/// [CompetitionCategory.check] is what every registration and every roster
/// substitution is run against (see `LineupEditor`), always evaluated live
/// off whatever bound is on the document right now — so tightening or
/// loosening it here takes effect immediately for anyone entering or being
/// subbed in from this point on. It deliberately does NOT retroactively
/// re-check entrants already approved — see [CategoryDimension.age]'s
/// existing spec note that a rule change flags existing entrants for the
/// organizer to review rather than auto-rejecting them; this dialog only
/// changes the bound going forward.
class EligibilityEditor extends ConsumerStatefulWidget {
  const EligibilityEditor({super.key, required this.competition});

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EligibilityEditor(competition: competition),
    );
  }

  @override
  ConsumerState<EligibilityEditor> createState() => _EligibilityEditorState();
}

class _EligibilityEditorState extends ConsumerState<EligibilityEditor> {
  final _formKey = GlobalKey<FormState>();
  late bool _enforceAge = widget.competition.category.dimensions
          .contains(CategoryDimension.age) &&
      (widget.competition.category.minAge != null ||
          widget.competition.category.maxAge != null);
  late final _minAge = TextEditingController(
    text: widget.competition.category.minAge?.toString() ?? '',
  );
  late final _maxAge = TextEditingController(
    text: widget.competition.category.maxAge?.toString() ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _minAge.dispose();
    _maxAge.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      final c = widget.competition;
      final category = c.category;
      final min = _enforceAge ? int.tryParse(_minAge.text.trim()) : null;
      final max = _enforceAge ? int.tryParse(_maxAge.text.trim()) : null;

      final updated = CompetitionCategory(
        label: category.label,
        dimensions: _enforceAge
            ? {...category.dimensions, CategoryDimension.age}
            : category.dimensions.difference({CategoryDimension.age}),
        minAge: min,
        maxAge: max,
        // The reference date stays the event's start — see
        // [CompetitionCategory.ageCutOffDate] — never "today".
        ageCutOffDate: category.ageCutOffDate ?? c.startDate,
        allowedGenders: category.allowedGenders,
        minWeightKg: category.minWeightKg,
        maxWeightKg: category.maxWeightKg,
        grade: category.grade,
      );

      await ref
          .read(competitionRepositoryProvider)
          .updateCompetition(c.copyWith(category: updated));

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Age bound updated. New entries and substitutions are checked '
            'against it immediately; already-approved entrants are not '
            'auto-rejected.',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Age & eligibility'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Applies from the moment you save — new registrations and '
                  'any roster substitution are checked against it. Players '
                  'already approved are flagged for your review, not '
                  'auto-rejected.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _enforceAge,
                  title: const Text('Enforce age bounds'),
                  onChanged: (v) =>
                      setState(() => _enforceAge = v ?? false),
                ),
                if (_enforceAge) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _minAge,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minimum age',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _maxAge,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Maximum age',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Measured on ${widget.competition.startDate != null ? _fmt(widget.competition.startDate!) : "the event start date, once set"}.',
                    style: theme.textTheme.bodySmall,
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
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
