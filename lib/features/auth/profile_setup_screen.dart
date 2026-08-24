import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/errors/app_exception.dart';
import '../../core/models/app_user.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/app_scaffold.dart';

/// Collects what Google Sign-In cannot give us.
///
/// Date of birth is mandatory and write-once. Every age-category rule, every
/// minor-safety protection and every eligibility check depends on it, and a
/// field a user can quietly edit later makes all three unenforceable — age
/// fraud is the single most common integrity problem in junior sport.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  DateTime? _dateOfBirth;
  Gender _gender = Gender.preferNotToSay;
  ProfileVisibility _visibility = ProfileVisibility.community;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 16, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Select your date of birth',
      // Opening on the year grid: scrolling a calendar back sixteen years a
      // month at a time is the kind of small cruelty that makes people
      // abandon a signup.
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      showError(context, const ValidationException('Please enter your date of birth.'));
      return;
    }

    final authUser = ref.read(authStateProvider).valueOrNull;
    if (authUser == null) return;

    setState(() => _busy = true);
    try {
      final existing = ref.read(currentUserProvider).valueOrNull;
      final phone =
          _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();
      // Edits build on the stored profile rather than on a fresh object, so
      // a field this form still does not show — the location that feeds
      // the government aggregates — survives a name change.
      final profile = existing?.copyWith(
            displayName: _nameController.text.trim(),
            gender: _gender,
            phone: phone,
            photoUrl: authUser.photoURL,
            profileVisibility: _visibility,
            profileComplete: true,
          ) ??
          AppUser(
            uid: authUser.uid,
            displayName: _nameController.text.trim(),
            email: authUser.email ?? '',
            dateOfBirth: _dateOfBirth!,
            gender: _gender,
            phone: phone,
            photoUrl: authUser.photoURL,
            profileVisibility: _visibility,
            profileComplete: true,
          );

      final repo = ref.read(userRepositoryProvider);
      if (existing == null) {
        await repo.createProfile(profile);
      } else {
        await repo.updateProfile(profile);
      }
      if (!mounted) return;
      // The router no longer moves a completed profile off this screen on
      // its own — see the redirect's comment in app_router.dart — because
      // this screen is also where a complete profile is deliberately
      // EDITED. A pop returns an editor to wherever they opened it from;
      // first-time setup has nothing to pop to, so it lands on home.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.home);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider).valueOrNull;

    // Seed the name from the Google account once, then leave it editable —
    // plenty of people sign in with an account named differently from how
    // they are known on a team sheet.
    // Waiting for the profile stream to settle before seeding the form is what
    // makes this an EDIT screen as well as a setup screen: prefilling from a
    // still-loading stream would blank every field the user already has.
    final profileAsync = ref.watch(currentUserProvider);
    final existing = profileAsync.valueOrNull;
    if (!_prefilled && authUser != null && !profileAsync.isLoading) {
      _nameController.text = existing?.displayName ?? authUser.displayName ?? '';
      _phoneController.text = existing?.phone ?? '';
      _visibility = existing?.profileVisibility ?? _visibility;
      _dateOfBirth ??= existing?.dateOfBirth;
      _gender = existing?.gender ?? _gender;
      _prefilled = true;
    }

    final dob = _dateOfBirth;
    final age = dob == null ? null : AppUser(
      uid: '',
      displayName: '',
      email: '',
      dateOfBirth: dob,
      gender: _gender,
    ).ageAt(DateTime.now());

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileSetupTitle)),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 520,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A few details before you start',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Your date of birth decides which age categories you can '
                  'enter, so it has to be right. It cannot be changed later '
                  'without an organizer.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.profileName,
                    helperText: 'How you appear on team sheets and results',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    helperText: 'Visible to whoever can already see your profile',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.profileDateOfBirth,
                      border: const OutlineInputBorder(),
                      helperText: age == null
                          ? 'Required'
                          : 'You are $age years old'
                              '${age < 18 ? ' — extra privacy protections apply' : ''}',
                    ),
                    child: Text(
                      dob == null
                          ? 'Tap to select'
                          : DateFormat('d MMMM yyyy').format(dob),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<Gender>(
                  value: _gender,
                  decoration: InputDecoration(
                    labelText: l10n.profileGender,
                    helperText: 'Used only for gender-based categories',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final g in Gender.values)
                      DropdownMenuItem(value: g, child: Text(g.label)),
                  ],
                  onChanged: (v) => setState(() => _gender = v ?? _gender),
                ),
                const SizedBox(height: 20),
                // Nothing anywhere in the app could set this before, so every
                // account carried the `community` default and no screen ever
                // told anyone it existed — a privacy control the owner cannot
                // see is not a privacy control.
                DropdownButtonFormField<ProfileVisibility>(
                  value: _visibility,
                  decoration: const InputDecoration(
                    labelText: 'Who can see my profile',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final v in ProfileVisibility.values)
                      DropdownMenuItem(value: v, child: Text(v.label)),
                  ],
                  onChanged: (v) => setState(() => _visibility = v ?? _visibility),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (_visibility) {
                    ProfileVisibility.private =>
                      'Only you. Your results still count towards your club\'s '
                          'records, but nobody can open your career page.',
                    ProfileVisibility.community =>
                      'Anyone in a club you belong to can open your career '
                          'page. People outside them cannot.',
                    ProfileVisibility.public =>
                      'Anyone with the link can open your career page — what '
                          'a scout or a selector would use.',
                  },
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
                if (age != null && age < 18) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Under 18, this setting does nothing: your profile stays '
                    'closed to everyone except a scout your guardian has '
                    'approved. That protection is not yours to switch off.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Saving…' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
