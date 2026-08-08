import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/models/scoring_request.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/notifications/notification_model.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart';
import '../home/home_providers.dart';

/// Everything that will not move until this person does something about it.
///
/// This used to sit in the middle of the home screen, where it competed with
/// the live scores for the top of the page and pushed the one action most
/// people open the app for — start scoring — below the fold. It is the same
/// content, on its own screen, reached from the bell.
///
/// The ordering below is deliberate and is not alphabetical or chronological:
/// it is by how expensive it is to answer late. A match about to start with
/// nobody cleared to score it is unrecoverable; a join request can wait a day.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoringAsync = ref.watch(myScoringAssignmentsProvider);
    final scoring = scoringAsync.valueOrNull ?? const <Fixture>[];
    final challengesAsync = ref.watch(myIncomingChallengesProvider);
    final challenges = challengesAsync.valueOrNull ?? const [];
    final approvalsAsync = ref.watch(myPendingApprovalsProvider);
    final approvals = approvalsAsync.valueOrNull ?? const [];
    final scoreAsksAsync = ref.watch(myScoringRequestsProvider);
    final scoreAsks = scoreAsksAsync.valueOrNull ?? const <ScoringRequest>[];
    final invitesAsync = ref.watch(myTournamentInvitesProvider);
    final invites = invitesAsync.valueOrNull ?? const <TournamentInvite>[];
    final feedAsync = ref.watch(myNotificationFeedProvider);
    final feed = feedAsync.valueOrNull ?? const <AppNotification>[];
    final unreadIds = [for (final n in feed) if (!n.read) n.id];

    final nothingWaiting = scoring.isEmpty &&
        challenges.isEmpty &&
        approvals.isEmpty &&
        scoreAsks.isEmpty &&
        invites.isEmpty;

    return AppScaffold(
      title: 'Notifications',
      subtitle: 'What is waiting on you, and what your clubs are doing',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ContentBounds(
            maxWidth: 1100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                AsyncErrorStrip(
                  value: scoringAsync,
                  what: 'the matches you are scoring',
                ),
                AsyncErrorStrip(
                  value: challengesAsync,
                  what: 'challenges from other clubs',
                ),
                AsyncErrorStrip(
                  value: approvalsAsync,
                  what: 'join requests',
                ),
                AsyncErrorStrip(
                  value: scoreAsksAsync,
                  what: 'requests to score a match',
                ),
                AsyncErrorStrip(
                  value: invitesAsync,
                  what: 'tournament invitations',
                ),

                if (nothingWaiting && feed.isEmpty)
                  const QuietCard(
                    icon: Icons.done_all,
                    title: 'Nothing here yet',
                    message: 'Match assignments, challenges from other clubs, '
                        'requests to score, people asking to join your club '
                        'and everything else your clubs do all land here.',
                  )
                else if (nothingWaiting)
                  const QuietCard(
                    icon: Icons.done_all,
                    title: 'Nothing is waiting on you',
                    message: 'Match assignments, challenges from other clubs, '
                        'requests to score and people asking to join your club '
                        'all land here.',
                  )
                else ...[
                  // "Waiting on you" was reported as confusing wording — it
                  // named a state rather than telling anyone what to do. The
                  // heading now says what the list is: things that need this
                  // person to act.
                  const SectionHeader(
                    icon: Icons.pending_actions_outlined,
                    title: 'Needs your action',
                    subtitle: 'Nothing here moves until you act on it',
                  ),
                  for (final f in scoring)
                    ActionCard(
                      icon: Icons.sports_cricket_outlined,
                      tone: ActionTone.primary,
                      title: f.isLive
                          ? 'You are scoring ${f.entrantAName} v '
                              '${f.entrantBName}'
                          : 'You are down to score ${f.entrantAName} v '
                              '${f.entrantBName}',
                      subtitle: [
                        if (f.roundLabel != null) f.roundLabel!,
                        if (f.venue != null) f.venue!,
                        if (f.scheduledAt != null) friendlyDate(f.scheduledAt!),
                      ].join(' · '),
                      actionLabel: f.isLive ? 'Resume' : 'Open',
                      onTap: () =>
                          context.push(Routes.scoring(f.orgId, f.compId, f.id)),
                    ),
                  for (final c in challenges)
                    ActionCard(
                      icon: Icons.sports_kabaddi_outlined,
                      tone: ActionTone.tertiary,
                      title: 'A club has challenged you',
                      subtitle: '${c.fromOrgName} · '
                          '${SportCatalog.byId(c.sportId).name}',
                      actionLabel: 'Answer',
                      onTap: () => context.push(Routes.challenges(c.toOrgId)),
                    ),
                  for (final i in invites) TournamentInviteCard(invite: i),
                  // Above join requests on purpose: a match may be about to
                  // start, and an unanswered request to score it means a match
                  // nobody records. A join request can wait a day.
                  for (final r in scoreAsks) ScoringRequestCard(request: r),
                  if (approvals.isNotEmpty)
                    ActionCard(
                      icon: Icons.person_add_alt,
                      tone: ActionTone.tertiary,
                      title: '${approvals.length} '
                          '${approvals.length == 1 ? 'person is' : 'people are'}'
                          ' waiting to join',
                      subtitle: 'They cannot play or be picked until you '
                          'approve them',
                      actionLabel: 'Review',
                      onTap: () =>
                          context.push(Routes.members(approvals.first.orgId)),
                    ),
                ],

                // --- Everything else your clubs have done -------------------
                //
                // Distinct from "Needs your action" above on purpose: nothing
                // here is an obligation, it is a record — a result posted, a
                // tournament announced, a match starting. A plain member with
                // no organizer capability never has anything in the action
                // list above (every one of those providers is capability-
                // gated), so without this section "Notifications" was
                // permanently empty for anyone who was not running their club.
                if (feed.isNotEmpty || feedAsync.hasError) ...[
                  if (!nothingWaiting) const SizedBox(height: 8),
                  SectionHeader(
                    icon: Icons.campaign_outlined,
                    title: 'Club activity',
                    subtitle: 'Everything happening across your clubs',
                    trailing: unreadIds.isEmpty
                        ? null
                        : TextButton(
                            onPressed: () => ref
                                .read(notificationRepositoryProvider)
                                .markAllRead(
                                  ref.read(currentUidProvider) ?? '',
                                  unreadIds,
                                ),
                            child: const Text('Mark all read'),
                          ),
                  ),
                  AsyncErrorStrip(value: feedAsync, what: 'club activity'),
                  if (feed.isEmpty && !feedAsync.hasError)
                    const QuietCard(
                      icon: Icons.campaign_outlined,
                      title: 'No club activity yet',
                      message: 'Results, tournament announcements, event '
                          'reminders and everything else your clubs send out '
                          'will appear here.',
                    )
                  else
                    for (final n in feed) ActivityCard(notification: n),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry in the club activity feed — a result, a tournament
/// announcement, an event reminder, whatever a club sent out. Read-only:
/// unlike the cards above this, there is nothing to decide, only something to
/// know. Tapping it opens whatever it is about and marks it read.
class ActivityCard extends ConsumerWidget {
  const ActivityCard({super.key, required this.notification});

  final AppNotification notification;

  static const _icons = {
    NotificationType.eventReminder: Icons.event_available_outlined,
    NotificationType.matchStart: Icons.sports_outlined,
    NotificationType.result: Icons.emoji_events_outlined,
    NotificationType.membershipApproved: Icons.how_to_reg_outlined,
    NotificationType.challengeReceived: Icons.sports_kabaddi_outlined,
    NotificationType.eventCancelled: Icons.event_busy_outlined,
    NotificationType.tournamentAnnounced: Icons.campaign_outlined,
    NotificationType.tournamentInvite: Icons.mail_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !notification.read;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: unread ? scheme.surfaceContainerHighest : null,
      child: ListTile(
        leading: Icon(
          _icons[notification.type] ?? Icons.notifications_outlined,
          color: unread ? scheme.primary : theme.hintColor,
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          [
            if (notification.body.isNotEmpty) notification.body,
            relativeTime(notification.createdAt),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: unread
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: () {
          final uid = ref.read(currentUidProvider);
          if (uid != null && unread) {
            ref
                .read(notificationRepositoryProvider)
                .markRead(uid, notification.id);
          }
          final route = notification.deepLink?.resolve();
          if (route != null) context.push(route);
        },
      ),
    );
  }
}

enum ActionTone { primary, tertiary }

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final ActionTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      ActionTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      ActionTone.tertiary => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: bg,
      child: ListTile(
        leading: Icon(icon, color: fg),
        title: Text(
          title,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
        subtitle:
            subtitle.isEmpty ? null : Text(subtitle, style: TextStyle(color: fg)),
        trailing: TextButton(onPressed: onTap, child: Text(actionLabel)),
        onTap: onTap,
      ),
    );
  }
}

/// "Nizampet Sports Club has invited you" — answered from here.
///
/// Answered in place, not behind a tap through to the host's tournament, for
/// the same reason a scoring request is: the decision is a yes or a no, the
/// person deciding is usually not sitting down with the app open, and two
/// screens between them and "yes" is how an invitation goes unanswered until
/// the entry deadline has passed. The public page is still one tap away for
/// anyone who wants to read the draw first.
class TournamentInviteCard extends ConsumerStatefulWidget {
  const TournamentInviteCard({super.key, required this.invite});

  final TournamentInvite invite;

  @override
  ConsumerState<TournamentInviteCard> createState() =>
      _TournamentInviteCardState();
}

class _TournamentInviteCardState extends ConsumerState<TournamentInviteCard> {
  bool _busy = false;

  Future<void> _answer(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(tournamentRepositoryProvider).respondToInvite(
            inviteId: widget.invite.id,
            status: status,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                status == 'accepted'
                    ? '${widget.invite.fromOrgName} know you are coming.'
                    : 'Invitation declined.',
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = widget.invite;
    final when = _dates(i);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_outlined,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i.fromOrgName} has invited you',
                        style: TextStyle(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        when == null
                            ? i.tournamentName
                            : '${i.tournamentName} · $when',
                        style: TextStyle(color: scheme.onTertiaryContainer),
                      ),
                      if (i.message != null && i.message!.isNotEmpty)
                        Text(
                          '“${i.message}”',
                          style: TextStyle(
                            color: scheme.onTertiaryContainer,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.push(
                            Routes.publicTournament(i.fromOrgId, i.tournamentId),
                          ),
                  child: const Text('Have a look'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _answer('declined'),
                  child: const Text('Not this time'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _answer('accepted'),
                  child: Text(_busy ? 'Working…' : 'We are in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String? _dates(TournamentInvite i) {
    final start = i.startDate;
    if (start == null) return null;
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}';
    final end = i.endDate;
    if (end == null ||
        (end.year == start.year &&
            end.month == start.month &&
            end.day == start.day)) {
      return '${fmt(start)}/${start.year}';
    }
    return '${fmt(start)} – ${fmt(end)}/${end.year}';
  }
}

/// "Ravi wants to score Blue House v Red House" — approve or not, from here.
///
/// Deliberately decided in place rather than behind a tap through to the
/// match. The admin is often not at the ground and the match may be starting;
/// making them navigate two screens to say yes is how a request goes
/// unanswered until after the game.
class ScoringRequestCard extends ConsumerStatefulWidget {
  const ScoringRequestCard({super.key, required this.request});

  final ScoringRequest request;

  @override
  ConsumerState<ScoringRequestCard> createState() => _ScoringRequestCardState();
}

class _ScoringRequestCardState extends ConsumerState<ScoringRequestCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    final me = ref.read(currentUidProvider);
    if (me == null || _busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(competitionRepositoryProvider);
      if (approve) {
        await repo.approveScoringRequest(
          request: widget.request,
          decidedByUid: me,
        );
      } else {
        await repo.declineScoringRequest(
          request: widget.request,
          decidedByUid: me,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? '${widget.request.displayName} can now score this match.'
                  : 'Request declined.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = widget.request;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.displayName} wants to score',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        r.matchLabel.isEmpty ? 'a match' : r.matchLabel,
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                      if (r.note != null && r.note!.isNotEmpty)
                        Text(
                          '“${r.note}”',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Wrap, not Row: "Let them score" is a long label next to a
            // second button on a 420px screen, and it has to survive both a
            // narrow phone and a reader who has turned their font size up.
            // It stacks rather than overflowing.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _decide(approve: false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _decide(approve: true),
                  child: Text(_busy ? 'Working…' : 'Let them score'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
