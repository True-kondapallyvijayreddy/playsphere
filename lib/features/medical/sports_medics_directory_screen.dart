import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sports_medic.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'sports_medic_card.dart';

/// What somebody has asked the sports-medicine directory for.
///
/// A record rather than five separate providers, so the search runs once when
/// a person sets a city and a specialty together rather than twice because
/// the two arrived in different frames. Same reasoning as `CoachQuery`.
typedef MedicQuery = ({
  String keywords,
  String city,
  SportsMedicRole? role,
  String? sportId,
  ConsultationMode? mode,
  bool acceptingOnly,
});

const MedicQuery _emptyMedicQuery = (
  keywords: '',
  city: '',
  role: null,
  sportId: null,
  mode: null,
  acceptingOnly: false,
);

final medicQueryProvider = StateProvider<MedicQuery>((ref) => _emptyMedicQuery);

final medicSearchProvider =
    FutureProvider.autoDispose<List<SportsMedicProfile>>((ref) {
  final q = ref.watch(medicQueryProvider);
  // Nothing asked yet. Reading the whole collection to fill a screen nobody
  // has addressed is the unbounded query the search design exists to avoid —
  // a specialty on its own is enough, because "every physio" is bounded.
  if (q.keywords.trim().isEmpty && q.city.trim().isEmpty && q.role == null) {
    return Future.value(const <SportsMedicProfile>[]);
  }
  return ref.watch(sportsMedicRepositoryProvider).searchMedics(
        keywords: q.keywords,
        city: q.city,
        role: q.role,
        sportId: q.sportId,
        mode: q.mode,
        acceptingOnly: q.acceptingOnly,
      );
});

/// Find a sports doctor or physiotherapist, and list yourself as one.
///
/// The fourth public directory in the product, after grounds, sponsorship and
/// coaches, and built to the same shape on purpose — some words, some chips,
/// a list. What differs is the first field: this screen leads with the city
/// rather than the sport, because an injured player's first constraint is how
/// far they can travel today, not which game hurt them.
class SportsMedicsDirectoryScreen extends ConsumerStatefulWidget {
  const SportsMedicsDirectoryScreen({super.key, this.initialSportId});

  /// Set when a sport hub or an injury page sends somebody here, so the list
  /// arrives already scoped rather than asking the question twice.
  final String? initialSportId;

  @override
  ConsumerState<SportsMedicsDirectoryScreen> createState() =>
      _SportsMedicsDirectoryScreenState();
}

class _SportsMedicsDirectoryScreenState
    extends ConsumerState<SportsMedicsDirectoryScreen> {
  final _words = TextEditingController();
  final _city = TextEditingController();

  @override
  void initState() {
    super.initState();
    final sportId = widget.initialSportId;
    if (sportId == null) return;
    // After the first frame: this writes to a provider, which cannot be done
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(medicQueryProvider.notifier).state = (
        keywords: '',
        city: '',
        role: null,
        sportId: sportId,
        mode: null,
        acceptingOnly: false,
      );
    });
  }

  @override
  void dispose() {
    _words.dispose();
    _city.dispose();
    super.dispose();
  }

  /// Every chip and field goes through here, carrying the two text fields
  /// along, so changing a specialty never silently discards a typed city.
  void _update({
    SportsMedicRole? role,
    String? sportId,
    ConsultationMode? mode,
    bool? acceptingOnly,
    bool clearRole = false,
    bool clearSport = false,
    bool clearMode = false,
  }) {
    final q = ref.read(medicQueryProvider);
    ref.read(medicQueryProvider.notifier).state = (
      keywords: _words.text,
      city: _city.text,
      role: clearRole ? null : (role ?? q.role),
      sportId: clearSport ? null : (sportId ?? q.sportId),
      mode: clearMode ? null : (mode ?? q.mode),
      acceptingOnly: acceptingOnly ?? q.acceptingOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(medicQueryProvider);
    final results = ref.watch(medicSearchProvider);
    final mine = ref.watch(mySportsMedicProfileProvider).valueOrNull;
    final signedIn = ref.watch(currentUidProvider) != null;
    final asked = query.keywords.trim().isNotEmpty ||
        query.city.trim().isNotEmpty ||
        query.role != null;

    return AppScaffold(
      title: 'Doctors & physios',
      subtitle: 'Sports medicine near you',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // City first. An injured player's binding constraint is how
                // far they can get today.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _city,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.place_outlined),
                      hintText: 'City or town — Hyderabad, Warangal',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _update(),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _words,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Name, clinic or qualification',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _update(),
                  ),
                ),

                const _FilterLabel('SPECIALTY'),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final role in SportsMedicRole.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(role.label),
                            selected: query.role == role,
                            onSelected: (on) => on
                                ? _update(role: role)
                                : _update(clearRole: true),
                          ),
                        ),
                    ],
                  ),
                ),

                const _FilterLabel('CONSULTATION'),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final mode in ConsultationMode.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(mode.label),
                            selected: query.mode == mode,
                            onSelected: (on) => on
                                ? _update(mode: mode)
                                : _update(clearMode: true),
                          ),
                        ),
                    ],
                  ),
                ),

                const _FilterLabel('SPORT'),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final sport in SportCatalog.all)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(sport.name),
                            selected: query.sportId == sport.id,
                            onSelected: (on) => on
                                ? _update(sportId: sport.id)
                                : _update(clearSport: true),
                          ),
                        ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Only those taking new patients',
                          style: TextStyle(fontSize: 13, color: Ps.muted),
                        ),
                      ),
                      Switch(
                        value: query.acceptingOnly,
                        onChanged: (v) => _update(acceptingOnly: v),
                      ),
                    ],
                  ),
                ),
                // The sport chips filter but never exclude — a general
                // orthopaedic surgeon who has ticked no sports still fixes
                // the knee a kabaddi player tore, and hiding them on a
                // technicality would withhold the right answer.
                if (query.sportId != null)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Text(
                      'Practitioners who treat all sports are included.',
                      style: TextStyle(fontSize: 11.5, color: Ps.faint),
                    ),
                  ),

                const SizedBox(height: 10),
                results.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Search failed: $e'),
                  ),
                  data: (list) {
                    if (!asked) {
                      return const EmptyState(
                        icon: Icons.travel_explore_outlined,
                        title: 'Where are you?',
                        message: 'Enter a city, or pick a specialty, to see '
                            'who is listed.',
                      );
                    }
                    if (list.isEmpty) {
                      return const EmptyState(
                        icon: Icons.medical_services_outlined,
                        title: 'Nobody listed here yet',
                        message: 'This directory is new and fills up city by '
                            'city. If you are a physio or a sports doctor, '
                            'you can be the first here.',
                      );
                    }
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Ps.surface,
                        borderRadius: BorderRadius.circular(Ps.radius),
                        border: Border.all(color: Ps.border),
                      ),
                      child: Column(
                        children: [
                          for (final m in list) SportsMedicCard(medic: m),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),
                if (signedIn)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.local_hospital_outlined,
                        color: Ps.primary,
                      ),
                      title: Text(
                        mine == null
                            ? 'Are you a doctor or physiotherapist?'
                            : 'Your practice listing',
                      ),
                      subtitle: Text(
                        mine == null
                            ? 'List your practice — players and clubs nearby '
                                'will find you'
                            : mine.isActive
                                ? '${mine.role.label} · '
                                    '${mine.city.isEmpty ? 'no city set' : mine.city}'
                                : 'Currently delisted',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.mySportsMedicProfile),
                    ),
                  ),

                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Practitioners write their own listings. PlaySphere does '
                    'not employ them, does not take a cut of any fee, and '
                    'does not vouch for treatment. Check the registration '
                    'number on the public council register before your first '
                    'appointment.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Ps.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Ps.faint,
        ),
      ),
    );
  }
}
