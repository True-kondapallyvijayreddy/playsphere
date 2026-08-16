import 'package:flutter/material.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../domain/scoring/scoring_registry.dart';

/// Specification of a selected category permutation.
class CategoryDraftItem {
  CategoryDraftItem({
    required this.sportId,
    required this.sideFormat,
    required this.category,
    this.equipmentType,
  })  : format = SportCatalog.byId(sportId).competitionFormats.first,
        entries = TextEditingController();

  final String sportId;
  final SideFormat sideFormat;
  final CompetitionCategory category;
  final String? equipmentType;
  CompetitionFormat format;
  final TextEditingController entries;

  SportSpec get sport => SportCatalog.byId(sportId);

  bool clashesWith(CategoryDraftItem other) =>
      sportId == other.sportId &&
      sideFormat.id == other.sideFormat.id &&
      category.label == other.category.label &&
      equipmentType == other.equipmentType;

  void dispose() => entries.dispose();
}

/// Multi-selection Matrix BottomSheet for creating multiple combinations of
/// sports, formats, age categories, genders and equipment types simultaneously.
class BulkCategorySelectorSheet extends StatefulWidget {
  const BulkCategorySelectorSheet({
    super.key,
    this.initialSportId,
    this.cutOff,
  });

  final String? initialSportId;
  final DateTime? cutOff;

  @override
  State<BulkCategorySelectorSheet> createState() => _BulkCategorySelectorSheetState();
}

class _BulkCategorySelectorSheetState extends State<BulkCategorySelectorSheet> {
  late SportSpec _sport;
  final Set<String> _selectedFormatIds = {};
  final Set<String> _selectedAgeCategories = {};
  final Set<String> _selectedEquipmentTypes = {};

  late final List<CompetitionCategory> _presets =
      CompetitionCategory.presets(cutOff: widget.cutOff);

  @override
  void initState() {
    super.initState();
    _sport = widget.initialSportId != null
        ? SportCatalog.byId(widget.initialSportId!)
        : SportCatalog.all.first;

    // Default select first format & Open category
    _selectedFormatIds.add(_sport.defaultSideFormat.id);
    _selectedAgeCategories.add('Open');
  }

  void _onSportChanged(String sportId) {
    setState(() {
      _sport = SportCatalog.byId(sportId);
      _selectedFormatIds.clear();
      _selectedFormatIds.add(_sport.defaultSideFormat.id);
      _selectedEquipmentTypes.clear();
    });
  }

  List<String> get _equipmentOptionsForSport {
    switch (_sport.id) {
      case 'cricket':
        return ['Red Leather Ball', 'White Leather Ball', 'Hard Tennis Ball', 'Soft Tennis Ball'];
      case 'badminton':
        return ['Feather Shuttle', 'Nylon Shuttle'];
      case 'tennis':
        return ['Hard Court Ball', 'Clay Court Ball'];
      case 'table_tennis':
        return ['Plastic 40+ Ball'];
      case 'football':
        return ['Size 5 Ball', 'Size 4 Ball (Youth)', 'Futsal Low-Bounce'];
      default:
        return [];
    }
  }

  List<CategoryDraftItem> _generateSelectedDrafts() {
    final drafts = <CategoryDraftItem>[];
    final selectedFormats = _sport.sideFormats
        .where((f) => _selectedFormatIds.contains(f.id))
        .toList();

    final selectedCategories = _presets
        .where((c) => _selectedAgeCategories.contains(c.label))
        .toList();

    final equipmentList = _selectedEquipmentTypes.isEmpty
        ? [null]
        : _selectedEquipmentTypes.toList();

    for (final fmt in selectedFormats) {
      for (final cat in selectedCategories) {
        for (final equip in equipmentList) {
          drafts.add(
            CategoryDraftItem(
              sportId: _sport.id,
              sideFormat: fmt,
              category: cat,
              equipmentType: equip,
            ),
          );
        }
      }
    }
    return drafts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDrafts = _generateSelectedDrafts();
    final equipOptions = _equipmentOptionsForSport;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Categories (+)',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Multi-select formats, ages, and equipment simultaneously',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    // Sport Selector
                    Text('Select Sport', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _sport.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        for (final s in SportCatalog.all)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.icon}  ${s.name}'),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) _onSportChanged(id);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Side Formats (Singles, Doubles, Mixed, 11-a-side...)
                    Text(
                      'Arrangements / Formats (Pick one or more)',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final format in _sport.sideFormats)
                          FilterChip(
                            label: Text(format.name),
                            selected: _selectedFormatIds.contains(format.id),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedFormatIds.add(format.id);
                                } else if (_selectedFormatIds.length > 1) {
                                  _selectedFormatIds.remove(format.id);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Age / Gender Categories
                    Text(
                      'Age & Gender Categories (Pick one or more)',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final cat in _presets)
                          FilterChip(
                            label: Text(cat.label),
                            selected: _selectedAgeCategories.contains(cat.label),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedAgeCategories.add(cat.label);
                                } else if (_selectedAgeCategories.length > 1) {
                                  _selectedAgeCategories.remove(cat.label);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Equipment / Ball Type (if applicable)
                    if (equipOptions.isNotEmpty) ...[
                      Text(
                        'Ball / Equipment Options',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final equip in equipOptions)
                            FilterChip(
                              label: Text(equip),
                              selected: _selectedEquipmentTypes.contains(equip),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedEquipmentTypes.add(equip);
                                  } else {
                                    _selectedEquipmentTypes.remove(equip);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: selectedDrafts.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(selectedDrafts),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.playlist_add),
                  label: Text(
                    'Add ${selectedDrafts.length} ${selectedDrafts.length == 1 ? 'Category' : 'Categories'}',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
