import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_user.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/identity.dart';

/// The one place a profile switch is performed.
///
/// Switching profiles is not navigation — it replaces the subject of every
/// screen in the app at once — so it does three things together and always
/// in the same order: set the profile, drop whatever sheet asked for it, and
/// land on the home screen.
///
/// That last step is not cosmetic. Routes in this app are scoped to things
/// the profile in use may or may not have any right to: a club page for a
/// club only the guardian belongs to, a competition only they entered, the
/// grounds console. Staying put after a switch would leave the person
/// looking at a screen that is now a permission error. Home is the one
/// destination that is meaningful for every profile.
void switchToProfile(BuildContext context, WidgetRef ref, String? uid) {
  ref.read(actingProfileUidProvider.notifier).switchTo(uid);
  _closeAnythingModal(context);
  context.go(Routes.home);
}

/// Dismisses the account panel or the switcher sheet, if the tap came from
/// inside one, and does nothing at all if it did not.
///
/// `PopupRoute` and not `canPop()`: a sheet is a route on the same navigator
/// as the pages under it, so a blanket pop would close whichever SCREEN a
/// banner tap came from. And leaving the sheet up is not an option either —
/// `go` replaces the pages beneath a popup route without touching the popup,
/// which strands it over a screen it no longer belongs to.
void _closeAnythingModal(BuildContext context) {
  Navigator.of(context).popUntil((route) => route is! PopupRoute);
}

/// The household's profiles, side by side — the account holder first, then
/// every child they manage.
///
/// Rendered as faces rather than a menu on purpose: this is the same gesture
/// people already know from a shared television, and the profile in use is
/// identified by the one with a ring around it rather than by reading a
/// label.
///
/// Renders nothing at all for the overwhelming majority of accounts, which
/// have no child profiles — a switcher with one face on it is furniture.
class ProfileSwitcherStrip extends ConsumerWidget {
  const ProfileSwitcherStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(switchableProfilesProvider);
    if (children.isEmpty) return const SizedBox.shrink();

    final me = ref.watch(authUserProvider).valueOrNull;
    final activeUid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who is playing?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _ProfileFace(
                name: me?.displayName ?? 'Me',
                photoUrl: me?.photoUrl,
                uid: me?.uid,
                selected: activeUid != null && activeUid == me?.uid,
                onTap: () => switchToProfile(context, ref, null),
              ),
              for (final child in children)
                _ProfileFace(
                  name: child.displayName,
                  photoUrl: child.photoUrl,
                  uid: child.uid,
                  selected: activeUid == child.uid,
                  onTap: () => switchToProfile(context, ref, child.uid),
                ),
              // Onboarding another child is the account holder's to do, so
              // it is absent from a child's own view of the household — the
              // same line the drawer's `accountOnly` entries draw.
              if (!ref.watch(isActingAsChildProvider))
                _AddProfileFace(
                  onTap: () {
                    _closeAnythingModal(context);
                    context.push(Routes.addChild);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _ProfileFace extends StatelessWidget {
  const _ProfileFace({
    required this.name,
    required this.photoUrl,
    required this.uid,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String? photoUrl;
  final String? uid;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    // The ring is the whole state indicator, so it has to be
                    // present at the same thickness either way — a border
                    // that appears only when selected shifts every face
                    // beside it by six pixels the moment one is tapped.
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: PsAvatar(name: name, photoUrl: photoUrl, seed: uid, size: 52),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProfileFace extends StatelessWidget {
  const _AddProfileFace({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                ),
                child: Icon(Icons.add, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                'Add child',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The switcher on its own, for the places that reach it from a banner or a
/// long press rather than from inside the account panel.
Future<void> showProfileSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [ProfileSwitcherStrip()],
      ),
    ),
  );
}

/// A one-line description of the profile in use, for a header that has room
/// for it. Null when the account holder is using their own profile, which is
/// the case that needs no explaining.
String? actingProfileCaption(AppUser? acting, bool isActingAsChild) {
  if (!isActingAsChild || acting == null) return null;
  return "You're in ${acting.displayName}'s profile";
}
