import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sports_medic.dart';
import '../../core/providers.dart';
import '../../domain/medical/sports_medicine_library.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// List your practice, or edit the listing you already have.
///
/// One screen for both, for the same reason the coach form is: they differ
/// only in whether the fields start filled, and a separate "register" flow
/// would be a second place for the same validation to drift out of step with
/// `firestore.rules`.
///
/// The form asks for a registration number and does not make it compulsory.
/// That is deliberate: a rule that refused every listing without one would
/// keep out the physiotherapists whose state council number is on a
/// certificate in a drawer, and the honest thing is to publish the field,
/// show plainly when it is empty, and let a patient weigh it.
class SportsMedicRegistrationScreen extends ConsumerStatefulWidget {
  const SportsMedicRegistrationScreen({super.key});

  @override
  ConsumerState<SportsMedicRegistrationScreen> createState() =>
      _SportsMedicRegistrationScreenState();
}

class _SportsMedicRegistrationScreenState
    extends ConsumerState<SportsMedicRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _qualifications = TextEditingController();
  final _registration = TextEditingController();
  final _council = TextEditingController();
  final _years = TextEditingController();
  final _clinic = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();
  final _languages = TextEditingController();
  final _fee = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();

  SportsMedicRole _role = SportsMedicRole.physiotherapist;
  final _sports = <String>{};
  final _bodyParts = <String>{};
  final _modes = <ConsultationMode>{ConsultationMode.clinic};
  bool _accepting = true;
  bool _active = true;
  bool _saving = false;

  /// Whether the fields have been filled from the existing listing yet.
  ///
  /// Guarded rather than done in `initState`: the listing arrives on a
  /// stream and is usually absent on the first build, and re-filling on every
  /// rebuild would wipe whatever the person had just typed.
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [
      _headline, _bio, _qualifications, _registration, _council,
      _years, _clinic, _city, _district, _address, _languages,
      _fee, _phone, _whatsapp, _email,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(SportsMedicProfile p) {
    _loaded = true;
    _role = p.role;
    _headline.text = p.headline ?? '';
    _bio.text = p.bio ?? '';
    _qualifications.text = p.qualifications.join(', ');
    _registration.text = p.registrationNumber ?? '';
    _council.text = p.councilName ?? '';
    _years.text = p.experienceYears == 0 ? '' : '${p.experienceYears}';
    _clinic.text = p.clinicName;
    _city.text = p.city;
    _district.text = p.district ?? '';
    _address.text = p.address ?? '';
    _languages.text = p.languages.join(', ');
    // Rupees in the field, paise on the document. Nobody types paise.
    _fee.text = p.consultationFeePaise == 0
        ? ''
        : '${(p.consultationFeePaise / 100).round()}';
    _phone.text = p.contactPhone ?? '';
    _whatsapp.text = p.whatsappPhone ?? '';
    _email.text = p.email ?? '';
    _sports
      ..clear()
      ..addAll(p.sportIds);
    _bodyParts
      ..clear()
      ..addAll(p.bodyPartsTreated);
    _modes
      ..clear()
      ..addAll(p.consultationModes);
    _accepting = p.acceptingNewPatients;
    _active = p.isActive;
  }

  static List<String> _split(String raw) => [
        for (final part in raw.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  String? _trimmedOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save({required bool isNew}) async {
    if (!_form.currentState!.validate()) return;
    if (_modes.isEmpty) {
      _complain('Pick at least one way patients can see you');
      return;
    }
    // A listing with no way to reach it is a row somebody taps and cannot
    // act on, which is worse than not being listed at all.
    if (_phone.text.trim().isEmpty &&
        _whatsapp.text.trim().isEmpty &&
        _email.text.trim().isEmpty) {
      _complain('Give at least one way to be contacted — phone, WhatsApp or '
          'email');
      return;
    }

    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(sportsMedicRepositoryProvider).saveMyProfile(
            SportsMedicProfile(
              uid: me.uid,
              // Taken from the account, not typed. A listing under a name the
              // rest of the app does not know is how a directory becomes
              // unsearchable — same rule as the coach listing.
              displayName: me.displayName,
              photoUrl: me.photoUrl,
              role: _role,
              headline: _trimmedOrNull(_headline),
              bio: _trimmedOrNull(_bio),
              qualifications: _split(_qualifications.text),
              registrationNumber: _trimmedOrNull(_registration),
              councilName: _trimmedOrNull(_council),
              experienceYears: int.tryParse(_years.text.trim()) ?? 0,
              sportIds: _sports.toList(),
              bodyPartsTreated: _bodyParts.toList(),
              clinicName: _clinic.text.trim(),
              city: _city.text.trim(),
              district: _trimmedOrNull(_district),
              address: _trimmedOrNull(_address),
              languages: _split(_languages.text),
              consultationModes: _modes.toList(),
              consultationFeePaise:
                  (int.tryParse(_fee.text.trim()) ?? 0) * 100,
              contactPhone: _trimmedOrNull(_phone),
              whatsappPhone: _trimmedOrNull(_whatsapp),
              email: _trimmedOrNull(_email),
              acceptingNewPatients: _accepting,
              isActive: _active,
            ),
            isNew: isNew,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNew ? 'Your practice is listed' : 'Listing saved',
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _complain('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _complain(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final existing = ref.watch(mySportsMedicProfileProvider);
    final profile = existing.valueOrNull;
    if (profile != null && !_loaded) _fill(profile);

    // Enforced in `firestore.rules` too, and that is the copy that matters;
    // this one exists so a seventeen-year-old is told why rather than
    // watching a save fail with a permission error.
    if (me != null && me.isMinor) {
      return const AppScaffold(
        title: 'Practice listing',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Not yet',
          message: 'A practice listing is a public invitation carrying your '
              'phone number and a clinical claim, so PlaySphere only accepts '
              'them from adults.',
        ),
      );
    }

    final isNew = profile == null;

    return AppScaffold(
      title: isNew ? 'List your practice' : 'Your practice listing',
      subtitle: isNew ? null : 'Players find you by these details',
      body: AsyncView(
        value: existing,
        onRetry: () => ref.invalidate(mySportsMedicProfileProvider),
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
                      const _Label('WHAT YOU ARE'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final role in SportsMedicRole.values)
                            ChoiceChip(
                              label: Text(role.label),
                              selected: _role == role,
                              // One only. This is the filter the whole
                              // directory turns on, and a person who ticked
                              // three would appear in three lists that mean
                              // three different things to a patient.
                              onSelected: (on) {
                                if (on) setState(() => _role = role);
                              },
                            ),
                        ],
                      ),

                      const _Label('HOW YOU’D INTRODUCE YOURSELF'),
                      TextFormField(
                        controller: _headline,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText:
                              'Team physio, Hyderabad district cricket squad',
                          helperText: 'The one line players see in the list',
                        ),
                      ),
                      TextFormField(
                        controller: _bio,
                        maxLines: 5,
                        maxLength: 1200,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'About your practice',
                        ),
                      ),

                      const _Label('CREDENTIALS'),
                      TextFormField(
                        controller: _qualifications,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Qualifications',
                          hintText: 'MBBS, MS Ortho, MPT (Sports), CSCS',
                          helperText: 'Comma separated',
                        ),
                        validator: (v) => _split(v ?? '').isEmpty
                            ? 'At least one qualification — this is what a '
                                'patient reads first'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _registration,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Registration number (optional)',
                          helperText: 'Shown publicly so patients can check '
                              'it on the council register',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _council,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Council or board',
                          hintText: 'Telangana State Medical Council',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _years,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Years in practice',
                        ),
                        validator: (v) {
                          final raw = (v ?? '').trim();
                          if (raw.isEmpty) return null;
                          final n = int.tryParse(raw);
                          if (n == null || n < 0 || n > 70) return '0–70';
                          return null;
                        },
                      ),

                      const _Label('SPORTS YOU WORK WITH'),
                      const Text(
                        'Leave all of these blank if you treat athletes from '
                        'any sport — you will still appear in every sport’s '
                        'results.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Ps.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final sport in SportCatalog.all)
                            FilterChip(
                              label: Text(sport.name),
                              selected: _sports.contains(sport.id),
                              // Ten is the cap the rules enforce. Past that
                              // the claim stops narrowing anything and the
                              // list is the whole catalogue.
                              onSelected: (on) => setState(() {
                                if (on) {
                                  if (_sports.length < 10) {
                                    _sports.add(sport.id);
                                  }
                                } else {
                                  _sports.remove(sport.id);
                                }
                              }),
                            ),
                        ],
                      ),

                      const _Label('WHAT YOU TREAT'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final part in BodyPart.values)
                            FilterChip(
                              label: Text(part.label),
                              selected: _bodyParts.contains(part.wire),
                              onSelected: (on) => setState(() {
                                if (on) {
                                  _bodyParts.add(part.wire);
                                } else {
                                  _bodyParts.remove(part.wire);
                                }
                              }),
                            ),
                        ],
                      ),

                      const _Label('WHERE'),
                      TextFormField(
                        controller: _clinic,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Clinic or hospital name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _city,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'City or town',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Patients search by place — this one is needed'
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
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _address,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Address',
                          helperText: 'Enough for somebody to find the door',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _languages,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Languages you consult in',
                          hintText: 'Telugu, Hindi, English',
                          helperText: 'Comma separated',
                        ),
                      ),

                      const _Label('HOW PATIENTS SEE YOU'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final mode in ConsultationMode.values)
                            FilterChip(
                              label: Text(mode.label),
                              selected: _modes.contains(mode),
                              onSelected: (on) => setState(() {
                                if (on) {
                                  _modes.add(mode);
                                } else {
                                  _modes.remove(mode);
                                }
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _fee,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '₹ per consultation',
                          helperText: 'Blank = on request. PlaySphere takes '
                              'no cut and handles no payment.',
                        ),
                      ),

                      const _Label('CONTACT'),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Phone',
                          helperText: 'Shown publicly on your listing',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _whatsapp,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'WhatsApp number (optional)',
                          helperText: 'Leave blank if it is the same number',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Email (optional)',
                        ),
                        validator: (v) {
                          final raw = (v ?? '').trim();
                          if (raw.isEmpty) return null;
                          return raw.contains('@') && raw.contains('.')
                              ? null
                              : 'That does not look like an email address';
                        },
                      ),

                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _accepting,
                        onChanged: (v) => setState(() => _accepting = v),
                        title: const Text('Taking new patients'),
                        subtitle: const Text(
                          'Turn off when your list is full — you stay '
                          'findable',
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
                                  ? 'List my practice'
                                  : 'Save listing',
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Text(
                        'Your listing is public and is not checked by '
                        'PlaySphere before it appears. Publish only '
                        'qualifications and a registration number you hold — '
                        'the page tells patients they can verify the number '
                        'on the council’s public register, and they will.',
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
          letterSpacing: 0.6,
          color: Ps.faint,
        ),
      ),
    );
  }
}
