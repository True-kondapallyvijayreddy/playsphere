import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/geo.dart';
import '../../core/models/sponsorship.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../home/home_providers.dart';

/// Publishing a sponsorship listing — for the signed-in adult themselves, or
/// for a team they manage.
///
/// Deliberately does not offer "for my child" at all. `firestore.rules`
/// requires a minor athlete's listing to be published by their linked
/// guardian (`users/{uid}.guardianUid`), and guardian-account linking is not
/// yet built anywhere in the app — see the rule comment on
/// `sponsorshipListings`. Rather than build a form that would always be
/// refused server-side, this screen is honest about the gap: an athlete
/// under 18 is told plainly why they cannot self-publish and what to do
/// instead, in the same voice `give_raise_need_screen.dart` uses for its own
/// authority gate.
class SponsorCreateListingScreen extends ConsumerStatefulWidget {
  const SponsorCreateListingScreen({super.key});

  @override
  ConsumerState<SponsorCreateListingScreen> createState() =>
      _SponsorCreateListingScreenState();
}

class _SponsorCreateListingScreenState
    extends ConsumerState<SponsorCreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sport = TextEditingController();
  final _district = TextEditingController();
  final _headline = TextEditingController();
  final _story = TextEditingController();
  final _descriptions = <SponsorshipSupportCategory, TextEditingController>{};

  SponsorshipTargetType _type = SponsorshipTargetType.athlete;
  String? _orgId;
  final Set<SponsorshipSupportCategory> _categories = {};
  bool _busy = false;

  @override
  void dispose() {
    _sport.dispose();
    _district.dispose();
    _headline.dispose();
    _story.dispose();
    for (final c in _descriptions.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _descriptionFor(SponsorshipSupportCategory c) =>
      _descriptions.putIfAbsent(c, () => TextEditingController());

  Future<void> _submit({required String uid, required String displayName}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == SponsorshipTargetType.team && _orgId == null) {
      showError(context, 'Pick which team this listing is for.');
      return;
    }

    setState(() => _busy = true);
    try {
      final orgName = _type == SponsorshipTargetType.team
          ? ref.read(organizationProvider(_orgId!)).valueOrNull?.name
          : null;

      final listing = SponsorshipListing(
        id: '',
        targetType: _type,
        subjectUid: _type == SponsorshipTargetType.athlete ? uid : null,
        subjectDisplayName:
            _type == SponsorshipTargetType.athlete ? displayName : null,
        orgId: _type == SponsorshipTargetType.team ? _orgId : null,
        orgName: _type == SponsorshipTargetType.team ? orgName : null,
        sport: _sport.text.trim(),
        geo: GeoLocation(district: _district.text.trim().isEmpty ? null : _district.text.trim()),
        headline: _headline.text.trim(),
        story: _story.text.trim(),
        asks: [
          for (final c in _categories)
            SponsorshipAsk(
              category: c,
              description: _descriptionFor(c).text.trim(),
            ),
        ],
      );
      await ref
          .read(sponsorRepositoryProvider)
          .publishListing(listing, createdByUid: uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Listing published — it\'s now visible to sponsors.'),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(authUserProvider).valueOrNull;

    if (me == null) {
      return const Scaffold(body: EmptyState(icon: Icons.lock_outline, title: 'Sign in first'));
    }

    if (_type == SponsorshipTargetType.athlete && me.isMinor) {
      return Scaffold(
        appBar: AppBar(title: const Text('Publish a listing')),
        body: const ContentBounds(
          maxWidth: 640,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: EmptyState(
              icon: Icons.shield_outlined,
              title: 'Guardian sign-off needed',
              message:
                  'Sponsorship listings for players under 18 must be published '
                  'by a linked parent/guardian account, which PlaySphere '
                  'doesn\'t yet support end-to-end. Ask your club to raise a '
                  'PlaySphere Give need in the meantime, or check back soon.',
            ),
          ),
        ),
      );
    }

    final orgIds = ref.watch(myActiveOrgIdsProvider);
    final manageableOrgIds = [
      for (final id in orgIds)
        if (ref.watch(myCapabilitiesProvider(id)).contains(Capability.manageCompetitions))
          id,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Publish a listing')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 640,
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<SponsorshipTargetType>(
                    segments: const [
                      ButtonSegment(
                        value: SponsorshipTargetType.athlete,
                        label: Text('For myself'),
                        icon: Icon(Icons.person_outline),
                      ),
                      ButtonSegment(
                        value: SponsorshipTargetType.team,
                        label: Text('For my team'),
                        icon: Icon(Icons.groups_outlined),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_type == SponsorshipTargetType.team)
                    manageableOrgIds.isEmpty
                        ? Card(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'You need to manage a club\'s competitions to '
                                'publish a listing for its team.',
                              ),
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            value: _orgId,
                            decoration: const InputDecoration(
                              labelText: 'Team',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final id in manageableOrgIds)
                                DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    ref.watch(organizationProvider(id)).valueOrNull?.name ?? id,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _orgId = v),
                          ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _sport,
                    decoration: const InputDecoration(
                      labelText: 'Sport',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _district,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'District (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _headline,
                    decoration: const InputDecoration(
                      labelText: 'Headline',
                      hintText: 'e.g. State U-16 100m champion',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _story,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Story (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('What would help?',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in SponsorshipSupportCategory.values)
                        FilterChip(
                          avatar: Text(c.emoji),
                          label: Text(c.label),
                          selected: _categories.contains(c),
                          onSelected: (sel) => setState(
                            () => sel ? _categories.add(c) : _categories.remove(c),
                          ),
                        ),
                    ],
                  ),
                  for (final c in _categories) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descriptionFor(c),
                      decoration: InputDecoration(
                        labelText: '${c.label} — details (optional)',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _submit(uid: me.uid, displayName: me.displayName),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Publish listing'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
