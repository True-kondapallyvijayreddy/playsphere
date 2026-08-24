import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_user.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

/// A guardian's list of the children they've created a profile for — both
/// still-managed and already claimed onto the child's own device.
///
/// Claiming does not remove a child from this list. `custodianUid` is a
/// permanent read grant (see the `users/{userId}` read rule in
/// firestore.rules), so a guardian keeps visibility into a claimed child's
/// matches and stats from here even after the child is fully independent —
/// they just can no longer edit the profile from this screen.
class ManagedChildrenScreen extends ConsumerWidget {
  const ManagedChildrenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = ref.watch(myManagedChildrenProvider);

    return AppScaffold(
      title: 'My Children',
      body: childrenAsync.when(
        data: (children) => _Body(children: children),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addChild),
        icon: const Icon(Icons.add),
        label: const Text('Add a child'),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.children});

  final List<AppUser> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      final hint = Theme.of(context).hintColor;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.family_restroom, size: 56, color: hint),
              const SizedBox(height: 16),
              Text(
                'No children added yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                "Create a profile for a child who doesn't have their own "
                'phone yet. They can join teams and be scored right away — '
                'and claim the profile onto their own phone later.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: hint),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final child = children[i];
        return Card(
          child: ListTile(
            leading: PsAvatar(
              name: child.displayName,
              photoUrl: child.photoUrl,
              seed: child.uid,
            ),
            title: Text(child.displayName),
            subtitle: Text(
              child.isManaged
                  ? 'Not yet claimed — you manage this profile'
                  : 'Claimed — signed in on their own device',
            ),
            trailing: child.isManaged
                ? FilledButton.tonal(
                    onPressed: () =>
                        context.push(Routes.claimCodeFor(child.uid)),
                    child: const Text('Get code'),
                  )
                : Icon(Icons.check_circle, color: Colors.green.shade600),
            onTap: () => context.push(Routes.profile(child.uid)),
          ),
        );
      },
    );
  }
}
