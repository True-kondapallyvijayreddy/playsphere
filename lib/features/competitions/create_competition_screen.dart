import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/ground_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../grounds/ground_booking_flow.dart';

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
  final _capacity = TextEditingController();
  final _preselect = TextEditingController();
  final _fee = TextEditingController();
  final _teamSize = TextEditingController();
  final _rules = TextEditingController();

  SportSpec _sport = SportCatalog.byId('badminton');
  late CompetitionCategory _category = CompetitionCategory.presets().first;
  CompetitionFormat _format = CompetitionFormat.roundRobin;
  DateTime? _startDate;
  TimeOfDay? _startTime;
  ParticipationModel _participation = ParticipationModel.open;
  bool _waitlist = true;
  bool _openToNonMembers = false;
  bool _busy = false;

  /// Whether the organizer wants PlaySphere to find them a ground.
  ///
  /// Off by default, deliberately — see the section comment in [build].
  bool _wantsGroundBooking = false;

  /// The slot actually held, once one has been. Null right up until the
  /// booking transaction has committed, so this being non-null is proof the
  /// ground is genuinely reserved rather than merely chosen.
  BookedGround? _booked;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    _capacity.dispose();
    _preselect.dispose();
    _fee.dispose();
    _teamSize.dispose();
    _rules.dispose();
    super.dispose();
  }

  /// The date and the time of day as one moment.
  ///
  /// Kept separate in the form because two pickers are far easier to use than
  /// one combined control, but stored as a single instant: "Sunday" and
  /// "6am" are not two facts about a match, and a start time that lives only
  /// in the event description is a start time no reminder can ever use.
  DateTime? get _startsAt {
    final date = _startDate;
    if (date == null) return null;
    final time = _startTime;
    if (time == null) return date;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int? get _capacityValue => int.tryParse(_capacity.text.trim());

  /// Reserved slots only mean anything for a hybrid event, and can never
  /// exceed the capacity they are carved out of.
  int get _preselectValue {
    if (_participation != ParticipationModel.hybrid) return 0;
    final wanted = int.tryParse(_preselect.text.trim()) ?? 0;
    final cap = _capacityValue;
    if (wanted < 0) return 0;
    if (cap != null && wanted > cap) return cap;
    return wanted;
  }

  // Deliberately no `singleMatch` in `SportSpec.competitionFormats` — a
  // one-off match is its own event type now, chosen a screen earlier
  // (Feature #8), which is a better place to ask: the whole lower half of
  // THIS form — participation model, capacity, waitlist — exists to
  // assemble a field, and a single match has both sides named on the spot.
  // Offering it as a "format" meant filling in a page of registration
  // settings that were then discarded.
  List<CompetitionFormat> get _formatsForSport => _sport.competitionFormats;

  /// Opens the search-and-book sheet, seeded with what the form already
  /// knows.
  ///
  /// The sport, the club's city and the event's start date are all sitting
  /// right here, and asking for them a second time inside the sheet is how a
  /// booking flow gets abandoned halfway.
  Future<void> _openGroundSearch() async {
    final org = ref.read(organizationProvider(widget.orgId)).valueOrNull;

    final result = await showGroundBookingSheet(
      context,
      sportId: _sport.id,
      initialCity: org?.city,
      initialDate: _startDate,
      orgId: widget.orgId,
    );
    if (result == null || !mounted) return;

    setState(() {
      _booked = result;
      _venue.text = result.venueLabel;
      // The booked day is the day the event is on. Leaving the two able to
      // differ would let an organizer hold Sunday and tell everyone Saturday.
      _startDate = result.booking.startsAt;
      _startTime = TimeOfDay(hour: result.booking.startHour, minute: 0);
    });
  }

  /// Drops the booking from the form. Deliberately does not cancel the slot:
  /// the hour is genuinely held and releasing it is a decision with a
  /// consequence, made on the Grounds screen where the confirmation lives.
  void _clearBooking() {
    _booked = null;
    _venue.clear();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // Unreachable by the dropdown since single match became its own event
    // type (Feature #8) — kept as a guard rather than deleted, because the
    // failure it prevents is silent and permanent: creating the competition
    // here would leave an event with no fixture, which appears in the club's
    // list and can never be played. If a single-sport format list ever grows
    // `singleMatch` back, this still hands over to the quick-match screen,
    // which writes the competition and its one fixture together.
    if (_format.isSingleMatch) {
      context.push(
        Routes.quickMatch(
          widget.orgId,
          name: _name.text.trim(),
          sportId: _sport.id,
          venue: _venue.text.trim(),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final compId = await ref
          .read(competitionRepositoryProvider)
          .createCompetition(
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
              startDate: _startsAt,
              maxEntrants: _capacityValue,
              participationModel: _participation,
              preselectedSlots: _preselectValue,
              waitlistEnabled: _waitlist,
              openToNonMembers: _openToNonMembers,
              entryFeeRupees: int.tryParse(_fee.text.trim()) ?? 0,
              teamSize: int.tryParse(_teamSize.text.trim()),
              rulesNote: _rules.text.trim().isEmpty ? null : _rules.text.trim(),
              createdBy: uid,
            ),
          );
      if (mounted) {
        // Replace rather than push: the event now exists, and a back press
        // from it should return to the club, not to a creation form that
        // would make a second copy if it were submitted again.
        context.pushReplacement(Routes.competition(widget.orgId, compId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _participationHint(ParticipationModel model) => switch (model) {
        ParticipationModel.open =>
          'Whoever registers first is in, up to the limit. Nothing for you '
              'to approve.',
        ParticipationModel.hybrid =>
          'You name some of the side; the rest of the slots fill first-come.',
        ParticipationModel.approval =>
          'Every registration waits for you to confirm it. Use for trials '
              'and selections.',
      };

  /// Spells the split back to the organizer in the numbers they typed —
  /// "8 picked by you + 5 open" — because "preselected slots" on its own is
  /// the kind of phrase that gets filled in wrong and discovered on match day.
  String _hybridSplitHint() {
    final cap = _capacityValue;
    if (cap == null) return 'Set a registration limit to split the field';
    final picked = _preselectValue;
    final open = cap - picked;
    return '$picked picked by you + $open open to registration = $cap';
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
                      final match = presets.firstWhere((c) => c.label == label);
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

                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime:
                            _startTime ?? const TimeOfDay(hour: 6, minute: 30),
                      );
                      if (picked != null) setState(() => _startTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start time',
                        helperText: 'What players are told to report for',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _startTime == null
                            ? 'Not set'
                            : _startTime!.format(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---- Where it is played ----------------------------
                  //
                  // Asked as a question with two equally valid answers, not
                  // as a booking funnel with a way out. Most clubs in India
                  // play on a ground they already have — a school field, a
                  // panchayat maidan, the street outside — and a form that
                  // treats "we have somewhere" as the awkward path is a form
                  // written for the cities. So the default stays off, and
                  // typing a place is a complete answer.
                  const _SectionHeading(
                    'Where are you playing?',
                    subtitle: 'Book a ground through PlaySphere, or just say '
                        'where',
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _wantsGroundBooking,
                    onChanged: (v) => setState(() {
                      _wantsGroundBooking = v;
                      if (!v) _clearBooking();
                    }),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Book a ground'),
                    subtitle: const Text(
                      'Search grounds near you and hold an hour. Leave this '
                      'off if you already have somewhere to play.',
                    ),
                  ),

                  if (_wantsGroundBooking) ...[
                    const SizedBox(height: 8),
                    if (_booked == null)
                      OutlinedButton.icon(
                        onPressed: _openGroundSearch,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.search),
                        label: const Text('Find an available ground'),
                      )
                    else
                      _BookedGroundCard(
                        booked: _booked!,
                        onChange: _openGroundSearch,
                        onRemove: () => setState(_clearBooking),
                      ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _venue,
                    // A booked ground fills this in and locks it. The venue
                    // line and the booking must not be able to disagree —
                    // a team sheet naming one ground while the slot is held
                    // at another is worse than either alone.
                    readOnly: _booked != null,
                    decoration: InputDecoration(
                      labelText: _booked == null
                          ? 'Venue / ground (optional)'
                          : 'Venue (from your booking)',
                      hintText: 'e.g. Main court',
                      border: const OutlineInputBorder(),
                      suffixIcon: _booked == null
                          ? null
                          : const Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Registration, capacity and waitlists describe how a field
                  // gets assembled. A single match has both sides named on the
                  // next screen, so none of it applies and showing it would be
                  // asking questions whose answers get thrown away.
                  if (_format.isSingleMatch) ...[
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'You will pick the two sides on the next screen and '
                          'the match starts immediately — no registration, no '
                          'draw. It still counts towards everyone\'s record '
                          'like any other match.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.sports_score),
                      label: const Text('Pick the sides'),
                    ),
                  ] else ...[
                    // ---- Who plays -------------------------------------
                    //
                    // The participation model is the single most consequential
                    // choice on this screen, because it decides what tapping
                    // Register does to the person who taps it. It is fixed at
                    // creation — see `Competition.toUpdate` — so it is asked
                    // plainly, with the consequence spelled out, rather than
                    // hidden behind an "advanced" disclosure.
                    const _SectionHeading(
                      'Who plays',
                      subtitle: 'How this event decides its field',
                    ),
                    const SizedBox(height: 12),

                    for (final model in ParticipationModel.values)
                      RadioListTile<ParticipationModel>(
                        value: model,
                        groupValue: _participation,
                        onChanged: (m) => setState(
                            () => _participation = m ?? _participation),
                        contentPadding: EdgeInsets.zero,
                        title: Text(model.label),
                        subtitle: Text(_participationHint(model)),
                      ),
                    const SizedBox(height: 12),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _capacity,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Registration limit',
                              hintText: 'e.g. 13',
                              helperText: 'Blank = no limit',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              final n = int.tryParse(t);
                              if (n == null || n < 1) return 'Enter a number';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _teamSize,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Team size',
                              hintText: 'e.g. 11',
                              helperText: 'Players a side (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_participation == ParticipationModel.hybrid) ...[
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _preselect,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Slots you pick yourself',
                          helperText: _hybridSplitHint(),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (_participation != ParticipationModel.hybrid) {
                            return null;
                          }
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n < 1) {
                            return 'How many players will you name?';
                          }
                          final cap = _capacityValue;
                          if (cap != null && n > cap) {
                            return 'Cannot reserve more than the $cap limit';
                          }
                          if (cap == null) {
                            return 'Set a registration limit first';
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _waitlist,
                      onChanged: (v) => setState(() => _waitlist = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Keep a waitlist'),
                      subtitle: const Text(
                        'People who register after the field is full join a '
                        'queue, and the first reserve is moved in '
                        'automatically if someone drops out',
                      ),
                    ),
                    SwitchListTile(
                      value: _openToNonMembers,
                      onChanged: (v) => setState(() => _openToNonMembers = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Open to people outside the club'),
                      subtitle: const Text(
                        'Off means only members of this club can register',
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _fee,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Entry fee (₹)',
                        hintText: '0',
                        helperText: 'Leave at 0 for a free event',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _rules,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Rules & guidelines (optional)',
                        hintText:
                            'e.g. Leather ball. Report by 6am. Whites only.',
                        helperText: 'Shown before anyone registers',
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
                      _participation == ParticipationModel.approval
                          ? 'The event starts as a draft. You open entries, '
                              'approve players, then generate the draw.'
                          : 'The event starts as a draft. Once you open '
                              'entries, players register themselves and the '
                              'field fills on its own.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slot that has been held, shown in the event form.
///
/// States the ground, the day, the hours and the price back in full. A
/// booking is a commitment of somebody's money and somebody else's evening,
/// and the confirmation that it happened should not be a tick.
class _BookedGroundCard extends StatelessWidget {
  const _BookedGroundCard({
    required this.booked,
    required this.onChange,
    required this.onRemove,
  });

  final BookedGround booked;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = booked.booking;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_available, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ground booked',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    booked.ground.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${DateFormat('EEE d MMM').format(b.startsAt)} · '
                    '${groundHourLabel(b.startHour)}–'
                    '${groundHourLabel(b.endHour)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    b.amountPaise == 0
                        ? 'Free'
                        : '${Pricing.formatPaise(b.amountPaise)} for '
                            '${b.hours} hour${b.hours == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton(
                        onPressed: onChange,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Book a different slot'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onRemove,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Remove from event'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null)
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
