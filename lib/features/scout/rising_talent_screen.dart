import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/gov/age_group.dart';
import '../../domain/scout/talent_board.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

const _sports = [
  ('cricket', 'Cricket'),
  ('football', 'Football'),
  ('kabaddi', 'Kabaddi'),
  ('basketball', 'Basketball'),
  ('badminton', 'Badminton'),
  ('hockey', 'Hockey'),
  ('volleyball', 'Volleyball'),
  ('tennis', 'Tennis'),
  ('table_tennis', 'Table Tennis'),
  ('athletics', 'Athletics'),
  ('kho_kho', 'Kho-Kho'),
];

/// Rising Talent — the discovery half of §6, as opposed to the search half in
/// `ScoutSearchScreen`.
///
/// Search asks "who is good at kabaddi in Nalgonda", and answers with the
/// players everybody already knows. This screen asks "who is *getting* good",
/// which is the question that finds the fifteen-year-old nobody has heard of
/// — and it is the question §7's sponsorship features need answered before
/// they have anyone to sponsor.
///
/// ## Why the filters write a document id rather than a query
///
/// Every control here narrows a `TalentBoardKey`, and the key is a document
/// id. Changing the sport or the age band swaps which single document is
/// being watched; there is no query, no index, and no client-side filtering
/// of somebody else's data. See `TalentBoard` for why the whole feature is
/// built that way.
class RisingTalentScreen extends ConsumerStatefulWidget {
  const RisingTalentScreen({super.key});

  @override
  ConsumerState<RisingTalentScreen> createState() => _RisingTalentScreenState();
}

class _RisingTalentScreenState extends ConsumerState<RisingTalentScreen> {
  final _stateController = TextEditingController();
  final _districtController = TextEditingController();

  @override
  void dispose() {
    _stateController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  void _update(TalentBoardKey Function(TalentBoardKey) change) {
    final notifier = ref.read(talentBoardKeyProvider.notifier);
    notifier.state = change(notifier.state);
  }

  void _applyPlace() {
    final state = TalentBoardKey.slug(_stateController.text);
    // A district without a state has no board — see `TalentBoardKey.isCoherent`
    // — so clearing the state clears the district with it rather than leaving
    // a combination that would silently show nothing.
    final district =
        state == kBoardAny ? kBoardAny : TalentBoardKey.slug(_districtController.text);
    if (state == kBoardAny) _districtController.clear();
    _update((k) => TalentBoardKey(
          sportId: k.sportId,
          audience: k.audience,
          ageGroup: k.ageGroup,
          state: state,
          district: district,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(talentBoardKeyProvider);
    final board = ref.watch(talentBoardProvider);
    final isScout = ref.watch(isScoutProvider).valueOrNull ?? false;

    return AppScaffold(
      title: 'Rising talent',
      subtitle: 'Players and clubs improving fastest, last 90 days',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SportChips(
                  selected: key.sportId,
                  onSelected: (id) => _update((k) => TalentBoardKey(
                        sportId: id,
                        audience: k.audience,
                        state: k.state,
                        district: k.district,
                        ageGroup: k.ageGroup,
                      )),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _stateController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'State',
                            hintText: 'All India',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _applyPlace(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _districtController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'District',
                            hintText: 'Statewide',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _applyPlace(),
                        ),
                      ),
                      IconButton(
                        onPressed: _applyPlace,
                        icon: const Icon(Icons.search),
                        tooltip: 'Apply place',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All ages'),
                        selected: key.ageGroup == null,
                        onSelected: (_) => _update((k) => TalentBoardKey(
                              sportId: k.sportId,
                              audience: k.audience,
                              state: k.state,
                              district: k.district,
                            )),
                      ),
                      for (final band in AgeGroup.values)
                        ChoiceChip(
                          label: Text(band.label),
                          selected: key.ageGroup == band,
                          onSelected: (_) => _update((k) => TalentBoardKey(
                                sportId: k.sportId,
                                audience: k.audience,
                                state: k.state,
                                district: k.district,
                                ageGroup: band,
                              )),
                        ),
                    ],
                  ),
                ),
                if (isScout) _ScoutToggle(boardKey: key, onChanged: _update),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                  child: Text(
                    key.scopeLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                board.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Could not load this board: $e'),
                  ),
                  data: (b) => b == null || b.isEmpty
                      ? const EmptyState(
                          icon: Icons.trending_up_outlined,
                          title: 'Nobody is on this board yet',
                          message:
                              'A player needs at least three rated matches in '
                              'the last 90 days, and a rising record, before '
                              'they appear here. Try a wider area, or all ages.',
                        )
                      : _BoardBody(board: b),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SportChips extends StatelessWidget {
  const _SportChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, label) in _sports)
              ChoiceChip(
                label: Text(label),
                selected: selected == id,
                onSelected: (_) => onSelected(id),
              ),
          ],
        ),
      );
}

/// The gate between the two board variants, shown only to accounts that hold
/// the claim — see `isScoutProvider`.
class _ScoutToggle extends StatelessWidget {
  const _ScoutToggle({required this.boardKey, required this.onChanged});

  final TalentBoardKey boardKey;
  final void Function(TalentBoardKey Function(TalentBoardKey)) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isScoutView = boardKey.audience == BoardAudience.scout;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        child: SwitchListTile(
          dense: true,
          value: isScoutView,
          title: const Text('Include under-18 players'),
          subtitle: Text(
            isScoutView
                ? 'Minors are shown because you hold a scout credential. '
                  'Contacting one still requires guardian consent.'
                : 'Public board — adults only.',
            style: theme.textTheme.bodySmall,
          ),
          onChanged: (on) => onChanged((k) => TalentBoardKey(
                sportId: k.sportId,
                state: k.state,
                district: k.district,
                ageGroup: k.ageGroup,
                audience: on ? BoardAudience.scout : BoardAudience.public,
              )),
        ),
      ),
    );
  }
}

class _BoardBody extends StatelessWidget {
  const _BoardBody({required this.board});

  final TalentBoard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (board.players.isNotEmpty) ...[
          _SectionHeading(
            title: 'Rising players',
            trailing: '${board.playerPoolSize} improving',
          ),
          for (final p in board.players) _PlayerRow(entry: p),
        ],
        if (board.teams.isNotEmpty) ...[
          _SectionHeading(
            title: 'Rising clubs',
            trailing: '${board.teamPoolSize} in form',
          ),
          for (final t in board.teams) _TeamRow(entry: t),
        ],
        if (board.computedAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Updated ${_ago(board.computedAt!)} · '
              '${board.windowDays}-day window',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
      ],
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(
            trailing,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.entry});

  final RisingPlayerEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: _RankAvatar(
          rank: entry.rank,
          name: entry.displayName,
          imageUrl: entry.photoUrl,
          seed: entry.uid,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entry.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (entry.provisional) ...[
              const SizedBox(width: 6),
              // Disclosed rather than hidden: a climb built on an unsettled
              // rating is still worth surfacing, but a scout should be able
              // to see which of two rows is the safer bet.
              Tooltip(
                message: 'Rating still settling — fewer results behind it',
                child: Icon(Icons.help_outline,
                    size: 15, color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
        subtitle: Text(
          [
            entry.ageGroupLabel,
            if (entry.districtLabel != null) entry.districtLabel!,
            if (entry.clubName != null) entry.clubName!,
            '${entry.matchesInWindow} matches',
          ].join(' · '),
        ),
        trailing: _DeltaBadge(
          delta: entry.ratingDelta,
          truncated: entry.truncatedSpan,
        ),
        onTap: () => context.push(Routes.profile(entry.uid)),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.entry});

  final RisingTeamEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winPct = (entry.recentWinRate * 100).round();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: _RankAvatar(
          rank: entry.rank,
          name: entry.orgName,
          imageUrl: entry.logoUrl,
          seed: entry.orgId,
          isOrg: true,
        ),
        title: Text(entry.orgName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            if (entry.districtLabel != null) entry.districtLabel!,
            '${entry.winsInWindow}/${entry.matchesInWindow} won ($winPct%)',
            if (entry.tournamentWins > 0)
              '${entry.tournamentWins} title${entry.tournamentWins == 1 ? '' : 's'}',
          ].join(' · '),
        ),
        trailing: entry.momentum > 0.01
            ? Chip(
                visualDensity: VisualDensity.compact,
                label: Text('+${(entry.momentum * 100).round()}%'),
                backgroundColor: theme.colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
        onTap: () => context.push(Routes.org(entry.orgId)),
      ),
    );
  }
}

class _RankAvatar extends StatelessWidget {
  const _RankAvatar({
    required this.rank,
    required this.name,
    this.imageUrl,
    this.seed,
    this.isOrg = false,
  });

  final int rank;
  final String name;
  final String? imageUrl;
  final String? seed;
  final bool isOrg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(width: 6),
          // A club row gets the squircle and a player row gets the circle.
          // Both used to get the same round mark with a generic person glyph
          // in it, so a club with no logo was drawn as a faceless human.
          if (isOrg)
            PsCrest(name: name, logoUrl: imageUrl, seed: seed, size: 30)
          else
            PsAvatar(name: name, photoUrl: imageUrl, seed: seed, size: 30),
        ],
      ),
    );
  }
}

/// The number a row is actually ranked on, in the units a person reads.
///
/// Shows the raw rating gain rather than the shrunk composite score: "+64" is
/// a fact about the player, while the score is an internal ordering device
/// that would invite the reader to compare two numbers whose difference they
/// have no way to interpret.
class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta, required this.truncated});

  final double delta;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '+${delta.round()}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          truncated ? 'since first result' : 'rating, 90d',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}
