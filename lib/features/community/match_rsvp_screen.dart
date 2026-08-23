import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/announcement.dart';
import '../../core/models/challenge.dart';
import '../../core/models/group_entry.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import '../home/home_providers.dart';
import '../notifications/notifications_screen.dart'
    show ActionCard, ActionTone, TournamentInviteCard;
import '../../domain/scoring/scoring_registry.dart';
import 'widgets/match_rsvp_card.dart';
import 'widgets/match_rsvp_section.dart';
import 'widgets/squad_invite_card.dart';

/// Everything waiting on this person to say yes, no or maybe.
///
/// ## Why it moved off the home screen
///
/// The cards are tall — a roster, a vote row, a chat toggle and an
/// organizer's actions — and a member in four clubs during a busy week can
/// have six of them. Stacked on the dashboard they pushed everything else
/// below two screenfuls, which is how a useful section becomes the thing
/// people scroll past.
///
/// Home now carries a COUNT and nothing more. The count is a question ("four
/// things are waiting on you"); this is where the question gets answered, with
/// the room to answer it properly.
///
/// ## Why it is four kinds of question and not one
///
/// It started as match availability alone, and that was the wrong boundary. A
/// person is asked to commit to a Saturday in four different shapes:
///
/// - **a match call** — their club asking the squad who is free;
/// - **a squad invitation** — a teammate having named them in a side, which
///   had no home at all before this screen and sat unanswered on an event page
///   they had no reason to open;
/// - **a tournament invitation** — another club asking theirs to enter;
/// - **a challenge** — another club asking theirs for a fixture.
///
/// All four are "somebody is waiting on an answer from you", all four expire,
/// and splitting them across four screens is what produced the state this
/// replaces: a member who had answered everything they could find, and three
/// people still waiting.
///
/// The last two are organizer-facing and appear only for people who can
/// actually answer them — the providers behind them are capability-gated, for
/// the reason those providers give. They are also on the Notifications screen,
/// which is the whole inbox; this screen is the subset that is a yes/no.
class MatchRsvpScreen extends ConsumerWidget {
  const MatchRsvpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(myMatchRsvpsProvider);
    final calls = callsAsync.valueOrNull ?? const <Announcement>[];
    final clashes = ref.watch(myRsvpClashesProvider);
    final uid = ref.watch(currentUidProvider);

    final squadsAsync = ref.watch(mySquadInvitesProvider);
    final squads = squadsAsync.valueOrNull ?? const <GroupEntry>[];
    final invitesAsync = ref.watch(myTournamentInvitesProvider);
    final invites = invitesAsync.valueOrNull ?? const <TournamentInvite>[];
    final challengesAsync = ref.watch(myIncomingChallengesProvider);
    final challenges = challengesAsync.valueOrNull ?? const <Challenge>[];

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

    // Everything still owed an answer, across all four kinds. Answered match
    // calls are excluded because they are a record rather than a question —
    // the same reason they sink to the bottom of the list below.
    final owed = unanswered.length +
        squads.length +
        invites.length +
        challenges.length;

    final nothingAtAll = calls.isEmpty &&
        squads.isEmpty &&
        invites.isEmpty &&
        challenges.isEmpty;

    return AppScaffold(
      title: 'Invitations & RSVPs',
      subtitle: owed == 0 ? null : '$owed waiting on you',
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
                AsyncErrorStrip(
                  value: squadsAsync,
                  what: 'squads you have been named in',
                ),
                AsyncErrorStrip(
                  value: invitesAsync,
                  what: 'tournament invitations',
                ),
                AsyncErrorStrip(
                  value: challengesAsync,
                  what: 'challenges from other clubs',
                ),

                // First, above the match calls, because a squad invitation is
                // addressed to this person BY NAME and holds four other people
                // up until it is answered. A match call is addressed to a
                // squad and survives one person not replying.
                if (squads.isNotEmpty) ...[
                  const _Heading('You have been named in a squad'),
                  for (final g in squads)
                    SquadInviteCard(key: ValueKey(g.id), group: g),
                ],

                if (nothingAtAll)
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
                  // The two club-to-club asks. Below the personal ones, and
                  // separately headed, because they are answered on behalf of
                  // a club rather than for oneself — a distinction that
                  // matters when the answer commits eleven other people.
                  if (invites.isNotEmpty || challenges.isNotEmpty) ...[
                    const _Heading('Another club is asking yours'),
                    for (final i in invites)
                      TournamentInviteCard(key: ValueKey(i.id), invite: i),
                    for (final c in challenges)
                      ActionCard(
                        icon: Icons.sports_kabaddi_outlined,
                        tone: ActionTone.tertiary,
                        title: '${c.fromOrgName} has challenged you',
                        subtitle: SportCatalog.byId(c.sportId).name,
                        actionLabel: 'Answer',
                        onTap: () => context.push(Routes.challenges(c.toOrgId)),
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
          message: 'A match call from your club, a teammate putting you in a '
              'squad, or another club inviting yours — all of it lands here, '
              'and you answer in one tap.',
        ),
      );
}
