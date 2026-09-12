import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/coach.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// List yourself as a coach, or edit the listing you already have.
///
/// One screen for both, because they differ only in whether the fields start
/// filled — and a separate "register" flow would be a second place for the
/// same validation to drift.
class CoachProfileEditScreen extends ConsumerStatefulWidget {
  const CoachProfileEditScreen({super.key});

  @override
  ConsumerState<CoachProfileEditScreen> createState() =>
      _CoachProfileEditScreenState();
}

class _CoachProfileEditScreenState
    extends ConsumerState<CoachProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _years = TextEditingController();
  final _rate = TextEditingController();
  final _phone = TextEditingController();
  final _certifications = TextEditingController();
  final _ageGroups = TextEditingController();
  final _formats = TextEditingController();

  final _sports = <String>{};
  bool _accepting = true;
  bool _active = true;
  bool _saving = false;

  /// Whether the fields have been filled from the existing listing yet.
  ///
  /// Guarded rather than done in `initState`: the listing arrives on a
  /// stream, so it is usually not there for the first build, and re-filling
  /// on every rebuild would wipe whatever the person had typed.
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [
      _headline, _bio, _city, _district, _years,
      _rate, _phone, _certifications, _ageGroups, _formats,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(CoachProfile p) {
    _loaded = true;
    _headline.text = p.headline ?? '';
    _bio.text = p.bio ?? '';
    _city.text = p.city;
    _district.text = p.district ?? '';
    _years.text = p.yearsExperience == 0 ? '' : '${p.yearsExperience}';
    // Rupees in the field, paise on the document. Nobody types paise.
    _rate.text =
        p.sessionRatePaise == 0 ? '' : '${(p.sessionRatePaise / 100).round()}';
    _phone.text = p.contactPhone ?? '';
    _certifications.text = p.certifications.join(', ');
    _ageGroups.text = p.ageGroups.join(', ');
    _formats.text = p.formats.join(', ');
    _sports
      ..clear()
      ..addAll(p.sportIds);
    _accepting = p.acceptingStudents;
    _active = p.isActive;
  }

  static List<String> _split(String raw) => [
        for (final part in raw.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  Future<void> _save({required bool isNew}) async {
    if (!_form.currentState!.validate()) return;
    if (_sports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one sport you coach')),
      );
      return;
    }

    final me = ref.read(authUserProvider).valueOrNull;
    if (me == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(coachRepositoryProvider).saveMyProfile(
            CoachProfile(
              uid: me.uid,
              // Taken from the account, not typed. A coach listing under a
              // name the rest of the app does not know them by is how a
              // directory becomes unsearchable.
              displayName: me.displayName,
              photoUrl: me.photoUrl,
              sportIds: _sports.toList(),
              headline: _headline.text.trim().isEmpty
                  ? null
                  : _headline.text.trim(),
              bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
              city: _city.text.trim(),
              district: _district.text.trim().isEmpty
                  ? null
                  : _district.text.trim(),
              yearsExperience: int.tryParse(_years.text.trim()) ?? 0,
              certifications: _split(_certifications.text),
              ageGroups: _split(_ageGroups.text),
              formats: _split(_formats.text),
              sessionRatePaise:
                  (int.tryParse(_rate.text.trim()) ?? 0) * 100,
              acceptingStudents: _accepting,
              contactPhone:
                  _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              isActive: _active,
            ),
            isNew: isNew,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isNew ? 'You are listed as a coach' : 'Listing saved'),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUserProvider).valueOrNull;
    final existing = ref.watch(myCoachProfileProvider);
    final profile = existing.valueOrNull;
    if (profile != null && !_loaded) _fill(profile);

    // Enforced in `firestore.rules` as well, and that is the copy that
    // matters — this one exists so a sixteen-year-old is told why rather
    // than watching a save fail with a permission error.
    if (me != null && me.isMinor) {
      return const AppScaffold(
        title: 'Coach listing',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Not yet',
          message: 'A coach listing is a public invitation carrying your '
              'phone number, so PlaySphere only accepts them from adults. '
              'You can still be found as a player.',
        ),
      );
    }

    final isNew = profile == null;

    return AppScaffold(
      title: isNew ? 'List yourself as a coach' : 'Your coach listing',
      subtitle: isNew ? null : 'Players find you by these details',
      body: AsyncView(
        value: existing,
        onRetry: () => ref.invalidate(myCoachProfileProvider),
        builder: (_) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Form(
                key: _form,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('WHAT YOU COACH'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final sport in SportCatalog.all)
                            FilterChip(
                              label: Text(sport.name),
                              selected: _sports.contains(sport.id),
                              // Six is the cap the rules enforce. Somebody
                              // claiming to coach the whole catalog is not
                              // making a claim worth indexing.
                              onSelected: (on) => setState(() {
                                if (on) {
                                  if (_sports.length < 6) _sports.add(sport.id);
                                } else {
                                  _sports.remove(sport.id);
                                }
                              }),
                            ),
                        ],
                      ),

                      const _Label('HOW YOU’D INTRODUCE YOURSELF'),
                      TextFormField(
                        controller: _headline,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Ex-Ranji seamer, 12 years with juniors',
                          helperText: 'The one line players see in the list',
                        ),
                      ),
                      TextFormField(
                        controller: _bio,
                        maxLines: 5,
                        maxLength: 1200,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'About your coaching',
                        ),
                      ),

                      const _Label('WHERE'),
                      TextFormField(
                        controller: _city,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'City or town',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Players search by place — this one is needed'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _district,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'District (optional)',
                        ),
                      ),

                      const _Label('EXPERIENCE'),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _years,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Years coaching',
                              ),
                              validator: (v) {
                                final raw = (v ?? '').trim();
                                if (raw.isEmpty) return null;
                                final n = int.tryParse(raw);
                                if (n == null || n < 0 || n > 80) {
                                  return '0–80';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _rate,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: '₹ per session',
                                helperText: 'Blank = on request',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _certifications,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Certifications',
                          hintText: 'NIS Patiala, BCCI Level 1',
                          helperText: 'Comma separated',
                        ),
                      ),

                      const _Label('WHO AND HOW'),
                      TextFormField(
                        controller: _ageGroups,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Age groups',
                          hintText: 'U12, U16, Seniors',
                          helperText: 'Comma separated',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _formats,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Session types',
                          hintText: 'One-to-one, Group, Online',
                          helperText: 'Comma separated',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Contact number',
                          helperText: 'Shown publicly on your listing',
                        ),
                      ),

                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _accepting,
                        onChanged: (v) => setState(() => _accepting = v),
                        title: const Text('Taking students right now'),
                        subtitle: const Text(
                          'Turn off when you are full — you stay findable',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                        title: const Text('Listed'),
                        subtitle: const Text(
                          'Turn off to disappear from searches entirely',
                        ),
                      ),

                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _saving ? null : () => _save(isNew: isNew),
                        child: Text(
                          _saving
                              ? 'Saving…'
                              : isNew
                                  ? 'List me as a coach'
                                  : 'Save listing',
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Text(
                        'Your listing is public and is not checked by '
                        'PlaySphere before it appears. Claim only what you '
                        'can stand behind — a player’s page will say so.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Ps.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: Ps.faint,
        ),
      ),
    );
  }
}
