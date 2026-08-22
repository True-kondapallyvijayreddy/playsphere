import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/router/app_router.dart';
import '../../domain/medical/sports_medicine_library.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'video_link_button.dart';

/// Common sports injuries: what happened, what to do in the first hour, and
/// the point at which the answer stops being an ice pack.
///
/// Every entry carries red flags and every entry shows them in red, above the
/// rehabilitation section rather than below it. An injury guide whose only
/// exit is "see a physiotherapist eventually" is the dangerous kind; this one
/// is written so that the sentence which sends somebody to a hospital is the
/// one they cannot scroll past.
class SportsInjuriesScreen extends StatefulWidget {
  const SportsInjuriesScreen({super.key, this.initialSportId});

  final String? initialSportId;

  @override
  State<SportsInjuriesScreen> createState() => _SportsInjuriesScreenState();
}

class _SportsInjuriesScreenState extends State<SportsInjuriesScreen> {
  String? _sportId;
  BodyPart? _part;

  @override
  void initState() {
    super.initState();
    _sportId = widget.initialSportId;
  }

  @override
  Widget build(BuildContext context) {
    // Only the body parts that actually have entries under the current sport,
    // so the filter row never offers a chip that returns an empty list.
    final parts = SportsMedicineLibrary.bodyPartsWithInjuries(
      sportId: _sportId,
    );
    if (_part != null && !parts.contains(_part)) _part = null;

    final list = SportsMedicineLibrary.injuriesFor(
      sportId: _sportId,
      part: _part,
    );

    return AppScaffold(
      title: 'Injuries & first aid',
      subtitle: 'What to do in the first hour',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ContentBounds(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Ps.live.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(Ps.radiusSm),
                    border: Border.all(
                      color: Ps.live.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: Ps.live),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This is general guidance, not a diagnosis. Every '
                          'entry below has a red-flag list — if any of those '
                          'apply, stop managing it yourself and get to a '
                          'doctor.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: Ps.ink,
                          ),
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
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('All sports'),
                          selected: _sportId == null,
                          onSelected: (_) => setState(() => _sportId = null),
                        ),
                      ),
                      for (final sport in SportCatalog.all)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(sport.name),
                            selected: _sportId == sport.id,
                            onSelected: (on) => setState(
                              () => _sportId = on ? sport.id : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const _FilterLabel('BODY PART'),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final p in parts)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(p.label),
                            selected: _part == p,
                            onSelected: (on) =>
                                setState(() => _part = on ? p : null),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (list.isEmpty)
                  const EmptyState(
                    icon: Icons.healing_outlined,
                    title: 'Nothing written for that yet',
                    message: 'Clear a filter to see the rest of the guide.',
                  )
                else
                  for (final injury in list) _InjuryCard(injury: injury),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    // The obvious next action after reading about a torn
                    // ACL, carried straight into the directory with the
                    // sport already applied so nobody answers that question
                    // twice.
                    onPressed: () => context.push(
                      _sportId == null
                          ? Routes.sportsMedics
                          : Routes.sportsMedicsIn(_sportId!),
                    ),
                    icon: const Icon(Icons.medical_services_outlined, size: 18),
                    label: const Text('Find a physio or sports doctor'),
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

class _InjuryCard extends StatelessWidget {
  const _InjuryCard({required this.injury});

  final SportsInjury injury;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Ps.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Ps.radiusSm),
            ),
            child: const Icon(Icons.healing_outlined,
                size: 20, color: Ps.primary),
          ),
          title: Text(
            injury.name,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            injury.bodyPart.label,
            style: const TextStyle(fontSize: 12, color: Ps.muted),
          ),
          children: [
            Text(
              injury.mechanism,
              style: const TextStyle(fontSize: 13, height: 1.5, color: Ps.ink),
            ),
            const SizedBox(height: 14),

            _Section(
              icon: Icons.visibility_outlined,
              title: 'What it feels like',
              items: injury.symptoms,
            ),
            _Section(
              icon: Icons.medical_information_outlined,
              title: injury.protocol == null
                  ? 'First aid'
                  : 'First aid · ${injury.protocol}',
              items: injury.firstAid,
              numbered: true,
            ),
            // Red, and above rehabilitation rather than below it. Somebody
            // skimming this card must not be able to reach the exercises
            // without passing the line that says when not to do them.
            _Section(
              icon: Icons.warning_amber_rounded,
              title: 'Red flags — see a doctor',
              items: injury.redFlags,
              tint: Ps.live,
            ),
            _Section(
              icon: Icons.fitness_center_outlined,
              title: 'Getting back',
              items: injury.rehab,
            ),

            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.schedule_outlined, size: 15, color: Ps.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    injury.recovery,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Ps.faint,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            VideoLinkButton(video: injury.video),
          ],
        ),
      ),
    );
  }
}

/// A titled list inside an injury card.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.items,
    this.numbered = false,
    this.tint,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  /// Numbered where order is instruction rather than enumeration — the first
  /// aid steps are done in sequence, the symptoms are not.
  final bool numbered;

  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final color = tint ?? Ps.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      numbered ? '${i + 1}.' : '•',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      items[i],
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Ps.ink,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
