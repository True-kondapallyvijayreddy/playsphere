import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/organization.dart';
import '../../../core/providers.dart';
import '../../../core/text/ordinal.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';

/// Where the club records which house, department, year or class each of its
/// members is in — the roster half of automatic team placement.
///
/// ## Why this is bulk-first
///
/// The unit of work is a class, not a person. An admin entering four hundred
/// students one profile at a time does not finish, and a roster that is half
/// filled in is worse than an empty one: auto-placement would confidently
/// split one year group across two houses and leave the organizer to work out
/// why. So the primary gesture here is "select these forty students, stamp
/// ECE — 3rd Year on all of them", and the single-member edit is the same
/// screen with one row ticked.
///
/// ## Why blank fields are left alone rather than cleared
///
/// The fields get filled in by different people at different times — a class
/// teacher sets departments in June, a sports captain sets houses in August.
/// If applying a department wiped the houses, the second person's work would
/// destroy the first's every time. So only the boxes that were filled in are
/// written. The cost is that this screen cannot blank a field back out — that
/// is the single-member edit's job, and it is the rarer action by a wide
/// margin.
class MemberGroupingSheet extends ConsumerStatefulWidget {
  const MemberGroupingSheet({
    super.key,
    required this.orgId,
    this.only,
  });

  final String orgId;

  /// Preselects one member and hides the picker — the roster's per-member
  /// edit. Null opens the full bulk picker.
  final Membership? only;

  static Future<void> show(
    BuildContext context, {
    required String orgId,
    Membership? only,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => MemberGroupingSheet(orgId: orgId, only: only),
      );

  @override
  ConsumerState<MemberGroupingSheet> createState() =>
      _MemberGroupingSheetState();
}

class _MemberGroupingSheetState extends ConsumerState<MemberGroupingSheet> {
  late final Set<String> _selected = {
    if (widget.only != null) widget.only!.uid,
  };

  final _search = TextEditingController();
  late final _department = TextEditingController(
    text: widget.only?.grouping.department ?? '',
  );
  late final _house = TextEditingController(
    text: widget.only?.grouping.house ?? '',
  );
  late final _grade = TextEditingController(
    text: widget.only?.grouping.grade ?? '',
  );
  late final _section = TextEditingController(
    text: widget.only?.grouping.section ?? '',
  );
  late int? _year = widget.only?.grouping.year;

  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _department.dispose();
    _house.dispose();
    _grade.dispose();
    _section.dispose();
    super.dispose();
  }

  String? _v(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  bool get _hasSomethingToWrite =>
      _v(_department) != null ||
      _v(_house) != null ||
      _v(_grade) != null ||
      _v(_section) != null ||
      _year != null;

  Future<void> _apply(List<Membership> all) async {
    final chosen = all.where((m) => _selected.contains(m.uid));

    // Merged onto what each member already has, one at a time — see the class
    // doc for why a blank box is "leave it" and not "clear it".
    final groupings = {
      for (final m in chosen)
        m.uid: m.grouping.copyWith(
          department: _v(_department),
          house: _v(_house),
          grade: _v(_grade),
          section: _v(_section),
          year: _year,
        ),
    };

    setState(() => _busy = true);
    try {
      await ref.read(orgRepositoryProvider).setMemberGroupings(
            orgId: widget.orgId,
            groupings: groupings,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${groupings.length} '
            '${groupings.length == 1 ? 'member' : 'members'}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final all = (membersAsync.valueOrNull ?? const <Membership>[])
        .where((m) => m.isActive)
        .toList();

    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? all
        : all
            .where((m) =>
                m.displayName.toLowerCase().contains(query) ||
                m.grouping.summary.toLowerCase().contains(query))
            .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined, color: Ps.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.only == null
                      ? 'Houses, Classes & Departments'
                      : widget.only!.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Text(
            'Recorded for this club only. Once a member has these, an event '
            'that splits by house, department or year can place them into a '
            'team automatically.',
            style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _department,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Department',
                    hintText: 'ECE',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _year,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Year',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (var y = 1; y <= 5; y++)
                      DropdownMenuItem(value: y, child: Text(ordinal(y))),
                  ],
                  onChanged: (v) => setState(() => _year = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _grade,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Class',
                    hintText: 'Class 8',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _section,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Section',
                    hintText: 'A',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _house,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'House',
              hintText: 'Red House',
            ),
            onChanged: (_) => setState(() {}),
          ),

          if (widget.only == null) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Find members',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                TextButton(
                  onPressed: visible.isEmpty
                      ? null
                      : () => setState(() {
                            final ids = visible.map((m) => m.uid).toSet();
                            // Toggles the FILTERED set, which is what makes
                            // "search ECE, select all, stamp 3rd Year" the
                            // three-tap gesture this screen exists for.
                            if (ids.every(_selected.contains)) {
                              _selected.removeAll(ids);
                            } else {
                              _selected.addAll(ids);
                            }
                          }),
                  child: const Text('All'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: membersAsync.isLoading && all.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) {
                        final m = visible[i];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected.contains(m.uid),
                          title: Text(m.displayName),
                          subtitle: m.grouping.isEmpty
                              ? const Text(
                                  'Not set',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Ps.faint,
                                  ),
                                )
                              : Text(
                                  m.grouping.summary,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Ps.muted,
                                  ),
                                ),
                          onChanged: (on) => setState(() {
                            on == true
                                ? _selected.add(m.uid)
                                : _selected.remove(m.uid);
                          }),
                        );
                      },
                    ),
            ),
          ],

          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _selected.isEmpty || !_hasSomethingToWrite
                ? null
                : () => _apply(all),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              _busy
                  ? 'Saving…'
                  : _selected.isEmpty
                      ? 'Select members to update'
                      : !_hasSomethingToWrite
                          ? 'Fill in at least one field'
                          : 'Apply to ${_selected.length} '
                              '${_selected.length == 1 ? 'member' : 'members'}',
            ),
          ),
        ],
      ),
    );
  }
}
