import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/announcement.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import '../home/home_providers.dart';
import 'widgets/match_rsvp_card.dart';
import 'widgets/match_rsvp_section.dart';

/// Every match this person's clubs are asking about, on its own screen.
///
/// ## Why it moved off the home screen
///
/// The cards are tall — a roster, a vote row, a chat toggle and an
/// organizer's actions — and a member in four clubs during a busy week can
/// have six of them. Stacked on the dashboard they pushed everything else
/// below two screenfuls, which is how a useful section becomes the thing
/// people scroll past.
///
/// Home now carries a COUNT and nothing more, and only when that count is
/// above zero. The count is a question ("two clubs are waiting on you"); this
/// is where the question gets answered, with the room to answer it properly.
class MatchRsvpScreen extends ConsumerWidget {
  const MatchRsvpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(myMatchRsvpsProvider);
    final calls = callsAsync.valueOrNull ?? const <Announcement>[];
    final clashes = ref.watch(myRsvpClashesProvider);
    final uid = ref.watch(currentUidProvider);

    final organizingOrgIds = <String>[
      for (final m in ref.watch(myActiveMembershipsProvider).valueOrNull ??
          const [])
        if (ref.watch(myCapabilitiesProvider(m.orgId)).any((c) =>
            c == Capability.manageCompetitions ||
            c == Capability.manageOrganization))
          m.orgId,
    ];

    // Unanswered first. The whole point of the screen is the ones still
    // waiting on this person; a match they already said yes to is a record,
    // not a question, and it should not sit above one they have not answered.
    final unanswered = [
      for (final c in calls)
        if (uid == null || c.poll?.voteOf(uid) == null) c,
    ];
    final answered = [
      for (final c in calls)
        if (uid != null && c.poll?.voteOf(uid) != null) c,
    ];

    return AppScaffold(
      title: 'Match availability',
      subtitle: calls.isEmpty
          ? null
          : '${unanswered.length} waiting on you',
      floatingActionButton: organizingOrgIds.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showCreateMatchRsvpSheet(
                context: context,
                ref: ref,
                orgIds: organizingOrgIds,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Call a match'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          ContentBounds(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsyncErrorStrip(value: callsAsync, what: 'match availability'),
                if (calls.isEmpty)
                  const _Empty()
                else ...[
                  if (unanswered.isNotEmpty) ...[
                    const _Heading('Waiting on you'),
                    for (final call in unanswered)
                      MatchRsvpCard(
                        key: ValueKey(call.id),
                        announcement: call,
                        canOrganize: ref
                            .watch(myCapabilitiesProvider(call.orgId))
                            .contains(Capability.manageCompetitions),
                        clashesWith: clashes[call.id] ?? const [],
                      ),
                  ],
                  if (answered.isNotEmpty) ...[
                    const _Heading('You have answered'),
                    for (final call in answered)
                      MatchRsvpCard(
                        key: ValueKey(call.id),
                        announcement: call,
                        canOrganize: ref
                            .watch(myCapabilitiesProvider(call.orgId))
                            .contains(Capability.manageCompetitions),
                        clashesWith: clashes[call.id] ?? const [],
                      ),
                  ],
                ],
              ],
            ),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Ps.faint,
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: EmptyState(
          icon: Icons.event_available_outlined,
          title: 'Nothing to answer',
          message: 'When one of your clubs asks who is free for a match, it '
              'lands here and you answer in one tap.',
        ),
      );
}
