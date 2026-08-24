import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_exception.dart';
import '../core/models/app_user.dart';
import '../core/models/enums.dart';
import '../core/models/organization.dart';
import 'club_id_chip.dart';
import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/settings/language_picker.dart';
import 'app_scaffold.dart';
import 'identity.dart';
import 'invite_card.dart';
import 'playsphere_logo.dart';

/// The avatar at the top right of every signed-in screen.
///
/// Opens a panel rather than a popup menu of four items. A popup menu could
/// only ever be a list of destinations, and the thing a person wants when they
/// tap their own face is *their own details* — who the app thinks they are,
/// which clubs they belong to, and what their record adds up to. Those answers
/// are what this panel leads with; the destinations follow underneath.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return IconButton(
      tooltip: 'You and your clubs',
      onPressed: () => showAccountPanel(context),
      icon: UserAvatar(user: user, radius: 16),
    );
  }
}

/// A person's picture, or the first letter of their name when there is none.
///
/// Extracted because the same fallback is needed in the app bar, the account
/// panel and the drawer header, and three slightly different versions of
/// "what do we show when Google gave us no photo" is how avatars end up
/// inconsistent.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 20});

  final AppUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // Kept as a named widget rather than replaced outright: it is referenced
    // from the app bar, the account panel and the drawer, and `radius` is the
    // vocabulary those call sites already speak. It is now a thin wrapper —
    // the drawing itself is [PsAvatar]'s, so this face matches every other
    // face in the app.
    return PsAvatar(
      name: user?.displayName ?? '?',
      photoUrl: user?.photoUrl,
      seed: user?.uid,
      size: radius * 2,
    );
  }
}

/// Shows the account panel as a sheet on a phone and a side panel on a laptop.
Future<void> showAccountPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _AccountPanel(),
  );
}

class _AccountPanel extends ConsumerWidget {
  const _AccountPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.valueOrNull;
    final uid = ref.watch(currentUidProvider);
    final memberships = ref.watch(myMembershipsProvider);
    final career = uid == null ? null : ref.watch(careerProvider(uid));
    final memories = uid == null ? null : ref.watch(playerMemoriesProvider(uid));

    final lines = career?.valueOrNull ?? const [];
    final active =
        (memberships.valueOrNull ?? const []).where((m) => m.isActive).toList();
    final pending =
        (memberships.valueOrNull ?? const []).where((m) => m.isPending).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          // --- Who you are -------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(user: user, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Signed in',
                      style: theme.textTheme.titleLarge,
                    ),
                    if (user?.email.isNotEmpty ?? false)
                      Text(
                        user!.email,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // `.filledTonal` rather than a bare IconButton: a bare one
              // takes its color from the ambient IconTheme, which in this
              // sheet resolves to something barely distinguishable from the
              // sheet's own white background. The tonal variant carries its
              // own container color from the scheme, so it reads clearly
              // regardless of what's behind it.
              IconButton.filledTonal(
                tooltip: 'Edit your details',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.profileSetup);
                },
              ),
              const SizedBox(width: 8),
              // Right beside the name rather than buried in the list below —
              // onboarding a child with no device of their own yet is a task
              // a guardian starts the moment they open their own profile, not
              // something they should have to scroll to find.
              IconButton.filledTonal(
                tooltip: 'Add a child',
                icon: const Icon(Icons.person_add_alt_1),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.addChild);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (user != null) _DetailChips(user: user),
          const SizedBox(height: 18),

          // --- What it adds up to -------------------------------------------
          Row(
            children: [
              _MiniStat(label: 'Clubs', value: '${active.length}'),
              _MiniStat(
                label: 'Matches',
                value: '${lines.fold<int>(0, (s, l) => s + l.matchesPlayed)}',
              ),
              _MiniStat(
                label: 'Sports',
                value: '${lines.where((l) => l.matchesPlayed > 0).length}',
              ),
              _MiniStat(
                label: 'Memories',
                value: '${(memories?.valueOrNull ?? const []).length}',
              ),
            ],
          ),
          const SizedBox(height: 18),

          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(Routes.myProfile);
            },
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Open my full career profile'),
          ),
          const SizedBox(height: 24),

          // --- The clubs you belong to --------------------------------------
          Row(
            children: [
              Expanded(
                child: Text('My clubs', style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.orgs);
                },
                child: const Text('Manage'),
              ),
            ],
          ),
          AsyncErrorStrip(value: memberships, what: 'your clubs'),
          if (memberships.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (active.isEmpty && pending.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('You have not joined a club yet'),
                subtitle: const Text(
                  'Join your school, college or community with an invite code '
                  '— your record follows you between all of them.',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(Routes.joinOrg);
                },
              ),
            )
          else ...[
            for (final m in active)
              _ClubRow(orgId: m.orgId, role: m.role, joinedAt: m.joinedAt),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Waiting for approval', style: theme.textTheme.labelLarge),
              for (final m in pending)
                _ClubRow(orgId: m.orgId, role: m.role, pending: true),
            ],
          ],
          const SizedBox(height: 20),

          // --- Everything else ----------------------------------------------
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.translate),
            title: const Text('Language / భాష / भाषा'),
            onTap: () async {
              Navigator.of(context).pop();
              await showLanguagePicker(context);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Switch club'),
            onTap: () {
              Navigator.of(context).pop();
              context.push(Routes.orgs);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.family_restroom),
            title: const Text('My children'),
            onTap: () {
              Navigator.of(context).pop();
              context.push(Routes.myChildren);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () async {
              Navigator.of(context).pop();
              await ref.read(authServiceProvider).signOut();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_outlined,
                color: theme.colorScheme.error),
            title: Text('Delete account',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () async {
              Navigator.of(context).pop();
              await _confirmAndDeleteAccount(context, ref);
            },
          ),
          const SizedBox(height: 12),
          const Center(child: PlaySphereLogo(markSize: 20, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Confirms, then deletes the caller's own sign-in — [AuthService.
/// deleteAccount] — retrying once through a fresh Google sign-in if
/// Firebase refuses because the session isn't recent enough.
///
/// Deliberately does not attempt to delete the `users/{uid}` document
/// itself: `firestore.rules` refuses that unconditionally
/// (`allow delete: if false`) for every account, by design — match results
/// and club records stay intact for everyone else's history even after a
/// player's own login is gone. This is why the confirmation copy below says
/// so plainly, rather than implying the account vanishes without a trace.
Future<void> _confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(
        "This removes your PlaySphere sign-in for good — you won't be able "
        'to open this account again, and signing in again with the same '
        'Google account starts a brand new, empty profile. Your existing '
        "matches, stats and club records stay on file (they're part of "
        "other people's history too), just no longer reachable from any "
        'account of yours.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete account'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final auth = ref.read(authServiceProvider);
  try {
    await auth.deleteAccount();
    // Nothing to navigate here — authStateProvider goes null the instant
    // this succeeds, and the router's own redirect sends the (now
    // signed-out) session to Routes.signIn on its own.
  } on ReauthenticationRequiredException {
    if (!context.mounted) return;
    showError(context, const ReauthenticationRequiredException());
    try {
      // The Google chooser IS the "sign in again" Firebase is asking for —
      // a fresh credential resets what "recent" means for this session.
      await auth.signInWithGoogle();
      await auth.deleteAccount();
    } on AuthCancelledException {
      // Backed out of the chooser; the account is untouched, say nothing.
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// The facts the app holds about a person, as chips.
///
/// Age rather than date of birth, deliberately — the same rule the public
/// profile follows. A minor's exact birth date is not something a screen needs
/// to render, and the band is the only part any eligibility check uses.
class _DetailChips extends StatelessWidget {
  const _DetailChips({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final geo = user.geo;
    final place = [
      geo.village,
      geo.mandal,
      geo.district,
      geo.state,
    ].where((p) => p != null && p.isNotEmpty).join(', ');

    Widget chip(IconData icon, String label) => Chip(
          avatar: Icon(icon, size: 15),
          label: Text(label),
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        );

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        chip(Icons.cake_outlined, '${user.ageAt(DateTime.now())} yrs'),
        chip(Icons.person_outline, user.gender.label),
        if (place.isNotEmpty) chip(Icons.place_outlined, place),
        if (user.phone != null && user.phone!.isNotEmpty)
          chip(Icons.phone_outlined, user.phone!),
        chip(Icons.visibility_outlined, user.profileVisibility.label),
        if (user.isMinor) chip(Icons.shield_outlined, 'Junior — protected'),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleLarge),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ClubRow extends ConsumerWidget {
  const _ClubRow({
    required this.orgId,
    required this.role,
    this.joinedAt,
    this.pending = false,
  });

  final String orgId;
  final MembershipRole role;
  final DateTime? joinedAt;
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Organization? org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final live = ref.watch(liveFixturesProvider(orgId)).valueOrNull ?? const [];
    // Only admins/owners get a door to hand out — same rule as the Members
    // screen's invite card, so a regular member never sees a code they
    // couldn't already find by opening the club.
    final canManage = !pending &&
        ref.watch(myCapabilitiesProvider(orgId)).contains(Capability.manageMembers);

    return Column(
      children: [
        Card(
          margin: EdgeInsets.only(bottom: canManage ? 0 : 8),
          shape: canManage
              ? const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                )
              : null,
          child: ListTile(
            leading: PsCrest(
              name: org?.name ?? '?',
              logoUrl: org?.logoUrl,
              seed: org?.id,
              size: 40,
            ),
            // The club's id sits beside its name, for every member and not
            // just the ones who can administer it — see [ClubIdChip] for why
            // an ordinary member is exactly who needs it.
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    org?.name ?? 'Loading…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (org != null) ...[
                  const SizedBox(width: 8),
                  ClubIdChip(org: org, compact: true),
                ],
              ],
            ),
            subtitle: Text(
              pending
                  ? 'Waiting for an admin to approve you'
                  : [
                      org?.orgType.label,
                      role.label,
                      if (org != null) '${org.memberCount} members',
                    ].whereType<String>().join(' · '),
            ),
            trailing: pending
                ? const Icon(Icons.hourglass_empty, size: 20)
                : live.isEmpty
                    ? const Icon(Icons.chevron_right)
                    : Chip(
                        label: Text('${live.length} live'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: const Color(0xFFDC2626),
                        labelStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
            enabled: !pending,
            onTap: pending
                ? null
                : () {
                    Navigator.of(context).pop();
                    context.push(Routes.org(orgId));
                  },
          ),
        ),
        // The join key and QR live right under the club they open — an
        // admin scrolling their own "My clubs" list shouldn't have to go
        // find the Members screen just to hand someone the door in.
        if (canManage && org != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InviteCard(org: org),
          )
        // Everybody else gets the half of that card which opens the club
        // rather than joining it: its id, copyable and shareable. Promoting
        // the club you play for should not require permission to run it.
        else if (org != null && !pending)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
              child: Row(
                children: [
                  Expanded(child: ClubIdChip(org: org)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
