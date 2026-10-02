import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/tournament.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/models/venue.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/discovery_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../domain/tournament/invitation_letter.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_id_chip.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import '../sports/sport_hub_providers.dart';
import '../tournaments/widgets/season_organizer_gate.dart';

/// Inviting other clubs to a season or a tournament — a page of its own.
///
/// ## Why a page and not the sheet it replaces
///
/// Inviting was a bottom sheet with a name search and a one-line note. An
/// organizer asking every club in Rangareddy to a sports week needs three
/// things that sheet could not hold: a way to find clubs by WHERE they are
/// and WHAT they play, not only by a name they already know; the invitation
/// itself, written out properly, so the clubs receiving it know what they are
/// being asked to; and the registration link, so saying yes is one tap.
///
/// ## What the page is made of
///
///  * **The letter.** Composed from the season — host, sports, dates, place —
///    by [InvitationLetter], and editable. It stays in step with the facts
///    until the organizer types into it, and "Reset" brings the composed one
///    back.
///  * **The directory.** Every public club, narrowed by name or Club ID, by
///    area, and by sport, with "select all" for the area case.
///  * **Send.** One invitation per club, each carrying the letter. The same
///    letter can leave the app through the share sheet, with the link
///    attached, for the clubs that are not on PlaySphere yet.
class InviteClubsScreen extends ConsumerWidget {
  const InviteClubsScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final kind = ref.watch(tournamentProvider(key)).valueOrNull?.kind ??
        SeasonKind.season;
    return AppScaffold(
      orgId: orgId,
      title: 'Invite clubs',
      subtitle: 'To your ${kind.noun}',
      body: SeasonOrganizerGate(
        orgId: orgId,
        tournamentId: tournamentId,
        what: 'who is invited',
        child: AsyncView<Tournament?>(
          value: ref.watch(tournamentProvider(key)),
          builder: (t) => t == null
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'This season no longer exists',
                )
              : _Composer(tournament: t),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _letter = TextEditingController();
  final _place = TextEditingController();
  final _search = TextEditingController();
  final _area = TextEditingController();

  /// Clubs ticked, by id, with the name to write onto the invitation.
  final _picked = <String, String>{};

  String? _sportId;

  /// Whether the organizer has typed into the letter. Until they have, the
  /// letter follows the season's facts as they load; afterwards it is theirs
  /// and nothing overwrites it.
  bool _letterEdited = false;
  bool _placeEdited = false;
  bool _busy = false;

  Tournament get t => widget.tournament;

  @override
  void dispose() {
    _letter.dispose();
    _place.dispose();
    _search.dispose();
    _area.dispose();
    super.dispose();
  }

  // --- The facts the letter is composed from ------------------------------

  List<Competition> get _events => [
        for (final c in ref
                .watch(tournamentEventsProvider(
                    (orgId: t.orgId, tournamentId: t.id)))
                .valueOrNull ??
            const <Competition>[])
          if (c.status != CompetitionStatus.cancelled) c,
      ];

  List<String> _sportNames(List<Competition> events) {
    final seen = <String>{};
    return [
      for (final e in events)
        if (e.sportName.isNotEmpty && seen.add(e.sportId)) e.sportName,
    ];
  }

  /// Where the season is played, in the words a club reading the invitation
  /// would use: the venue line the organizer wrote on the events, else the
  /// grounds' own names and towns, else the host club's town.
  /// Fitted to [TournamentInvite.maxPlaceLength]. The pieces are a venue
  /// label and ground names somebody else typed, and a prefill the field
  /// could not hold would refuse the send.
  String _defaultPlace(
    List<Competition> events,
    List<Venue> venues,
    Organization? host,
  ) =>
      TournamentInvite.fit(
        _rawPlace(events, venues, host),
        TournamentInvite.maxPlaceLength,
      ) ??
      '';

  String _rawPlace(
    List<Competition> events,
    List<Venue> venues,
    Organization? host,
  ) {
    for (final e in events) {
      final label = e.venue?.trim() ?? '';
      if (label.isNotEmpty) return label;
    }
    final grounds = [
      for (final v in venues)
        if (t.venueIds.contains(v.id)) v,
    ];
    if (grounds.isNotEmpty) {
      final names = grounds.map((v) => v.name).take(2).join(', ');
      final town = grounds
          .map((v) => (v.city ?? v.district ?? '').trim())
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      return town.isEmpty || names.contains(town) ? names : '$names, $town';
    }
    final hostTown = [
      host?.geo.village ?? host?.geo.mandal,
      host?.city ?? host?.geo.district ?? host?.district,
    ].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
    return hostTown.toSet().join(', ');
  }

  /// The letter as composed, fitted to what an invitation may carry. A long
  /// season name and thirty sports can compose past it, and the field's own
  /// limit does not stop text the app writes into it.
  String _composed({
    required Organization? host,
    required List<Competition> events,
  }) =>
      TournamentInvite.fit(
        _composedRaw(host: host, events: events),
        TournamentInvite.maxMessageLength,
      ) ??
      '';

  String _composedRaw({
    required Organization? host,
    required List<Competition> events,
  }) =>
      InvitationLetter.compose(
        hostClubName: host?.name ?? '',
        seasonName: t.name,
        kind: t.kind,
        sports: _sportNames(events),
        startDate: t.startDate,
        endDate: t.endDate,
        place: _place.text,
      );

  String get _registrationUrl => Routes.seasonRegisterUrl(t.orgId, t.id);

  // --- Actions ------------------------------------------------------------

  Future<void> _send({required Organization? host}) async {
    final uid = ref.read(authUidProvider);
    if (uid == null || _picked.isEmpty || _busy) return;
    final events = _events;
    setState(() => _busy = true);
    try {
      await ref.read(tournamentRepositoryProvider).inviteClubs(
            tournament: t,
            hostOrgName: host?.name ?? 'A club',
            clubs: [
              for (final e in _picked.entries) (orgId: e.key, name: e.value),
            ],
            invitedByUid: uid,
            message: _letter.text,
            sportNames: _sportNames(events),
            place: _place.text,
          );
      if (!mounted) return;
      final n = _picked.length;
      setState(() => _picked.clear());
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              n == 1 ? 'Invitation sent.' : 'Invitations sent to $n clubs.',
            ),
          ),
        );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareOutside() async {
    final text = InvitationLetter.shareText(
      letter: _letter.text,
      registrationUrl: _registrationUrl,
    );
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'Invitation: ${t.name}'),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation copied — paste it anywhere.')),
        );
      }
    }
  }

  Future<void> _withdraw(TournamentInvite invite) async {
    try {
      await ref
          .read(tournamentRepositoryProvider)
          .respondToInvite(inviteId: invite.id, status: 'withdrawn');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(organizationProvider(t.orgId)).valueOrNull;
    final events = _events;
    final venues = ref.watch(venuesProvider(t.orgId)).valueOrNull ?? const [];

    // Follow the facts until the organizer takes the pen. After the frame,
    // not during it: writing a controller notifies its text field, and a
    // widget may not be marked dirty while the tree is being built.
    if (!_placeEdited || !_letterEdited) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_placeEdited) {
          final place = _defaultPlace(events, venues, host);
          if (_place.text != place) _place.text = place;
        }
        if (!_letterEdited) {
          final letter = _composed(host: host, events: events);
          if (_letter.text != letter) _letter.text = letter;
        }
      });
    }

    final invitesAsync = ref.watch(
        tournamentInvitesProvider((orgId: t.orgId, tournamentId: t.id)));
    final invites = invitesAsync.valueOrNull ?? const <TournamentInvite>[];

    final letterPane = _LetterPane(
      tournament: t,
      host: host,
      events: events,
      letter: _letter,
      place: _place,
      registrationUrl: _registrationUrl,
      letterEdited: _letterEdited,
      onLetterEdited: () => setState(() => _letterEdited = true),
      onPlaceEdited: () => setState(() {
        _placeEdited = true;
        if (!_letterEdited) {
          _letter.text = _composed(host: host, events: events);
        }
      }),
      onReset: () => setState(() {
        _letterEdited = false;
        _letter.text = _composed(host: host, events: events);
      }),
      onShareOutside: _shareOutside,
    );

    final directory = _DirectoryPane(
      hostOrgId: t.orgId,
      seasonSports: {for (final e in events) e.sportId: e.sportName},
      invites: invites,
      invitesAsync: invitesAsync,
      search: _search,
      area: _area,
      sportId: _sportId,
      picked: _picked,
      hostArea: host?.geo.district ?? host?.district ?? host?.city,
      onSport: (id) => setState(() => _sportId = id),
      onChanged: () => setState(() {}),
      onWithdraw: _withdraw,
    );

    final sendBar = _SendBar(
      count: _picked.length,
      busy: _busy,
      onSend: () => _send(host: host),
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 980) {
          return Column(
            children: [
              Expanded(
                child: ContentBounds(
                  maxWidth: 1180,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                          children: [letterPane],
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
                          children: [directory],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              sendBar,
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  ContentBounds(
                    maxWidth: 720,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        letterPane,
                        const SizedBox(height: 20),
                        directory,
                      ],
                    ),
                  ),
                ],
              ),
            ),
            sendBar,
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The letter
// ---------------------------------------------------------------------------

class _LetterPane extends StatelessWidget {
  const _LetterPane({
    required this.tournament,
    required this.host,
    required this.events,
    required this.letter,
    required this.place,
    required this.registrationUrl,
    required this.letterEdited,
    required this.onLetterEdited,
    required this.onPlaceEdited,
    required this.onReset,
    required this.onShareOutside,
  });

  final Tournament tournament;
  final Organization? host;
  final List<Competition> events;
  final TextEditingController letter;
  final TextEditingController place;
  final String registrationUrl;
  final bool letterEdited;
  final VoidCallback onLetterEdited;
  final VoidCallback onPlaceEdited;
  final VoidCallback onReset;
  final VoidCallback onShareOutside;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final noEntriesYet = events.isNotEmpty &&
        events.every((e) => e.status == CompetitionStatus.draft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepLabel(number: 1, text: 'Your invitation'),
        const SizedBox(height: 10),
        // A private host is the one case where sending works and accepting
        // does not: the invited club cannot read a private club's season,
        // so the registration link would open onto nothing.
        if (host != null && !host!.isPublic)
          const _Warning(
            icon: Icons.lock_outline,
            text: 'Your club is private, so clubs you invite cannot open the '
                'registration page. Make the club public in its settings '
                'before inviting.',
          ),
        if (noEntriesYet)
          _Warning(
            icon: Icons.how_to_reg_outlined,
            text: 'Entries are not open yet. Clubs can accept now and will be '
                'able to register as soon as you open entries on the '
                '${t.kind.noun} page.',
          ),
        PsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PsCrest(
                    name: host?.name ?? t.name,
                    logoUrl: host?.logoUrl,
                    seed: t.orgId,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Ps.ink,
                          ),
                        ),
                        Text(
                          '${t.kind.label} · hosted by ${host?.name ?? '…'}',
                          style:
                              const TextStyle(fontSize: 12, color: Ps.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: place,
                onChanged: (_) => onPlaceEdited(),
                maxLength: TournamentInvite.maxPlaceLength,
                decoration: const InputDecoration(
                  labelText: 'Where',
                  hintText: 'Adibatla, Hyderabad',
                  prefixIcon: Icon(Icons.place_outlined),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: letter,
                onChanged: (_) => onLetterEdited(),
                minLines: 6,
                maxLines: 14,
                maxLength: TournamentInvite.maxMessageLength,
                style: const TextStyle(fontSize: 13.5, height: 1.45),
                decoration: const InputDecoration(
                  labelText: 'Invitation letter',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.link, size: 16, color: Ps.primary),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'A Register button that opens your registration page is '
                      'attached to every invitation.',
                      style: TextStyle(fontSize: 12, color: Ps.muted),
                    ),
                  ),
                  if (letterEdited)
                    TextButton(
                      onPressed: onReset,
                      child: const Text('Reset'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onShareOutside,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share on WhatsApp & more'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: registrationUrl),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Registration link copied.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy registration link'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The directory
// ---------------------------------------------------------------------------

/// The whole public directory, one bounded page — the same read the club
/// network and Discover use. Not `publicOrgsProvider`, which stops at fifty:
/// an organizer inviting "every club in the district" must not silently miss
/// the fifty-first.
final _inviteDirectoryProvider = StreamProvider.autoDispose<List<Organization>>(
  (ref) => ref.watch(discoveryRepositoryProvider).watchPublicClubs(),
);

class _DirectoryPane extends ConsumerWidget {
  const _DirectoryPane({
    required this.hostOrgId,
    required this.seasonSports,
    required this.invites,
    required this.invitesAsync,
    required this.search,
    required this.area,
    required this.sportId,
    required this.picked,
    required this.hostArea,
    required this.onSport,
    required this.onChanged,
    required this.onWithdraw,
  });

  final String hostOrgId;

  /// sportId → name, for the sports this season runs. Offered first as sport
  /// filters, because "clubs that play what we are running" is the question.
  final Map<String, String> seasonSports;
  final List<TournamentInvite> invites;
  final AsyncValue<List<TournamentInvite>> invitesAsync;
  final TextEditingController search;
  final TextEditingController area;
  final String? sportId;
  final Map<String, String> picked;
  final String? hostArea;
  final ValueChanged<String?> onSport;
  final VoidCallback onChanged;
  final ValueChanged<TournamentInvite> onWithdraw;

  /// How many rows the list draws. A district can hold hundreds of clubs;
  /// "Select all" still covers every match, the list just stops drawing.
  static const _shown = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(_inviteDirectoryProvider);
    final all = orgsAsync.valueOrNull ?? const <Organization>[];
    // Clubs with a live invitation — waiting or coming. A club that declined,
    // or whose invitation the host withdrew, can be asked again.
    final invitedIds = {
      for (final i in invites)
        if (i.isPending || i.isAccepted) i.toOrgId,
    };

    Set<String>? sportOrgIds;
    var sportLoading = false;
    final sport = sportId;
    if (sport != null) {
      // Clubs putting this sport on, read off the events rather than
      // `sportClubsProvider`, which only looks inside the first fifty clubs.
      final events = ref.watch(sportEventsProvider(sport));
      sportLoading = events.isLoading;
      sportOrgIds = {
        for (final c in events.valueOrNull ?? const <Competition>[]) c.orgId,
      };
    }

    // Area and sport through the discovery screen's own filter, so "is this
    // club in Rangareddy" has one answer across the app.
    final placed = ref.watch(discoveryRepositoryProvider).filterClubs(
          all,
          DiscoveryFilters(district: area.text),
          sportOrgIds: sportOrgIds,
        );
    // Name OR Club ID here, because a club secretary is as likely to have
    // been handed "ABCD-1234" on a phone call as the club's name.
    final q = search.text.trim().toLowerCase();
    final qCode = q.replaceAll('-', '');
    final matches = [
      for (final o in placed)
        if (o.id != hostOrgId &&
            !invitedIds.contains(o.id) &&
            (q.isEmpty ||
                o.name.toLowerCase().contains(q) ||
                (qCode.length >= 4 &&
                    o.clubCodeLabel
                        .replaceAll('-', '')
                        .toLowerCase()
                        .contains(qCode))))
          o,
    ];
    final allPicked =
        matches.isNotEmpty && matches.every((o) => picked.containsKey(o.id));

    // Areas worth one tap: the host's own, then the busiest in the directory.
    final areaCounts = <String, int>{};
    for (final o in all) {
      final d = (o.geo.district ?? o.district ?? o.city)?.trim();
      if (d != null && d.isNotEmpty) areaCounts[d] = (areaCounts[d] ?? 0) + 1;
    }
    final areas = <String>[
      if (hostArea != null && hostArea!.trim().isNotEmpty) hostArea!.trim(),
      ...(areaCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => e.key),
    ];
    final quickAreas = <String>[];
    for (final a in areas) {
      if (quickAreas.length >= 6) break;
      if (!quickAreas.any((x) => x.toLowerCase() == a.toLowerCase())) {
        quickAreas.add(a);
      }
    }

    final otherSports = [
      for (final s in SportCatalog.all)
        if (!seasonSports.containsKey(s.id)) s,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepLabel(number: 2, text: 'Choose the clubs'),
        const SizedBox(height: 10),
        PsSearchField(
          hint: 'Club name or Club ID',
          controller: search,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: area,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: 'Area — district, city, mandal or village',
            prefixIcon: const Icon(Icons.place_outlined, size: 20),
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: area.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Any area',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      area.clear();
                      onChanged();
                    },
                  ),
          ),
        ),
        if (quickAreas.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in quickAreas)
                ChoiceChip(
                  label: Text(a),
                  visualDensity: VisualDensity.compact,
                  selected: area.text.trim().toLowerCase() == a.toLowerCase(),
                  onSelected: (on) {
                    area.text = on ? a : '';
                    onChanged();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Any sport'),
              visualDensity: VisualDensity.compact,
              selected: sport == null,
              onSelected: (_) => onSport(null),
            ),
            for (final e in seasonSports.entries)
              ChoiceChip(
                label: Text('${SportCatalog.byId(e.key).icon} ${e.value}'),
                visualDensity: VisualDensity.compact,
                selected: sport == e.key,
                onSelected: (on) => onSport(on ? e.key : null),
              ),
            if (otherSports.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Another sport',
                onSelected: onSport,
                itemBuilder: (_) => [
                  for (final s in otherSports)
                    PopupMenuItem(
                      value: s.id,
                      child: Text('${s.icon}  ${s.name}'),
                    ),
                ],
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    sport != null && !seasonSports.containsKey(sport)
                        ? SportCatalog.byId(sport).name
                        : 'Other sport…',
                  ),
                  avatar: const Icon(Icons.arrow_drop_down, size: 18),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AsyncErrorStrip(value: orgsAsync, what: 'the club directory'),
        AsyncErrorStrip(value: invitesAsync, what: 'the clubs already invited'),

        Row(
          children: [
            Expanded(
              child: Text(
                orgsAsync.isLoading || sportLoading
                    ? 'Looking for clubs…'
                    : '${matches.length} '
                        '${matches.length == 1 ? 'club' : 'clubs'} found',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Ps.muted,
                ),
              ),
            ),
            if (matches.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  if (allPicked) {
                    for (final o in matches) {
                      picked.remove(o.id);
                    }
                  } else {
                    for (final o in matches) {
                      picked[o.id] = o.name;
                    }
                  }
                  onChanged();
                },
                icon: Icon(
                  allPicked ? Icons.deselect : Icons.select_all,
                  size: 18,
                ),
                label: Text(
                  allPicked ? 'Clear these' : 'Select all ${matches.length}',
                ),
              ),
          ],
        ),
        if (matches.isEmpty && !orgsAsync.isLoading && !sportLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              all.isEmpty
                  ? 'No other clubs are listed publicly yet. Share the '
                      'invitation on WhatsApp instead.'
                  : 'No club matches. Try a wider area or any sport.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Ps.muted),
            ),
          )
        else
          PsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final o in matches.take(_shown))
                  CheckboxListTile(
                    value: picked.containsKey(o.id),
                    onChanged: (on) {
                      if (on == true) {
                        picked[o.id] = o.name;
                      } else {
                        picked.remove(o.id);
                      }
                      onChanged();
                    },
                    secondary: PsCrest(
                      name: o.name,
                      logoUrl: o.logoUrl,
                      seed: o.id,
                      size: 36,
                    ),
                    title: Text(
                      o.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    // The club's own id under the name, always. Two clubs may
                    // carry the same name — two "PS Test Academy" rows sat in
                    // this very picker — and a host about to commit to
                    // inviting one of them has nothing else on the row to tell
                    // them apart. See [ClubIdChip].
                    subtitle: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _where(o),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ClubIdChip(org: o, compact: true),
                      ],
                    ),
                    dense: true,
                  ),
                if (matches.length > _shown)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${matches.length - _shown} more not drawn — narrow '
                      'the search, or use Select all to include them.',
                      style: const TextStyle(fontSize: 12, color: Ps.muted),
                    ),
                  ),
              ],
            ),
          ),

        if (invites.isNotEmpty) ...[
          const SizedBox(height: 20),
          _InvitedList(invites: invites, onWithdraw: onWithdraw),
        ],
      ],
    );
  }

  static String _where(Organization o) {
    final parts = <String>[
      o.orgType.label,
      for (final p in [o.geo.village ?? o.geo.mandal, o.city, o.geo.district ?? o.district])
        if (p != null && p.trim().isNotEmpty) p.trim(),
      'ID ${o.clubCodeLabel}',
    ];
    return parts.toSet().join(' · ');
  }
}

/// The clubs already asked, with their answers. Shown rather than hidden,
/// because an organizer who cannot see last week's invitation sends it again.
class _InvitedList extends StatelessWidget {
  const _InvitedList({required this.invites, required this.onWithdraw});

  final List<TournamentInvite> invites;
  final ValueChanged<TournamentInvite> onWithdraw;

  @override
  Widget build(BuildContext context) {
    final coming = invites.where((i) => i.isAccepted).length;
    final waiting = invites.where((i) => i.isPending).length;
    final declined = invites.where((i) => i.isDeclined).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Already invited · $coming coming · $waiting waiting'
          '${declined > 0 ? ' · $declined declined' : ''}',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Ps.muted,
          ),
        ),
        const SizedBox(height: 8),
        PsCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final i in invites)
                ListTile(
                  dense: true,
                  leading: PsCrest(name: i.toOrgName, seed: i.toOrgId, size: 32),
                  title: Text(i.toOrgName),
                  subtitle: Text(switch (i.status) {
                    'accepted' => 'Coming',
                    'declined' => 'Declined',
                    'withdrawn' => 'You withdrew this invitation',
                    _ => 'No reply yet',
                  }),
                  trailing: i.isPending
                      ? TextButton(
                          onPressed: () => onWithdraw(i),
                          child: const Text('Withdraw'),
                        )
                      : Icon(
                          i.isAccepted
                              ? Icons.check_circle
                              : Icons.remove_circle_outline,
                          color: i.isAccepted ? Ps.primary : Ps.faint,
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.count,
    required this.busy,
    required this.onSend,
  });

  final int count;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ps.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: ContentBounds(
            maxWidth: 1180,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    count == 0
                        ? 'Tick the clubs to invite'
                        : '$count ${count == 1 ? 'club' : 'clubs'} selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Ps.ink,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: count == 0 || busy ? null : onSend,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(
                    count == 0
                        ? 'Send invitations'
                        : 'Send to $count ${count == 1 ? 'club' : 'clubs'}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: Ps.primary,
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Ps.ink,
          ),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF78350F)),
            ),
          ),
        ],
      ),
    );
  }
}
