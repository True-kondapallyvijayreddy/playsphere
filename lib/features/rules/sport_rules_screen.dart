import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/sport_rule.dart';
import '../../data/sport_rule_repository.dart';

final sportRuleRepositoryProvider = Provider<SportRuleRepository>((ref) {
  return const SportRuleRepository();
});

class SportRulesScreen extends ConsumerStatefulWidget {
  const SportRulesScreen({
    super.key,
    this.initialSportId = 'all',
  });

  final String initialSportId;

  @override
  ConsumerState<SportRulesScreen> createState() => _SportRulesScreenState();
}

class _SportRulesScreenState extends ConsumerState<SportRulesScreen> {
  late String _selectedSport;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  final _allSports = const [
    ('all', 'All Sports'),
    ('cricket', 'Cricket (ICC)'),
    ('football', 'Football (FIFA)'),
    ('kabaddi', 'Kabaddi (AKFI/PKL)'),
    ('basketball', 'Basketball (FIBA)'),
    ('badminton', 'Badminton (BWF)'),
    ('chess', 'Chess (FIDE)'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedSport = widget.initialSportId;
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(sportRuleRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Official Rules & Regulations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Official rules verified against ICC, FIFA, FIBA, PKL, and BWF rulebooks.'),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Real-time Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search rules (e.g. "free hit", "offside", "do or die")...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
              ),
            ),
          ),

          // Sport Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _allSports.map((sport) {
                final isSelected = _selectedSport == sport.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(sport.$2),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedSport = sport.$1);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Real-time Rule Cards List
          Expanded(
            child: StreamBuilder<List<SportRule>>(
              stream: repo.watchRules(
                sportId: _selectedSport,
                searchQuery: _searchQuery,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rules = snapshot.data ?? [];
                if (rules.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No rules found matching "$_searchQuery"',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text('Try searching for another keyword or sport.'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rules.length,
                  itemBuilder: (context, index) {
                    final rule = rules[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.shade800,
                          child: Icon(
                            switch (rule.sportId) {
                              'cricket' => Icons.sports_cricket,
                              'football' => Icons.sports_soccer,
                              'basketball' => Icons.sports_basketball,
                              'badminton' => Icons.sports_tennis,
                              'chess' => Icons.grid_view,
                              _ => Icons.sports,
                            },
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          rule.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade900.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  rule.officialSource,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                rule.category,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rule.description,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  children: rule.keywords.map((k) {
                                    return Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text('#$k',
                                          style: const TextStyle(fontSize: 10)),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
