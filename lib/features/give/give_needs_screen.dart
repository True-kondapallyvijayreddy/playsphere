import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/give_need.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// The verified needs board — "12 pairs of cricket shoes for a village club
/// in Nalgonda", not a generic appeal. See `GiveNeed` for why only staff can
/// put a card on this board.
class GiveNeedsScreen extends ConsumerStatefulWidget {
  const GiveNeedsScreen({super.key});

  @override
  ConsumerState<GiveNeedsScreen> createState() => _GiveNeedsScreenState();
}

class _GiveNeedsScreenState extends ConsumerState<GiveNeedsScreen> {
  final _cityController = TextEditingController();
  String? _city;

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needs = ref.watch(giveNeedsBoardProvider(_city));

    return AppScaffold(
      title: 'Needs board',
      subtitle: 'Verified requests you can act on directly',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.giveRaiseNeed),
        icon: const Icon(Icons.add),
        label: const Text('Raise a need'),
      ),
      body: AsyncView(
        value: needs,
        onRetry: () => ref.invalidate(giveNeedsBoardProvider(_city)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      controller: _cityController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'City',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _cityController.text.isEmpty
                            ? null
                            : IconButton(
                              tooltip: 'Clear',
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _cityController.clear();
                                  _city = null;
                                }),
                              ),
                      ),
                      onSubmitted: (v) => setState(
                        () => _city = v.trim().isEmpty ? null : v.trim(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    EmptyState(
                      icon: Icons.checklist_outlined,
                      title: _city == null
                          ? 'No verified needs right now'
                          : 'No verified need in "$_city" yet',
                      message: 'Clubs and players raise needs, and '
                          'PlaySphere verifies them before they land here.',
                    )
                  else
                    for (final n in list) _NeedCard(need: n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedCard extends StatelessWidget {
  const _NeedCard({required this.need});

  final GiveNeed need;

  String get _who => switch (need.beneficiaryType) {
        GiveBeneficiaryType.player => need.playerName ?? 'A player',
        GiveBeneficiaryType.team ||
        GiveBeneficiaryType.club =>
          need.orgName ?? 'A club',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  need.beneficiaryType == GiveBeneficiaryType.player
                      ? Icons.person_outline
                      : Icons.groups_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    need.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                _who,
                if (need.city.isNotEmpty) need.city,
                if (need.playersCount != null)
                  '${need.playersCount} players',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
            if (need.description != null) ...[
              const SizedBox(height: 6),
              Text(need.description!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in need.items)
                  Chip(
                    label: Text('${l.quantity} × ${l.category.label}'),
                    avatar: Text(l.category.emoji),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => context.push(Routes.giveDonate),
                child: const Text('Donate towards this'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
