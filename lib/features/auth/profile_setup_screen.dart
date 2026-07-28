import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
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
  DateTime? _dateOfBirth;
  Gender _gender = Gender.preferNotToSay;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
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
      showError(context, Exception(': Please enter your date of birth.'));
      return;
    }

    final authUser = ref.read(authStateProvider).valueOrNull;
    if (authUser == null) return;

    setState(() => _busy = true);
    try {
      final existing = ref.read(currentUserProvider).valueOrNull;
      final profile = AppUser(
        uid: authUser.uid,
        displayName: _nameController.text.trim(),
        email: authUser.email ?? '',
        dateOfBirth: _dateOfBirth!,
        gender: _gender,
        photoUrl: authUser.photoURL,
        profileComplete: true,
      );

      final repo = ref.read(userRepositoryProvider);
      if (existing == null) {
        await repo.createProfile(profile);
      } else {
        await repo.updateProfile(profile);
      }
      // The router redirect moves us on as soon as the profile stream
      // reports complete.
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
    if (!_prefilled && authUser != null) {
      _nameController.text = authUser.displayName ?? '';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Complete your profile')),
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
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    helperText: 'How you appear on team sheets and results',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
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
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    helperText: 'Used only for gender-based categories',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final g in Gender.values)
                      DropdownMenuItem(value: g, child: Text(g.label)),
                  ],
                  onChanged: (v) => setState(() => _gender = v ?? _gender),
                ),
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
