import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/promo_banner.dart';

/// Every tournament in the country that is open to outside entries.
///
/// ## Why the app needed a screen it did not have
///
/// Every list in the product answered "what is happening in MY club". That is
/// the right question for a member and the wrong one for the thing a club
/// actually needs from a national platform: somewhere to play. A district
/// badminton open lived inside one club's tenant, visible only to that club's
/// own members — the one group with no reason to discover it. Clubs found
/// tournaments on WhatsApp forwards, or did not find them.
///
/// Only events whose organizer set "open to non-members" appear. That flag is
/// the invitation, and it is also the security boundary: the collection-group
/// rule refuses any query that does not pin it, so this screen structurally
/// cannot show a club's private draws.
class GlobalEventsScreen extends ConsumerStatefulWidget {
  const GlobalEventsScreen({super.key});

  @override
  ConsumerState<GlobalEventsScreen> createState() => _GlobalEventsScreenState();
}

class _GlobalEventsScreenState extends ConsumerState<GlobalEventsScreen> {
  final _search = TextEditingController();
  String? _sportId;

  /// Null means both. Most people want the ones they can still enter, so that
  /// is the default — a board where two thirds of the rows cannot be acted on
  /// is a board people stop opening.
  bool _openOnly = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(globalEventsProvider);
    final query = _search.text.trim().toLowerCase();

    return AppScaffold(
      title: 'Global events',
      subtitle: 'Open to entries across the country',
      body: AsyncView(
        value: async,
        builder: (all) {
          // Filtered here rather than in the query — see
          // `CompetitionRepository.watchGlobalEvents` for why.
          final shown = all.where((c) {
            if (_sportId != null && c.sportId != _sportId) return false;
            if (_openOnly &&
                c.displayStatus() != CompetitionStatus.registrationOpen) {
              return false;
            }
            if (query.isEmpty) return true;
            return c.name.toLowerCase().contains(query) ||
                c.sportName.toLowerCase().contains(query) ||
                (c.venue ?? '').toLowerCase().contains(query);
          }).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PromoBanner(
                      slot: PromoSlot.events,
                      margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Search by name, sport or venue',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('Open for entries'),
                            selected: _openOnly,
                            onSelected: (v) => setState(() => _openOnly = v),
                          ),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('All sports'),
                            selected: _sportId == null,
                            onSelected: (_) =>
                                setState(() => _sportId = null),
                          ),
                          for (final s in SportCatalog.all) ...[
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Text(s.icon),
                              label: Text(s.name),
                              selected: _sportId == s.id,
                              onSelected: (_) =>
                                  setState(() => _sportId = s.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: EmptyState(
                          icon: Icons.public_off,
                          title: 'Nothing open right now',
                          message: 'Events appear here when an organizer opens '
                              'them to clubs other than their own.',
                        ),
                      )
                    else
                      for (final c in shown)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: _EventCard(competition: c),
                        ),
                    if (shown.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${shown.length} of ${all.length} open events.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    final theme = Theme.of(context);
    final sport = SportCatalog.byId(c.sportId);
    final status = c.displayStatus();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Text(sport.icon, style: const TextStyle(fontSize: 24)),
        title: Text(c.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.sportName} · ${c.category.label}'),
            if (c.venue != null && c.venue!.isNotEmpty) Text(c.venue!),
            if (c.startDate != null)
              Text(
                _when(c.startDate!),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(status.label),
          visualDensity: VisualDensity.compact,
        ),
        // Opens the event's own page, where Register already lives and already
        // enforces eligibility. Nothing about entry needed reimplementing here.
        onTap: () => context.push(Routes.competition(c.orgId, c.id)),
      ),
    );
  }

  static String _when(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
