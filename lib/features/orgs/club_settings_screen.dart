import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/ground.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Where a club manages the things about itself that change slowly, starting
/// with its home ground.
///
/// The club's own ground is set here, not at creation, and can be changed
/// again at any point — a lease ends, a school gets a new court, a village
/// team finally gets its own maidan. Nothing about it is a one-time choice.
class ClubSettingsScreen extends ConsumerWidget {
  const ClubSettingsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final canManageStaff = caps.contains(Capability.manageMembers);
    final members = ref.watch(orgMembersProvider(orgId)).valueOrNull;
    final staffCount = members
        ?.where((m) =>
            m.isActive &&
            (m.role != MembershipRole.member || m.portfolios.isNotEmpty))
        .length;

    return AppScaffold(
      orgId: orgId,
      title: 'Club settings',
      body: org == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                ContentBounds(
                  maxWidth: 700,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canManageStaff) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Club details',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          child: ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: Text(org.name),
                            subtitle: Text([
                              org.visibility == OrgVisibility.public
                                  ? 'Public'
                                  : 'Unlisted',
                              org.requiresApprovalToJoin
                                  ? 'joining needs approval'
                                  : 'anyone may join',
                              if ((org.city ?? '').isNotEmpty) org.city!,
                            ].join(' · ')),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              useSafeArea: true,
                              builder: (_) => _ClubDetailsSheet(
                                org: org,
                                isOwner: caps
                                    .contains(Capability.manageOrganization),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                      // First, because it is the setting an owner comes here
                      // to change most often and the one that decides who can
                      // change everything else.
                      if (canManageStaff) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'People',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "You don't have to run ${org.name} on your own. "
                            'Make someone an admin, or put one person in '
                            'charge of the money and another in charge of the '
                            'ground.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          child: ListTile(
                            leading: const Icon(Icons.workspace_premium_outlined),
                            title: const Text('Staff & roles'),
                            subtitle: Text(
                              staffCount == null
                                  ? 'Admins, and who looks after what'
                                  : '$staffCount running the club · '
                                      'admins, departments, umpires',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.push(Routes.clubStaff(orgId)),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Home ground',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "Where ${org.name}'s matches are actually played. "
                          'Shown on the club profile — change it whenever it '
                          'changes.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        child: org.hasHomeGround
                            ? ListTile(
                                leading: const Icon(Icons.stadium_outlined),
                                title: Text(
                                  org.homeGroundName ?? 'Home ground',
                                ),
                                subtitle: org.homeGroundId != null
                                    ? const Text('Registered on PlaySphere')
                                    : const Text('Added by the club'),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (org.homeGroundId != null)
                                      IconButton(
                                        tooltip: 'View ground',
                                        icon: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onPressed: () => context.push(
                                          Routes.ground(org.homeGroundId!),
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'Change',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _pickHomeGround(context, ref, org),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove',
                                      icon: const Icon(Icons.close),
                                      onPressed: () => ref
                                          .read(orgRepositoryProvider)
                                          .setHomeGround(orgId),
                                    ),
                                  ],
                                ),
                              )
                            : ListTile(
                                leading: const Icon(
                                  Icons.add_location_alt_outlined,
                                ),
                                title: const Text('No home ground set'),
                                subtitle: const Text(
                                  'Add the ground this club plays at',
                                ),
                                trailing: FilledButton.tonal(
                                  onPressed: () =>
                                      _pickHomeGround(context, ref, org),
                                  child: const Text('Add'),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _pickHomeGround(
    BuildContext context,
    WidgetRef ref,
    Organization org,
  ) async {
    final result = await showModalBottomSheet<_HomeGroundChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _HomeGroundPicker(
          scrollController: controller,
          initialCity: org.city,
        ),
      ),
    );
    if (result == null) return;
    try {
      await ref.read(orgRepositoryProvider).setHomeGround(
            orgId,
            groundId: result.groundId,
            groundName: result.groundName,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Editing a club's name and how people find and join it.
///
/// Visibility is shown to everybody who can open this sheet and editable by the
/// owner alone — it decides who can read the whole club, which the rules keep
/// out of an admin's hands.
class _ClubDetailsSheet extends ConsumerStatefulWidget {
  const _ClubDetailsSheet({required this.org, required this.isOwner});

  final Organization org;
  final bool isOwner;

  @override
  ConsumerState<_ClubDetailsSheet> createState() => _ClubDetailsSheetState();
}

class _ClubDetailsSheetState extends ConsumerState<_ClubDetailsSheet> {
  late final _name = TextEditingController(text: widget.org.name);
  late final _description =
      TextEditingController(text: widget.org.description ?? '');
  late final _city = TextEditingController(text: widget.org.city ?? '');
  late final _district = TextEditingController(text: widget.org.district ?? '');
  late bool _approval = widget.org.requiresApprovalToJoin;
  late bool _public = widget.org.visibility == OrgVisibility.public;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _district.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(orgRepositoryProvider);
    try {
      await repo.updateOrganization(widget.org.copyWith(
        name: _name.text.trim(),
        description: _description.text.trim(),
        city: _city.text.trim(),
        district: _district.text.trim(),
        requiresApprovalToJoin: _approval,
      ));
      final visibility = _public ? OrgVisibility.public : OrgVisibility.unlisted;
      if (widget.isOwner && visibility != widget.org.visibility) {
        await repo.setVisibility(widget.org.id, visibility);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Club details', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Club name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'About the club',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City or town',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _district,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'District',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _approval,
            onChanged: (v) => setState(() => _approval = v),
            title: const Text('Approve people before they join'),
            subtitle: const Text(
              'Off lets anyone with the club link or code join straight away '
              '(public clubs only).',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _public,
            onChanged: widget.isOwner ? (v) => setState(() => _public = v) : null,
            title: const Text('Listed publicly'),
            subtitle: Text(
              widget.isOwner
                  ? 'Public clubs appear in search, and their seasons, scores '
                      'and invitations can be opened by anyone.'
                  : 'Only the owner can change who can find the club.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _HomeGroundChoice {
  const _HomeGroundChoice({this.groundId, required this.groundName});
  final String? groundId;
  final String groundName;
}

/// Search PlaySphere's ground marketplace, or fall back to a plain name —
/// most village and school grounds will never be a marketplace listing, and
/// a picker that cannot say "our own ground, School Playground" is a picker
/// nobody outside a city can actually use.
class _HomeGroundPicker extends ConsumerStatefulWidget {
  const _HomeGroundPicker({required this.scrollController, this.initialCity});

  final ScrollController scrollController;
  final String? initialCity;

  @override
  ConsumerState<_HomeGroundPicker> createState() => _HomeGroundPickerState();
}

class _HomeGroundPickerState extends ConsumerState<_HomeGroundPicker> {
  late final _city = TextEditingController(text: widget.initialCity ?? '');
  late final _name = TextEditingController();
  String _searchedCity = '';

  @override
  void initState() {
    super.initState();
    if ((widget.initialCity ?? '').trim().isNotEmpty) {
      _searchedCity = widget.initialCity!.trim();
    }
  }

  @override
  void dispose() {
    _city.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Home ground', style: theme.textTheme.titleLarge),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Search PlaySphere grounds', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() => _searchedCity = v.trim()),
                decoration: InputDecoration(
                  labelText: 'City',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () =>
                        setState(() => _searchedCity = _city.text.trim()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_searchedCity.isNotEmpty) _Results(city: _searchedCity),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Not listed on PlaySphere?',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'A school hall, a village maidan — just name it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Ground name',
                  hintText: 'e.g. Zilla Parishad School Ground',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(context).pop(
                    _HomeGroundChoice(groundName: name),
                  );
                },
                child: const Text('Save this name'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.city});
  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results =
        ref.watch(groundSearchProvider(GroundQuery(keywords: city)));

    return AsyncView(
      value: results,
      onRetry: () =>
          ref.invalidate(groundSearchProvider(GroundQuery(keywords: city))),
      builder: (grounds) {
        if (grounds.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No registered grounds in $city yet — name it below instead.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return Column(
          children: [
            for (final Ground g in grounds)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.stadium_outlined),
                  title: Text(g.name),
                  subtitle: Text(
                    [g.city, if (g.address != null) g.address!].join(' · '),
                  ),
                  onTap: () => Navigator.of(context).pop(
                    _HomeGroundChoice(groundId: g.id, groundName: g.name),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
