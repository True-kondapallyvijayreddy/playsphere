import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/membership_application.dart';
import '../../../core/models/organization.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';
import '../../../shared/ui_kit.dart';

/// Who is asking to join, before the club answers.
///
/// ## The gap this closes
///
/// The approval queue used to be a name, a photo and two icon buttons. An
/// admin was being asked to admit somebody they knew nothing about, which in
/// practice produced one of two behaviours: approve everything without
/// looking, or never open the queue at all. Neither is a decision.
///
/// So the sheet shows, in order, the three things a club actually decides on:
/// what they play, roughly how old they are, and where they are — followed by
/// whatever they said for themselves. All of it travels on the membership
/// document as a [MembershipApplication], written by the applicant when they
/// applied, so it renders for a thirteen-year-old and for somebody whose
/// profile is private, neither of whom a club may read directly.
///
/// ## And the live profile, where the rules allow it
///
/// "Open full profile" is offered as well, and is honest about being a
/// separate thing. `firestore.rules` decides whether it opens: an adult
/// applicant's profile is readable by this club's owners and admins for as
/// long as the application is outstanding (see `AppUser.pendingOrgIds`), a
/// junior's is not without guardian consent. Where it is refused the profile
/// screen says so in its own words, which is better than this sheet guessing
/// in advance and hiding a button that would have worked.
class ApplicantReviewSheet extends ConsumerWidget {
  const ApplicantReviewSheet({
    super.key,
    required this.orgId,
    required this.member,
    required this.canManage,
  });

  final String orgId;
  final Membership member;

  /// False for an ordinary member who reached this from the roster: they see
  /// who is waiting, they do not get the buttons.
  final bool canManage;

  static Future<void> show(
    BuildContext context, {
    required String orgId,
    required Membership member,
    required bool canManage,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => ApplicantReviewSheet(
          orgId: orgId,
          member: member,
          canManage: canManage,
        ),
      );

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    MembershipStatus status,
  ) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    try {
      await ref.read(orgRepositoryProvider).decideMembership(
            orgId: orgId,
            uid: member.uid,
            status: status,
            decidedByUid: uid,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == MembershipStatus.active
                ? '${member.displayName} is now a member.'
                : '${member.displayName}’s request was declined.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final app = member.application;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            children: [
              PsAvatar(
                name: member.displayName,
                photoUrl: member.photoUrl,
                seed: member.uid,
                size: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Wants to join',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          _Facts(application: app),

          if (app.note != null && app.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('In their words', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(app.note!, style: theme.textTheme.bodyMedium),
            ),
          ],

          if (app.sports.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Sports played', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final s in app.sports) _SportLine(sport: s),
          ],

          if (app.isEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'This person applied before introductions existed, or chose to '
              'send none. Their profile below may say more.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(Routes.profile(member.uid));
            },
            icon: const Icon(Icons.person_outline),
            label: const Text('Open full profile'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),

          if (canManage) ...[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _decide(context, ref, MembershipStatus.active),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => _decide(context, ref, MembershipStatus.removed),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Decline'),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Declining keeps their row so they can apply again — it is not a '
              'ban.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// Age, gender, place and code, as chips.
///
/// The age is rendered "as of" its submission date rather than as a live
/// number, because it IS a stored number — the reviewer cannot read a birth
/// date, and a stored age that quietly ages a year is the kind of small lie
/// that makes an eligibility check wrong later.
class _Facts extends StatelessWidget {
  const _Facts({required this.application});

  final MembershipApplication application;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[];

    Widget chip(IconData icon, String label) => Chip(
          avatar: Icon(icon, size: 15),
          label: Text(label),
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        );

    final age = application.ageYears;
    if (age != null) chips.add(chip(Icons.cake_outlined, '$age yrs'));

    final gender = application.gender;
    if (gender != null && gender != Gender.preferNotToSay) {
      chips.add(chip(Icons.person_outline, gender.label));
    }

    final place = application.locationLabel;
    if (place != null && place.isNotEmpty) {
      chips.add(chip(Icons.place_outlined, place));
    }

    final code = application.playerCode;
    if (code != null) chips.add(chip(Icons.badge_outlined, code));

    final total = application.totalMatches;
    if (total > 0) {
      chips.add(chip(Icons.sports_score_outlined, '$total matches'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    final at = application.submittedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 6, children: chips),
        if (at != null && age != null) ...[
          const SizedBox(height: 8),
          Text(
            'As stated when they applied on ${_shortDate(at)}.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ],
    );
  }

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _SportLine extends StatelessWidget {
  const _SportLine({required this.sport});

  final ApplicantSport sport;

  @override
  Widget build(BuildContext context) {
    final spec = SportCatalog.byId(sport.sportId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SportBadge(sportId: spec.id, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Text(spec.name)),
          Text(
            sport.matchesPlayed == 1
                ? '1 match'
                : '${sport.matchesPlayed} matches',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Builds the introduction that travels with a join request.
///
/// Lives beside the sheet that reads it so the two halves of the contract are
/// one file apart, not one folder apart. It reads only what the applicant
/// already has open on their own device — their profile and their own career
/// record — and never fetches anything on their behalf.
MembershipApplication buildApplication({
  required AppUser user,
  required List<ApplicantSport> sports,
  String? note,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final trimmed = note?.trim();
  return MembershipApplication(
    note: trimmed == null || trimmed.isEmpty
        ? null
        : (trimmed.length > MembershipApplication.maxNoteLength
            ? trimmed.substring(0, MembershipApplication.maxNoteLength)
            : trimmed),
    ageYears: user.ageAt(at),
    gender: user.gender,
    // The coarse half only. A club deciding whether to admit somebody needs
    // the district, never the village they live in.
    locationLabel:
        user.geo.areaLabel.isEmpty ? null : user.geo.areaLabel,
    playerCode: user.playerCode,
    sports: sports,
    submittedAt: at,
  );
}
