import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/organization.dart';
import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../features/home/home_providers.dart';
import 'identity.dart';

/// Which club a club-owned action is being performed *as*, said on the screen
/// where the action happens.
///
/// ## Why the app bar was not enough
///
/// Every org-scoped screen already passes `orgId` to [AppScaffold], which
/// prints the club's name in the caption under the wordmark — six-point text,
/// beside a title, on a bar people stop reading after the first week. That is
/// adequate for orientation and inadequate for authorship: "New event" and
/// "New event · Sunrise" look the same at a glance, and the second one is a
/// commitment. A person in three clubs who opens Create Event from the wrong
/// club's page has no signal at all until the event turns up in the wrong
/// club's calendar, at which point it has already been announced to the wrong
/// members.
///
/// So the club is stated once more, in the body, in the form the question is
/// actually asked in — *creating as who* — with the crest to recognise it by
/// and the club id to quote. It is the same fact the bar carries; the point is
/// that it is carried where the decision is made.
///
/// ## Why the id is here and not only on the club's own page
///
/// Two clubs in one district are routinely called the same thing. "Creating as
/// Sunrise Cricket Club" is ambiguous in exactly the situation where getting
/// it wrong is most likely, and [Organization.clubCodeLabel] is the only
/// identifier that is not — see [ClubIdChip] for why every member, not only an
/// admin, is given it.
///
/// ## Switching
///
/// Pass [onChanged] on a screen that can genuinely retarget — one that has not
/// written anything yet, and whose org is state rather than a route parameter.
/// The chevron then opens the person's own clubs, filtered to those where they
/// hold [requires]. Omit it and the banner is a statement, which is right for
/// a screen reached through a club's own pages: on those, changing club means
/// going back, and offering a switcher that silently re-parents a half-filled
/// form is worse than not offering one.
class ClubContextBanner extends ConsumerWidget {
  const ClubContextBanner({
    super.key,
    required this.orgId,
    this.label = 'Creating as',
    this.onChanged,
    this.requires,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  final String orgId;

  /// The relationship this screen has to the club — "Creating as" on a form
  /// that writes something new, "Managing" on one that edits what is there.
  /// Always a verb: a bare club name is orientation, and the whole point of
  /// this strip is that it is attribution.
  final String label;

  /// Non-null on a screen where picking a different club is a real choice.
  final ValueChanged<String>? onChanged;

  /// The capability a club must be held with to appear in the switcher.
  /// Null offers every club the person is an active member of.
  final Capability? requires;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;

    // Only worth a switcher if there is somewhere to switch to. A person in
    // one club offered "change club" learns that the app does not know how
    // many clubs they are in.
    final switchable = onChanged == null
        ? const <String>[]
        : _switchableOrgIds(ref, requires);
    final canSwitch = switchable.length > 1;

    final banner = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          PsCrest(
            name: org?.name ?? '?',
            logoUrl: org?.logoUrl,
            seed: orgId,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  org?.name ?? 'Loading…',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                if (org != null)
                  Text(
                    'Club ID ${org.clubCodeLabel}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),
          if (canSwitch)
            TextButton.icon(
              onPressed: () => _pick(context, ref, switchable),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Change'),
            ),
        ],
      ),
    );

    return Padding(padding: padding, child: banner);
  }

  /// The clubs this person could do this in — active membership plus, when
  /// one is named, the capability the action needs. A switcher that lists a
  /// club whose "Create event" would be refused is a dead end with a name on
  /// it.
  static List<String> _switchableOrgIds(WidgetRef ref, Capability? requires) {
    final active = ref.watch(myActiveOrgIdsProvider);
    if (requires == null) return active;
    return [
      for (final id in active)
        if (ref.watch(myCapabilitiesProvider(id)).contains(requires)) id,
    ];
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    List<String> orgIds,
  ) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                label,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final id in orgIds)
              _ClubOption(
                orgId: id,
                selected: id == orgId,
                onTap: () => Navigator.of(ctx).pop(id),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == orgId) return;
    // Picking a club here is picking the club you are acting as, so it moves
    // the app's selection too — the chip in the bar, the dashboard's buttons
    // and this form must not end up naming two different clubs. See
    // [CurrentClubController].
    ref.read(currentClubIdProvider.notifier).switchTo(chosen);
    onChanged?.call(chosen);
  }
}

class _ClubOption extends ConsumerWidget {
  const _ClubOption({
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
