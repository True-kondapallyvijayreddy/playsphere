import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// Event creation.
///
/// One screen rather than a multi-step wizard: an organizer setting up eight
/// events for a sports day should not click through five pages each time.
/// Sensible defaults come from the sport, so the only genuinely required
/// choices are a name, a sport and a category.
class CreateCompetitionScreen extends ConsumerStatefulWidget {
  const CreateCompetitionScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState
    extends ConsumerState<CreateCompetitionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _venue = TextEditingController();

  SportSpec _sport = SportCatalog.byId('badminton');
  late CompetitionCategory _category = CompetitionCategory.presets().first;
  CompetitionFormat _format = CompetitionFormat.roundRobin;
  DateTime? _startDate;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    super.dispose();
  }

  List<CompetitionFormat> get _formatsForSport {
    if (_sport.isPerformance) {
      return [CompetitionFormat.finalOnly, CompetitionFormat.heatsThenFinal];
    }
    return [
      CompetitionFormat.roundRobin,
      CompetitionFormat.knockout,
      CompetitionFormat.leagueTable,
      CompetitionFormat.swiss,
    ];
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final compId =
          await ref.read(competitionRepositoryProvider).createCompetition(
                Competition(
                  id: '',
                  orgId: widget.orgId,
                  name: _name.text.trim(),
                  sportId: _sport.id,
                  sportName: _sport.name,
                  archetype: _sport.archetype,
                  entrantType: _sport.defaultEntrantType,
                  format: _format,
                  status: CompetitionStatus.draft,
                  category: _category,
                  scoringPluginKey: _sport.pluginKey,
                  venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
                  startDate: _startDate,
                  createdBy: uid,
                ),
              );
      if (mounted) {
        context.go(Routes.competition(widget.orgId, compId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = CompetitionCategory.presets(cutOff: _startDate);

    return AppScaffold(
      orgId: widget.orgId,
      title: 'New event',
      body: ListView(
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Event name',
                      hintText: 'e.g. Inter-house Badminton 2026',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'At least 3 characters'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(
                    value: _sport.id,
                    isExpanded: true,
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
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        _sport = SportCatalog.byId(id);
                        if (!_formatsForSport.contains(_format)) {
                          _format = _formatsForSport.first;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scored using: '
                    '${ScoringRegistry.resolve(_sport.pluginKey).displayName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),

                  // Category is a required, first-class choice rather than
                  // something buried in the event name. It is what makes
                  // eligibility checkable and medal tallies correct.
                  DropdownButtonFormField<String>(
                    value: _category.label,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      helperText:
                          'Entries are checked against this automatically',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in presets)
                        DropdownMenuItem(value: c.label, child: Text(c.label)),
                    ],
                    onChanged: (label) {
                      final match =
                          presets.firstWhere((c) => c.label == label);
                      setState(() => _category = match);
                    },
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<CompetitionFormat>(
                    value: _format,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final f in _formatsForSport)
                        DropdownMenuItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (f) => setState(() => _format = f ?? _format),
                  ),
                  const SizedBox(height: 20),

                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 3),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start date',
                        helperText:
                            'Ages are measured on this date, so a birthday '
                            'mid-event cannot change anyone\'s category',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _startDate == null
                            ? 'Not set'
                            : DateFormat('d MMMM yyyy').format(_startDate!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _venue,
                    decoration: const InputDecoration(
                      labelText: 'Venue (optional)',
                      hintText: 'e.g. Main court',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 28),

                  FilledButton(
                    onPressed: _busy ? null : _create,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_busy ? 'Creating…' : 'Create event'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The event starts as a draft. You open entries, approve '
                    'players, then generate the draw.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
