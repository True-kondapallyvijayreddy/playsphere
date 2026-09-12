import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/locale_controller.dart';
import '../core/models/app_user.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/family/profile_switcher.dart';
import '../features/profile/widgets/level_board.dart';
import '../features/settings/language_picker.dart';
import 'app_scaffold.dart';
import 'file_download.dart';
import 'identity.dart';
import 'playsphere_logo.dart';

/// The avatar at the top right of every signed-in screen.
///
/// Opens a panel rather than a popup menu of four items. A popup menu could
/// only ever be a list of destinations, and the thing a person wants when they
/// tap their own face is *their own standing* — who the app thinks they are
/// and what their record adds up to. Those answers are what this panel leads
/// with; the destinations follow underneath.
///
/// ## Why the club list is not here any more
///
/// It was the same list, twice. "My clubs" is a first-class destination — its
/// own bottom-bar tab, its own screen, with the invite code and QR beside each
/// club name — and reproducing it inside the account sheet meant a member's
/// clubs were maintained in two places and read differently in each. The
/// panel is about the PERSON now; the clubs are one tap away through "Switch
/// club" below and through the tab that is always on screen.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return IconButton(
      tooltip: 'Your profile',
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
    final user = ref.watch(currentUserProvider).valueOrNull;
    final uid = ref.watch(currentUidProvider);
    // Everything above is about the PROFILE in use. The entries further down
    // that are about the ACCOUNT — onboarding another child, deleting the
    // account — are hidden while a child's profile is open: they are not that
    // profile's to reach, and offering them there would attach the guardian's
    // account to a screen that says somebody else's name at the top.
    final isChildProfile = ref.watch(isActingAsChildProvider);

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
                    if (isChildProfile)
                      Text(
                        'Managed profile',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (user?.email.isNotEmpty ?? false)
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
              if (!isChildProfile) ...[
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
            ],
          ),
          const SizedBox(height: 12),

          if (user != null) _DetailChips(user: user),
          const SizedBox(height: 18),

          // The household, if there is one. Placed above the stats rather
          // than in the list of destinations at the bottom: on a shared
          // phone "whose app is this" is the first question the panel
          // answers, and everything below it is an answer about that person.
          const ProfileSwitcherStrip(),

          // --- What it adds up to -------------------------------------------
          // The level, the bar to the next one, and the numbers behind them.
          // This replaced a four-cell strip whose first cell was a club count
          // — a fact about the person's clubs, on a panel that is about the
          // person. See [PersonalLevelBoard].
          if (uid != null) PersonalLevelBoard(uid: uid),
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

          // --- Everything else ----------------------------------------------
          const Divider(),
          // The language row only exists when there is a choice to make.
          //
          // It used to be unconditional, offering తెలుగు and हिंदी on the
          // strength of seventy translated keys that reached three of two
          // hundred and thirty-three feature screens. Somebody picked Telugu,
          // saw the sign-in screen change, and then used an English app.
          // `supportedLocales` is English-only until the strings are actually
          // extracted; when a second locale returns, so does this row, with
          // no change here.
          if (supportedLocales.length > 1)
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
          if (isChildProfile)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.switch_account_outlined),
              title: Text(
                'Back to ${ref.watch(authUserProvider).valueOrNull?.displayName ?? 'my profile'}',
              ),
              onTap: () => switchToProfile(context, ref, null),
            )
          else ...[
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
                // Anything a shared link asked us to open belongs to the
                // person who was signed in. The next person on this phone
                // must not inherit it.
                PendingDestination.forget();
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
            // Above the delete row on purpose. Somebody who has decided to
            // leave should be offered their record on the way out, next to the
            // button that destroys it, rather than having to find it in a
            // different menu after the fact.
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Download my data'),
              subtitle: const Text('Everything PlaySphere holds, as a file'),
              onTap: () async {
                Navigator.of(context).pop();
                await _exportMyData(context, ref);
              },
            ),
          ],
          const SizedBox(height: 12),
          const Center(child: PlaySphereLogo(markSize: 20, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Produces the account's data export and hands it to the share sheet.
///
/// The right of access, self-service. The privacy policy promised a
/// machine-readable copy on request and nothing implemented it, so the promise
/// rested on somebody running queries against production by hand.
///
/// Deliberately blocking with a visible spinner rather than optimistic: the
/// server walks a dozen collections and collection-group queries, which takes
/// a second or two, and a share sheet that appears with no warning after an
/// unexplained pause reads as a bug.
Future<void> _exportMyData(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Gathering your data…'),
      duration: Duration(seconds: 8),
    ),
  );
  try {
    final bytes = await ref.read(authServiceProvider).exportMyData();
    messenger.hideCurrentSnackBar();
    await saveFileBytes(
      bytes: bytes,
      // Dated, because somebody who asks twice wants to be able to tell the
      // two files apart.
      filename: 'playsphere-my-data-'
          '${DateTime.now().toIso8601String().split('T').first}.json',
      mimeType: 'application/json',
      shareText: 'My PlaySphere data',
    );
  } catch (e) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) showError(context, e);
  }
}

/// Confirms, then erases the account — [AuthService.deleteAccount], which
/// hands both halves to `deleteMyAccount` on the server.
///
/// The `users/{uid}` document is scrubbed rather than deleted, and the copy
/// below says exactly that. `firestore.rules` refuses to delete it for
/// anybody, by design: match results, scorecards and club rosters all point at
/// this uid, and they are other people's records as much as this person's. So
/// the identifiers go — name, email, phone, photo, place — and the skeleton
/// stays behind the matches that need it.
///
/// No re-authentication retry any more: the server deletes the Auth user with
/// Admin privileges, so "requires a recent sign-in" cannot arise.
Future<void> _confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(
        "This removes your PlaySphere sign-in for good — you won't be able "
        'to open this account again, and signing in again with the same '
        'Google account starts a brand new, empty profile.\n\n'
        'Erased: your name, email, phone number, photo and location; your '
        'notification tokens; your entry in the player directory; any coach, '
        'practitioner, shop or official listing you published; your ground '
        'check-ins; the photos you uploaded; and the documents you sent us to '
        'verify a ground.\n\n'
        "Kept: your past matches, stats and club records — they're part of "
        "other people's history too — with your name removed from the "
        'profile behind them. Payment receipts are kept as a financial '
        'record.\n\n'
        'Want a copy first? Close this and tap “Download my data”.',
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
  } catch (e) {
    // Includes the one refusal worth reading: an account still managing a
    // child profile has to hand it over first, and the server's message says
    // which step does that.
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
