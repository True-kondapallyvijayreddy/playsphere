import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// A guardian creates a profile for a child with no device or Google
/// account of their own yet.
///
/// Deliberately a smaller form than [ProfileSetupScreen]: no photo (nobody
/// has one to give yet), no visibility choice (every managed profile starts
/// private — see `functions/family.js` — and the child can change that
/// themselves once they've claimed it), no email (there isn't one). Just
/// enough to register the child for sport.
class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key});

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  DateTime? _dateOfBirth;
  Gender _gender = Gender.preferNotToSay;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 8, now.month, now.day),
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: "Select the child's date of birth",
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final dob = _dateOfBirth;
    if (dob == null) {
      showError(context,
          const ValidationException("Enter the child's date of birth."));
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(userRepositoryProvider);
      final child = await repo.createManagedChild(
        displayName: _nameController.text.trim(),
        dateOfBirth: dob,
        gender: _gender,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            child.playerCode == null
                ? '${_nameController.text.trim()} was added.'
                : '${_nameController.text.trim()} was added — player code '
                    '${child.playerCode}.',
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dob = _dateOfBirth;

    return Scaffold(
      appBar: AppBar(title: const Text('Add a child')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 520,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Create your child's profile",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'You manage this profile until your child has their own '
                  'phone. When they do, generate a code from their profile '
                  'and they can claim it as their own — same matches, same '
                  'player code, nothing lost.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Child's name",
                    helperText: 'How they appear on team sheets and results',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? "Enter the child's name"
                      : null,
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
                      border: const OutlineInputBorder(),
                      helperText: dob == null ? 'Required' : null,
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
                  child: Text(_busy ? 'Adding…' : 'Add child'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
