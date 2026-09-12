import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/home/home_providers.dart';
import 'identity.dart';

/// Which club the person is in, said in the chrome and changeable there.
///
/// ## The problem this closes
///
/// PlaySphere is used from inside one club at a time, and until this existed
/// the app never said which one. The selection was implicit — the most
/// recently joined club, chosen for you, invisible — and the only way to work
/// as a different club was to navigate into that club's page and stay inside
/// it. A player in a school team and a weekend academy had no way to tell,
/// from the dashboard, whose live matches they were looking at.
///
/// So the club is now stated in exactly one place — [ClubChip], in the app
/// bar beside the notification bell — and it is on every screen, it never
/// moves, and it reads the same everywhere because it names the SELECTION
/// rather than whatever screen you happen to be on. Tapping it switches, from
/// anywhere, without a trip to a club page.
///
/// One place, deliberately. The dashboard briefly carried a second copy as a
/// strip under the hero; two controls for one fact on the one screen where
/// the bar is already visible is a duplicate, not an emphasis.
///
/// See [CurrentClubController] for what is remembered and what it falls back
/// to when nothing has been chosen.

/// Opens the club picker. Returns the club chosen, or null if dismissed.
///
/// Also the join door: a person with one club — or none at all — still gets
/// the sheet, because "I am not in the club I want" and "I want a different
/// club" are the same impulse and the answer to both is at the bottom of this
/// list.
Future<String?> showClubSwitcher(
  BuildContext context,
  WidgetRef ref, {
  String? selectedOrgId,
}) async {
  final orgIds = ref.read(myActiveOrgIdsProvider);
  final current = selectedOrgId ?? ref.read(currentClubIdProvider);

  final chosen = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Your club',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              orgIds.isEmpty
                  ? 'You have not joined a club yet.'
                  : 'Everything you start — matches, events, live scores — '
                      'happens as this club.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          for (final id in orgIds)
            _ClubTile(
              orgId: id,
              selected: id == current,
              onTap: () => Navigator.of(ctx).pop(id),
            ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text(orgIds.isEmpty ? 'Join a club' : 'Join another club'),
            subtitle: const Text('With a club code, or find one near you'),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push(Routes.orgs);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );

  if (chosen == null) return null;
  ref.read(currentClubIdProvider.notifier).switchTo(chosen);
  return chosen;
}

class _ClubTile extends ConsumerWidget {
  const _ClubTile({
    required this.orgId,
    required this.selected,
    required this.onTap,
  });

  final String orgId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    return ListTile(
      leading: PsCrest(
        name: org?.name ?? '?',
        logoUrl: org?.logoUrl,
        seed: orgId,
        size: 36,
      ),
      title: Text(org?.name ?? 'Loading…', overflow: TextOverflow.ellipsis),
      subtitle: org == null ? null : Text('Club ID ${org.clubCodeLabel}'),
      trailing: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// The club, in the app bar, immediately left of the notification bell.
///
/// Deliberately the narrowest thing that can carry a name: crest, name, and a
/// chevron that says it is a control rather than a label. The name is capped
/// and ellipsized because an app bar that a long club name pushes the bell
/// out of is worse than one that says "Sunrise Cricket A…".
///
/// ## It shows the SELECTION, never the screen
///
/// This first shipped showing the screen's own club on a club-owned page and
/// the standing selection everywhere else, on the theory that two club names
/// in one bar would be a puzzle. It was worse: the chip changed as you walked
/// around, so the one element that was supposed to answer "which club am I
/// acting as" gave a different answer on the dashboard than three taps in,
/// and neither answer was checkable against the other.
///
/// So it is the selection, on every screen, and nothing about where you have
/// navigated moves it. The club a screen BELONGS to is already named in the
/// caption under the wordmark — that is what you are reading; this is who you
/// are. Switching changes it for the whole app at once, which is the only
/// behaviour that makes a persistent chip worth having.
///
/// Switching from a club-owned screen also takes you to the club you picked:
/// there, leaving the bar and the body disagreeing would reintroduce exactly
/// the confusion above. From the person's own screens the selection alone is
/// the whole effect.
///
/// A brand-new account belongs to no club, and this says so rather than
/// inventing one: "No club", tapping through to where you join.
class ClubChip extends ConsumerWidget {
  const ClubChip({super.key, this.orgId});

  /// The club the screen underneath belongs to, when it belongs to one.
  ///
  /// Never displayed — see the note above. It decides one thing only: whether
  /// switching should also navigate.
  final String? orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(currentClubIdProvider);
    final org =
        shown == null ? null : ref.watch(organizationProvider(shown)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    Future<void> open() async {
      final chosen = await showClubSwitcher(context, ref, selectedOrgId: shown);
      if (chosen == null || chosen == shown) return;
      // Only when the screen underneath is about a club. On home, More or the
      // profile there is nothing to navigate to — the selection alone is the
      // whole effect, and pushing a club page over the dashboard would make
      // "switch club" feel like leaving.
      if (orgId != null && context.mounted) context.go(Routes.org(chosen));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 6, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shown == null)
                  Icon(Icons.groups_2_outlined,
                      size: 20, color: scheme.onSurfaceVariant)
                else
                  PsCrest(
                    name: org?.name ?? '?',
                    logoUrl: org?.logoUrl,
                    seed: shown,
                    size: 22,
                  ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(
                    shown == null ? 'No club' : (org?.name ?? '…'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: shown == null ? scheme.onSurfaceVariant : null,
                        ),
                  ),
                ),
                Icon(Icons.expand_more,
                    size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
