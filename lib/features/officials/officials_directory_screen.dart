/// The registered officials directory — who is available to umpire, and how
/// to reach them.
///
/// ## What was actually missing
///
/// `/community/officials` already existed and was a registration FORM. You
/// could describe yourself as a district-certified kabaddi umpire, tick
/// "available", save — and then nothing. No screen in the product read
/// `umpires` back except two assignment pickers buried inside a tournament
/// somebody else was running. So the registry took people's details and gave
/// them nowhere to be found, which is the same failure as a badge with no
/// process behind it: it tells an official PlaySphere connects them to work,
/// and that was not true.
///
/// This is the read side. Registration moved to
/// `Routes.umpireRegister`, and this screen owns the front door.
///
/// ## Contact details, and why they are shown
///
/// `UmpireProfile` carries a phone number on purpose — unlike a
/// `SponsorshipListing` or a `GiveNeed`, both of which deliberately carry no
/// contact route at all. The difference is consent and direction: an official
/// registers here in order to be called about work, and an organizer with a
/// fixture on Sunday and no umpire needs to reach one today, not through a
/// mediated offer that gets answered on Monday. The registration form is where
/// somebody decides to be reachable; leaving the number out of the only screen
/// that displays the registry would make that decision meaningless.
///
/// That is also why this screen, alone among the three directories, is behind
/// a sign-in. `coaches` and `sportsMedics` are world-readable and carry no
/// number; `firestore.rules` gates `umpires` on `isSignedIn()` precisely
/// because the document holds one. So the screen asks for a sign-in rather
/// than firing a query it knows will be refused — an anonymous visitor
/// otherwise got a permission error where the empty state should be.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/umpire_profile.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

/// The certification tiers `UmpireRegistryScreen` writes, in the order a
/// reader ranks them. Kept here rather than on [UmpireProfile] because the
/// model stores a free string — a district association inventing its own tier
/// must not make a profile unreadable — so this is a display map with a
/// fallback, not a validation list.
const _badgeLabels = <String, String>{
  'community': 'Community',
  'district_certified': 'District certified',
  'state_certified': 'State certified',
  'association_certified': 'Association certified',
};

String _badgeLabel(String wire) =>
    _badgeLabels[wire] ?? wire.replaceAll('_', ' ');

class OfficialsDirectoryScreen extends ConsumerStatefulWidget {
  const OfficialsDirectoryScreen({super.key, this.initialSportId});

  /// Set when a sport hub sends somebody here, so the list arrives already
  /// scoped — same courtesy `CoachesScreen` extends.
  final String? initialSportId;

  @override
  ConsumerState<OfficialsDirectoryScreen> createState() =>
      _OfficialsDirectoryScreenState();
}

class _OfficialsDirectoryScreenState
    extends ConsumerState<OfficialsDirectoryScreen> {
  @override
  void initState() {
    super.initState();
    final sportId = widget.initialSportId;
    if (sportId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(officialsQueryProvider.notifier).state =
          (sportId: sportId, district: null, availableOnly: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(officialsQueryProvider);
    final signedIn = ref.watch(currentUidProvider) != null;
    final mine =
        signedIn ? ref.watch(myUmpireProfileProvider).valueOrNull : null;
    // Mounted only behind the sign-in gate: `firestore.rules` refuses this
    // read outright to an anonymous caller, and firing it anyway would put a
    // permission error on screen where the sign-in prompt belongs.
    final results = signedIn
        ? ref.watch(officialsDirectoryProvider)
        : const AsyncValue<List<UmpireProfile>>.data([]);

    // Only the sports the registration form actually offers. A directory
    // filter for a sport nobody can register under is a filter that is always
    // empty — see `UmpireRegistryScreen`'s own list.
    final sports = SportCatalog.all
        .where((s) => _registrableSports.contains(s.id))
        .toList(growable: false);

    return AppScaffold(
      title: 'Umpires & officials',
      subtitle: 'Registered umpires and referees',
      // No floating action button. The directory is what somebody came for —
      // a club that needs an umpire on Sunday vastly outnumbers a person
      // deciding to become one — so registering is a card at the END of the
      // list rather than a button floating over it. A FAB would also have
      // covered the last row's Call button, which is the one control on this
      // screen that has to work.
      body: !signedIn
          ? const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Sign in to see registered officials',
              message:
                  'Officials list a contact number here so clubs can reach '
                  'them directly, so the directory is not open to anonymous '
                  'visitors.',
            )
          : Column(
              children: [
                _Filters(sports: sports),
                Expanded(
                  child: AsyncView(
                    value: results,
                    onRetry: () => ref.invalidate(officialsDirectoryProvider),
                    skeleton: const PsListSkeleton(),
                    builder: (officials) => ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 32),
                      children: [
                        ContentBounds(
                          maxWidth: 700,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (officials.isEmpty)
                                _EmptyDirectory(query: query)
                              else ...[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                  child: Text(
                                    '${officials.length} '
                                    'official${officials.length == 1 ? '' : 's'}'
                                    '${query.district == null ? '' : ' in ${query.district}'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(context).hintColor,
                                        ),
                                  ),
                                ),
                                for (final o in officials)
                                  _OfficialCard(official: o),
                              ],

                              // The registration door, below the list.
                              _RegisterCard(alreadyListed: mine != null),
                            ],
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

/// Sport, district and availability — the three things a club filters on when
/// it needs somebody to stand in the middle on Sunday.
class _Filters extends ConsumerStatefulWidget {
  const _Filters({required this.sports});

  final List<SportSpec> sports;

  @override
  ConsumerState<_Filters> createState() => _FiltersState();
}

class _FiltersState extends ConsumerState<_Filters> {
  final _district = TextEditingController();

  @override
  void initState() {
    super.initState();
    _district.text = ref.read(officialsQueryProvider).district ?? '';
  }

  @override
  void dispose() {
    _district.dispose();
    super.dispose();
  }

  void _set({
    String? Function()? sportId,
    String? Function()? district,
    bool? availableOnly,
  }) {
    final q = ref.read(officialsQueryProvider);
    ref.read(officialsQueryProvider.notifier).state = (
      sportId: sportId != null ? sportId() : q.sportId,
      district: district != null ? district() : q.district,
      availableOnly: availableOnly ?? q.availableOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(officialsQueryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: ContentBounds(
        maxWidth: 700,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: query.sportId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Sport',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All sports'),
                      ),
                      for (final s in widget.sports)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => _set(sportId: () => v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _district,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'District',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: query.district == null
                          ? const Icon(Icons.search, size: 18)
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _district.clear();
                                _set(district: () => null);
                              },
                            ),
                    ),
                    onSubmitted: (v) => _set(
                      district: () => v.trim().isEmpty ? null : v.trim(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilterChip(
                  label: const Text('Free now'),
                  selected: query.availableOnly,
                  onSelected: (on) => _set(availableOnly: on),
                ),
                const Spacer(),
                if (query.sportId != null ||
                    query.district != null ||
                    query.availableOnly)
                  TextButton(
                    onPressed: () {
                      _district.clear();
                      ref.read(officialsQueryProvider.notifier).state =
                          (sportId: null, district: null, availableOnly: false);
                    },
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDirectory extends StatelessWidget {
  const _EmptyDirectory({required this.query});

  final OfficialsQuery query;

  @override
  Widget build(BuildContext context) {
    final filtered = query.sportId != null ||
        query.district != null ||
        query.availableOnly;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: EmptyState(
        icon: Icons.verified_user_outlined,
        title: filtered
            ? 'No officials match these filters'
            : 'No officials registered yet',
        message: filtered
            ? 'Try clearing the district, or widening to all sports — an '
                'umpire one district over is usually still reachable.'
            : 'Registering takes a minute, and clubs looking for an umpire '
                'look here.',
      ),
    );
  }
}

/// "Do you officiate?" — deliberately the last thing on the screen.
class _RegisterCard extends StatelessWidget {
  const _RegisterCard({required this.alreadyListed});

  final bool alreadyListed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alreadyListed ? 'You are listed here' : 'Do you officiate?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              alreadyListed
                  ? 'Update your sports, district, tier, or mark yourself '
                      'unavailable when you cannot take matches.'
                  : 'Register once and clubs across your district can find '
                      'you when they need an umpire. Every match you stand in '
                      'is counted on your listing.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.push(Routes.umpireRegister),
              icon: Icon(alreadyListed ? Icons.edit_outlined : Icons.add),
              label: Text(
                alreadyListed ? 'Edit my listing' : 'Register as an official',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the sport list `UmpireRegistryScreen` offers. Duplicated rather
/// than shared because the registration list is a product choice about who may
/// register, not a fact about the sport catalogue — if the two ever diverge on
/// purpose, this is the seam where that becomes visible instead of silent.
const _registrableSports = {
  'cricket',
  'football',
  'basketball',
  'kabaddi',
  'volleyball',
  'kho_kho',
  'tennis',
  'table_tennis',
  'hockey',
};

class _OfficialCard extends StatelessWidget {
  const _OfficialCard({required this.official});

  final UmpireProfile official;

  Future<void> _dial(BuildContext context) async {
    final phone = official.phone;
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchUrl(uri)) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the dialler — $phone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = official.phone;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PsAvatar(
                  name: official.displayName,
                  photoUrl: official.photoUrl,
                  seed: official.uid,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        official.displayName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          _badgeLabel(official.badgeLevel),
                          if (official.geo.district != null)
                            official.geo.district!,
                          // Only once it means something. "0 matches
                          // officiated" beside a name reads as a warning
                          // about that person, when it usually just means
                          // they registered last week.
                          if (official.matchesOfficiated > 0)
                            '${official.matchesOfficiated} '
                                'match${official.matchesOfficiated == 1 ? '' : 'es'} '
                                'officiated',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                if (official.isAvailable)
                  Chip(
                    label: const Text('Free'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.primaryContainer,
                  )
                else
                  const Chip(
                    label: Text('Busy'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (official.sports.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in official.sports)
                    Chip(
                      label: Text(SportCatalog.byId(id).name),
                      avatar: Text(SportCatalog.byId(id).icon),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            if (phone == null)
              Text(
                'No contact number on their listing — reach them through a '
                'club you both belong to.',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              )
            else
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _dial(context),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      phone,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
