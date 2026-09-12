import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/competition.dart';
import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_context_banner.dart';
import '../../shared/offline_fee_notice.dart';
import '../../shared/ui_kit.dart';

/// Ten people turned up for badminton. Make it a tournament, now.
///
/// ## The gap this fills
///
/// [QuickMatchScreen] collapsed "create event → open entries → register →
/// close entries → generate draw" into one screen for a SINGLE match. It has
/// no answer for the commonest surplus in club sport: more people than one
/// match seats. Ten for badminton is not one match and it is not five
/// unrelated ones — it is a bracket, and until now producing one meant the
/// six-screen tournament wizard with a registration window nobody needs when
/// everybody is already standing on the court.
///
/// So this is the same collapse applied to a draw: the field is whoever said
/// they were In, the format is one of two, and the button makes the whole
/// thing — competition, entrants and fixtures — and drops the organizer on
/// the fixture list ready to score.
///
/// ## What it reuses and why that matters
///
/// Nothing here generates a bracket. `CompetitionRepository.generateDraw` is
/// the draw engine for every event in the product, seeding and byes and
/// double-elimination transfers included, and a second "quick" implementation
/// would be a second set of bracket bugs. This screen's whole job is to
/// assemble the three arguments that engine already takes.
class QuickTournamentScreen extends ConsumerStatefulWidget {
  const QuickTournamentScreen({
    super.key,
    required this.orgId,
    this.initialName,
    this.initialSportId,
    this.initialVenue,
    this.playerUids = const [],
  });

  final String orgId;
  final String? initialName;
  final String? initialSportId;
  final String? initialVenue;

  /// The confirmed roster from the availability call that sent us here.
  final List<String> playerUids;

  @override
  ConsumerState<QuickTournamentScreen> createState() =>
      _QuickTournamentScreenState();
}

class _QuickTournamentScreenState
    extends ConsumerState<QuickTournamentScreen> {
  late final SportSpec _sport =
      SportCatalog.byId(widget.initialSportId ?? 'badminton');

  /// Knockout or round robin, and nothing else.
  ///
  /// The full [CompetitionFormat] list includes Swiss, double elimination and
  /// groups-then-knockout, all of which are right for a real tournament and
  /// none of which a club deciding what to do in the next four minutes should
  /// be reading about. The two here answer the only question that matters at
  /// this point: does everybody play everybody, or does losing send you home.
  CompetitionFormat _format = CompetitionFormat.knockout;

  late final _name = TextEditingController(
    text: widget.initialName ?? '${_sport.name} — club tournament',
  );
  late final _venue = TextEditingController(text: widget.initialVenue ?? '');

  /// Blank means free — see `FeeSettlement`.
  final _entryFee = TextEditingController();

  /// Who is excluded. Everybody plays unless the organizer says otherwise —
  /// they are all here because they said they were free.
  final Set<String> _dropped = {};

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    _entryFee.dispose();
    super.dispose();
  }

  List<String> get _playing => [
        for (final uid in widget.playerUids)
          if (!_dropped.contains(uid)) uid,
      ];

  /// The declared fee in whole rupees, floored at zero. Unparseable text
  /// reads as free — see `_CategoryDraft.entryFeeRupees` in
  /// `create_season_screen.dart` for why that direction is deliberate.
  int get _entryFeeRupees {
    final n = int.tryParse(_entryFee.text.trim());
    return (n == null || n < 0) ? 0 : n;
  }

  /// How many matches the chosen format will produce, so the organizer sees
  /// the size of what they are about to commit the afternoon to.
  ///
  /// A round robin of ten is forty-five matches, which nobody is going to
  /// play, and the honest place to learn that is before the draw rather than
  /// after it.
  int get _matchCount {
    final n = _playing.length;
    if (n < 2) return 0;
    return switch (_format) {
      CompetitionFormat.roundRobin => n * (n - 1) ~/ 2,
      _ => n - 1,
    };
  }

  Future<void> _create() async {
    final uid = ref.read(currentUidProvider);
    final playing = _playing;
    if (uid == null) return;
    if (playing.length < 3) {
      showError(
        context,
        'A tournament needs at least three players. With two, start a single '
        'match instead.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final members =
          ref.read(orgMembersProvider(widget.orgId)).valueOrNull ?? const [];
      final names = {for (final m in members) m.uid: m.displayName};
      final repo = ref.read(competitionRepositoryProvider);

      final competition = Competition(
        id: '',
        orgId: widget.orgId,
        name: _name.text.trim().isEmpty
            ? '${_sport.name} — club tournament'
            : _name.text.trim(),
        sportId: _sport.id,
        sportName: _sport.name,
        archetype: _sport.archetype,
        // Individuals, always. A mini-tournament out of an availability call
        // is a pool of people, not a set of pre-formed clubs, and the team
        // entry modes all assume somebody registered a squad.
        entrantType: EntrantType.individual,
        format: _format,
        // Created closed. There is no registration window: the field is the
        // people who already said yes, and an event sitting in
        // `registrationOpen` would invite the rest of the club to a draw that
        // is about to be generated without them.
        status: CompetitionStatus.registrationClosed,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: _sport.pluginKey,
        teamEntryMode: TeamEntryMode.individual,
        venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        startDate: DateTime.now(),
        // Seeded from ratings, so the two strongest players cannot meet in
        // round one. The draw engine already knows how; it only has to be
        // told that this is wanted.
        drawConfig: const DrawConfig(seedFromRatings: true),
        entryFeeRupees: _entryFeeRupees,
      );

      final compId = await repo.createCompetition(competition);

      await repo.seedEntrants(
        orgId: widget.orgId,
        compId: compId,
        entrants: [
          for (final playerUid in playing)
            Entrant(
              // The uid IS the entrant id for an individual, which is what
              // makes the fixture, the rating and the career profile all point
              // at the same person without a lookup table.
              id: playerUid,
              displayName: names[playerUid] ?? 'Member',
              entrantType: EntrantType.individual,
              uid: playerUid,
            ),
        ],
      );

      final made = await repo.generateDraw(
        competition: competition.copyWith(id: compId),
        entrants: [
          for (final playerUid in playing)
            Entrant(
              id: playerUid,
              displayName: names[playerUid] ?? 'Member',
              entrantType: EntrantType.individual,
              uid: playerUid,
            ),
        ],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${made.written} matches created.')),
      );
      context.go(Routes.competition(widget.orgId, compId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members =
        ref.watch(orgMembersProvider(widget.orgId)).valueOrNull ?? const [];
    final names = {for (final m in members) m.uid: m.displayName};

    return AppScaffold(
      orgId: widget.orgId,
      title: 'Mini-tournament',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          ClubContextBanner(orgId: widget.orgId),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _venue,
            decoration: const InputDecoration(
              labelText: 'Where',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // Small, but it earns its place: "₹50 each for the court" is how
          // a very large share of club games in India actually work, and an
          // organizer who cannot say so here has to say it in a WhatsApp
          // group the event does not know about.
          TextField(
            controller: _entryFee,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Entry fee per player',
              hintText: 'Free',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const OfflineFeeNotice(message: FeeSettlement.organiserHelper),
          const SizedBox(height: 18),
          const _Heading('Format'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final format in const [
                CompetitionFormat.knockout,
                CompetitionFormat.roundRobin,
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FormatTile(
                      label: format.label,
                      hint: format == CompetitionFormat.knockout
                          ? 'Lose and you are out'
                          : 'Everybody plays everybody',
                      selected: _format == format,
                      onTap: () => setState(() => _format = format),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _matchCount == 0
                ? 'Not enough players yet.'
                : '${_playing.length} players · $_matchCount '
                    'match${_matchCount == 1 ? '' : 'es'}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Ps.muted,
            ),
          ),
          const SizedBox(height: 18),
          const _Heading('Who is playing'),
          const SizedBox(height: 4),
          const Text(
            'Everyone who said they were In. Tap to leave somebody out.',
            style: TextStyle(fontSize: 12, color: Ps.faint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final uid in widget.playerUids)
                FilterChip(
                  label: Text(names[uid] ?? 'Member'),
                  selected: !_dropped.contains(uid),
                  onSelected: (keep) => setState(() {
                    if (keep) {
                      _dropped.remove(uid);
                    } else {
                      _dropped.add(uid);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.emoji_events_outlined),
            label: Text(_busy ? 'Making the draw…' : 'Create and draw'),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Ps.faint,
        ),
      );
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Ps.primary.withValues(alpha: 0.1) : Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            border: Border.all(
              color: selected ? Ps.primary : Ps.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Ps.primary : Ps.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: const TextStyle(fontSize: 11.5, color: Ps.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
