import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// Creating a multi-sport season (Feature #8).
///
/// ## What a season is, and why it is not just several tournaments
///
/// A school sports week, a village community's annual meet, a college's
/// inter-department calendar: one banner, several sports, each with its own
/// entry list, all sharing dates, a venue and a rest gap. The pieces already
/// existed — a [Tournament] is a container that events hang off, and each
/// sport is an ordinary [Competition] — but nothing put them together, so an
/// organizer had to create the container, then remember to open each sport
/// separately and attach it by hand.
///
/// This creates the whole thing in one pass: the season, plus one event per
/// sport chosen, each carrying its own entry limit.
///
/// ## External entries
///
/// The one genuinely new setting. A school running its own sports day wants
/// its own students only; the same school hosting a zonal meet wants other
/// schools to enter and expects to approve them. That is the difference
/// between [ParticipationModel.open] within the club and
/// `openToNonMembers` with [ParticipationModel.approval], and it is asked as
/// the plain question an organizer actually has in mind.
class CreateSeasonScreen extends ConsumerStatefulWidget {
  const CreateSeasonScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateSeasonScreen> createState() => _CreateSeasonScreenState();
}

class _CreateSeasonScreenState extends ConsumerState<CreateSeasonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _venue = TextEditingController();

  /// Sport id → the entry limit typed for it. Presence in this map is what
  /// "this sport is included" means, so adding and removing a sport cannot
  /// drift out of step with its own settings.
  final _entriesBySport = <String, TextEditingController>{};

  /// Sport id → the draw format chosen for it. Every sport in a season can
  /// need a different one — a five-team cricket league plays a round robin,
  /// a thirty-two-player badminton draw wants a knockout — so this is per
  /// sport rather than one setting for the whole season.
  final _formatBySport = <String, CompetitionFormat>{};

  DateTime? _startDate;
  DateTime? _endDate;
  late CompetitionCategory _category = CompetitionCategory.presets().first;
  bool _externalEntries = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    for (final c in _entriesBySport.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _chosenSports => _entriesBySport.keys.toList();

  void _toggleSport(String sportId, bool on) {
    setState(() {
      if (on) {
        _entriesBySport[sportId] = TextEditingController();
        _formatBySport[sportId] = SportCatalog.byId(sportId).competitionFormats.first;
      } else {
        _entriesBySport.remove(sportId)?.dispose();
        _formatBySport.remove(sportId);
      }
    });
  }

  int? _entriesFor(String sportId) {
    final text = _entriesBySport[sportId]?.text.trim() ?? '';
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// Entries from outside the club must be approved, not auto-confirmed.
  ///
  /// The whole point of opening a season to other clubs is that the host
  /// decides who is in — an open model would let anyone who found the link
  /// confirm themselves a place in a school's meet.
  ParticipationModel get _participation =>
      _externalEntries ? ParticipationModel.approval : ParticipationModel.open;

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_chosenSports.isEmpty) {
      showError(context, 'Pick at least one sport for this season.');
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final tournaments = ref.read(tournamentRepositoryProvider);
      final competitions = ref.read(competitionRepositoryProvider);

      // The season container first: every event created below carries its id,
      // and an event pointing at a season that does not exist yet would be a
      // dangling reference for however long the writes take.
      final seasonId = await tournaments.createTournament(
        Tournament(
          id: '',
          orgId: widget.orgId,
          name: _name.text.trim(),
          status: TournamentStatus.draft,
          startDate: _startDate,
          endDate: _endDate ?? _startDate,
          eventCount: _chosenSports.length,
          createdBy: uid,
        ),
      );

      for (final sportId in _chosenSports) {
        final sport = SportCatalog.byId(sportId);
        await competitions.createCompetition(
          Competition(
            id: '',
            orgId: widget.orgId,
            tournamentId: seasonId,
            // Named for the sport within the season rather than repeating the
            // season's name: a list of events reading "Sports Week 2026" five
            // times tells an organizer nothing.
            name: '${_name.text.trim()} — ${sport.name}',
            sportId: sport.id,
            sportName: sport.name,
            archetype: sport.archetype,
            entrantType: sport.defaultEntrantType,
            format: _formatBySport[sportId] ?? sport.competitionFormats.first,
            status: CompetitionStatus.draft,
            category: _category,
            scoringPluginKey: sport.pluginKey,
            venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
            startDate: _startDate,
            maxEntrants: _entriesFor(sportId),
            participationModel: _participation,
            waitlistEnabled: true,
            openToNonMembers: _externalEntries,
            createdBy: uid,
          ),
        );
      }

      // The sports above were created already attached, which is the one path
      // that bypasses `addEvent` and its increment. Without this the season
      // reports no events, and the rule that refuses to delete a tournament
      // with events in it stops protecting the ones it has.
      tournaments.noteEventsCreated(
        orgId: widget.orgId,
        tournamentId: seasonId,
        count: _chosenSports.length,
      );

      if (mounted) {
        // Replace: the season exists now, and a back press should reach the
        // club rather than a form that would create a second copy.
        context.pushReplacement(Routes.tournament(widget.orgId, seasonId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = CompetitionCategory.presets(cutOff: _startDate);

    return AppScaffold(
      orgId: widget.orgId,
      title: 'New season',
      subtitle: 'Several sports on one calendar',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Season name',
                      hintText: 'e.g. Nizampet Sports Week 2026',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'At least 3 characters'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  _DateField(
                    label: 'Starts',
                    helper: 'Ages are measured on this date',
                    value: _startDate,
                    onPick: (d) => setState(() => _startDate = d),
                  ),
                  const SizedBox(height: 20),
                  _DateField(
                    label: 'Ends (optional)',
                    helper: 'Leave blank for a one-day season',
                    value: _endDate,
                    onPick: (d) => setState(() => _endDate = d),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _venue,
                    decoration: const InputDecoration(
                      labelText: 'Venue (optional)',
                      hintText: 'e.g. School grounds',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(
                    value: _category.label,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      helperText: 'Applied to every sport in the season',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in presets)
                        DropdownMenuItem(value: c.label, child: Text(c.label)),
                    ],
                    onChanged: (label) => setState(
                      () => _category =
                          presets.firstWhere((c) => c.label == label),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ---- Sports, and the entries each takes ----------------
                  Text('Sports included', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Pick every sport this season runs. Each becomes its own '
                    'event with its own entry list, all under this season.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),

                  for (final sport in SportCatalog.all)
                    _SportRow(
                      sportId: sport.id,
                      icon: sport.icon,
                      name: sport.name,
                      included: _entriesBySport.containsKey(sport.id),
                      entries: _entriesBySport[sport.id],
                      format: _formatBySport[sport.id],
                      onFormatChanged: (f) =>
                          setState(() => _formatBySport[sport.id] = f),
                      onToggle: (on) => _toggleSport(sport.id, on),
                      onConfigChanged: (config) {},
                    ),

                  if (_chosenSports.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Pick at least one sport.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 28),

                  // ---- Who may enter -------------------------------------
                  Text('Who may enter', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _externalEntries,
                    onChanged: (v) => setState(() => _externalEntries = v),
                    title: const Text('Allow entries from outside this club'),
                    subtitle: Text(
                      _externalEntries
                          ? 'Anyone can apply, and every entry waits for you '
                              'to approve it.'
                          : 'Only members of this club can enter, and they '
                              'are confirmed straight away.',
                    ),
                  ),
                  const SizedBox(height: 28),

                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _chosenSports.isEmpty
                          ? 'Create season'
                          : 'Create season with ${_chosenSports.length} '
                              '${_chosenSports.length == 1 ? 'sport' : 'sports'}',
                    ),
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

class _SportRow extends StatefulWidget {
  const _SportRow({
    required this.sportId,
    required this.icon,
    required this.name,
    required this.included,
    required this.entries,
    required this.format,
    required this.onFormatChanged,
    required this.onToggle,
    required this.onConfigChanged,
  });

  final String sportId;
  final String icon;
  final String name;
  final bool included;
  final TextEditingController? entries;

  /// Null while the sport is not included — [CreateSeasonScreen._toggleSport]
  /// picks a default the moment it is checked, so this is only ever null for
  /// the instant before that setState lands.
  final CompetitionFormat? format;
  final ValueChanged<CompetitionFormat> onFormatChanged;
  final ValueChanged<bool> onToggle;
  final ValueChanged<Map<String, dynamic>> onConfigChanged;

  @override
  State<_SportRow> createState() => _SportRowState();
}

class _SportRowState extends State<_SportRow> {
  String _overs = '20';
  String _ballType = 'Leather';
  String _discipline = 'Singles';

  void _notify() {
    widget.onConfigChanged({
      'overs': int.tryParse(_overs) ?? 20,
      'ballType': _ballType,
      'discipline': _discipline,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCricket = widget.sportId == 'cricket';
    final isRacquet = widget.sportId == 'tennis' ||
        widget.sportId == 'badminton' ||
        widget.sportId == 'table_tennis';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: widget.included,
                  onChanged: (v) => widget.onToggle(v ?? false),
                  title: Text('${widget.icon}  ${widget.name}'),
                ),
              ),
              if (widget.included)
                SizedBox(
                  width: 108,
                  child: TextFormField(
                    controller: widget.entries,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Entries',
                      hintText: 'Any',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null;
                      final n = int.tryParse(t);
                      return (n == null || n < 1) ? 'No' : null;
                    },
                  ),
                ),
            ],
          ),
          if (widget.included && widget.format != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 4),
              child: SizedBox(
                width: 220,
                child: DropdownButtonFormField<CompetitionFormat>(
                  value: widget.format,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Format',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final f in SportCatalog.byId(widget.sportId).competitionFormats)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged: (f) {
                    if (f != null) widget.onFormatChanged(f);
                  },
                ),
              ),
            ),
          if (widget.included && (isCricket || isRacquet))
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4, bottom: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isCricket) ...[
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<String>(
                        value: _overs,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Overs',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: '20', child: Text('20 Overs (T20)')),
                          DropdownMenuItem(value: '15', child: Text('15 Overs')),
                          DropdownMenuItem(value: '12', child: Text('12 Overs')),
                          DropdownMenuItem(value: '10', child: Text('10 Overs')),
                          DropdownMenuItem(value: '8', child: Text('8 Overs')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _overs = v);
                            _notify();
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        value: _ballType,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Ball Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Leather', child: Text('Leather Ball')),
                          DropdownMenuItem(value: 'Tennis', child: Text('Tennis Ball')),
                          DropdownMenuItem(value: 'Tape', child: Text('Tape Ball')),
                          DropdownMenuItem(value: 'Soft', child: Text('Soft Ball')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _ballType = v);
                            _notify();
                          }
                        },
                      ),
                    ),
                  ],
                  if (isRacquet) ...[
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        value: _discipline,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Discipline',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Singles', child: Text('Singles (1v1)')),
                          DropdownMenuItem(value: 'Doubles', child: Text('Doubles (2v2)')),
                          DropdownMenuItem(value: 'Mixed', child: Text('Mixed Doubles')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _discipline = v);
                            _notify();
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.helper,
    required this.value,
    required this.onPick,
  });

  final String label;
  final String helper;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 3),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          value == null ? 'Not set' : DateFormat('d MMMM yyyy').format(value!),
        ),
      ),
    );
  }
}
