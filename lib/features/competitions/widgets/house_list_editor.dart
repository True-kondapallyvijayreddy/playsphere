import 'package:flutter/material.dart';

import '../../../domain/tournament/house_roster.dart';
import '../../../shared/ui_kit.dart';

/// The template pickers and the plain house-list editor, shared by the
/// creation wizards and by [HousesEditorSheet].
///
/// The wizard and the sheet edit the same list for the same reason, but not
/// under the same constraints: at creation time no one has registered yet, so
/// there is nothing to rename and nothing to strand. Keeping the naming UI
/// here and the migration logic in the sheet is what stops the wizard from
/// carrying machinery it has no use for — and stops the two from drifting into
/// offering different templates.

/// A bare editable list of house names, for the creation wizards.
///
/// No registration counts and no rename tracking: an event being created has
/// no entries to move. [onChanged] fires with the trimmed, non-empty names.
class HouseListEditor extends StatefulWidget {
  const HouseListEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  @override
  State<HouseListEditor> createState() => _HouseListEditorState();
}

class _HouseListEditorState extends State<HouseListEditor> {
  late final List<TextEditingController> _rows = [
    for (final h in widget.initial) TextEditingController(text: h),
  ];

  @override
  void dispose() {
    for (final c in _rows) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged([
        for (final c in _rows)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ]);

  void _applyTemplate(List<String> names) {
    setState(() {
      for (final c in _rows) {
        c.dispose();
      }
      _rows
        ..clear()
        ..addAll([for (final n in names) TextEditingController(text: n)]);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HouseTemplateChips(onPicked: _applyTemplate),
        const SizedBox(height: 10),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rows[i],
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: 'House ${i + 1}',
                      hintText: 'e.g. ECE — 3rd Year',
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    setState(() => _rows.removeAt(i).dispose());
                    _emit();
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _rows.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a house'),
          ),
        ),
      ],
    );
  }
}

/// The four ways an organizer gets a house list without typing one.
class HouseTemplateChips extends StatelessWidget {
  const HouseTemplateChips({super.key, required this.onPicked});

  final ValueChanged<List<String>> onPicked;

  Future<void> _departments(BuildContext context) async {
    final r = await showDialog<List<String>>(
      context: context,
      builder: (_) => const DepartmentYearDialog(),
    );
    if (r != null && r.isNotEmpty) onPicked(r);
  }

  Future<void> _sections(BuildContext context) async {
    final r = await showDialog<List<String>>(
      context: context,
      builder: (_) => const SectionDialog(),
    );
    if (r != null && r.isNotEmpty) onPicked(r);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        ActionChip(
          avatar: const Icon(Icons.palette_outlined, size: 16),
          label: const Text('School houses'),
          onPressed: () => onPicked(HouseTemplates.schoolColours),
        ),
        ActionChip(
          avatar: const Icon(Icons.apartment_outlined, size: 16),
          label: const Text('Departments × Years'),
          onPressed: () => _departments(context),
        ),
        ActionChip(
          avatar: const Icon(Icons.class_outlined, size: 16),
          label: const Text('Class sections'),
          onPressed: () => _sections(context),
        ),
        ActionChip(
          avatar: const Icon(Icons.school_outlined, size: 16),
          label: const Text('Year groups'),
          onPressed: () => onPicked(HouseTemplates.years(4)),
        ),
      ],
    );
  }
}

/// Collects the two lists a college meet is actually split by, and crosses
/// them — see [HouseTemplates.departmentYears].
class DepartmentYearDialog extends StatefulWidget {
  const DepartmentYearDialog({super.key});

  @override
  State<DepartmentYearDialog> createState() => _DepartmentYearDialogState();
}

class _DepartmentYearDialogState extends State<DepartmentYearDialog> {
  final _departments = TextEditingController(text: 'ECE, CSE, EEE, MECH');
  final Set<int> _years = {1, 2, 3, 4};

  @override
  void dispose() {
    _departments.dispose();
    super.dispose();
  }

  List<String> get _preview => HouseTemplates.departmentYears(
        departments: _departments.text
            .split(',')
            .map((d) => d.trim())
            .where((d) => d.isNotEmpty)
            .toList(),
        years: (_years.toList()..sort()),
      );

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Departments × Years'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _departments,
              decoration: const InputDecoration(
                labelText: 'Departments, separated by commas',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text('Years', style: TextStyle(fontSize: 12.5, color: Ps.muted)),
            Wrap(
              spacing: 6,
              children: [
                for (final y in [1, 2, 3, 4, 5])
                  FilterChip(
                    label: Text(HouseTemplates.ordinal(y)),
                    selected: _years.contains(y),
                    onSelected: (on) => setState(() {
                      on ? _years.add(y) : _years.remove(y);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              preview.isEmpty
                  ? 'Nothing to create yet.'
                  : '${preview.length} groups: ${preview.take(4).join(', ')}'
                      '${preview.length > 4 ? '…' : ''}',
              style: const TextStyle(fontSize: 12.5, color: Ps.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: preview.isEmpty
              ? null
              : () => Navigator.of(context).pop(preview),
          child: const Text('Use these'),
        ),
      ],
    );
  }
}

/// "8-A", "8-B", "8-C" — see [HouseTemplates.sections].
class SectionDialog extends StatefulWidget {
  const SectionDialog({super.key});

  @override
  State<SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<SectionDialog> {
  final _grade = TextEditingController(text: 'Class 8');
  int _count = 4;

  @override
  void dispose() {
    _grade.dispose();
    super.dispose();
  }

  List<String> get _preview =>
      HouseTemplates.sections(grade: _grade.text, count: _count);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Class sections'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _grade,
            decoration: const InputDecoration(
              labelText: 'Class or grade',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Sections', style: TextStyle(fontSize: 12.5, color: Ps.muted)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _count > 2 ? () => setState(() => _count--) : null,
              ),
              Text('$_count'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _count < 12 ? () => setState(() => _count++) : null,
              ),
            ],
          ),
          Text(
            _preview.join(', '),
            style: const TextStyle(fontSize: 12.5, color: Ps.muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_preview),
          child: const Text('Use these'),
        ),
      ],
    );
  }
}
