import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

enum ActivityCategory {
  sportsSeason,
  tournament,
  standaloneMatch,
  trainingCamp,
  selectionTrials,
  coachingCamp,
  ceremonyWorkshop,
}

class CreateActivityWizardScreen extends ConsumerStatefulWidget {
  const CreateActivityWizardScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateActivityWizardScreen> createState() => _CreateActivityWizardScreenState();
}

class _CreateActivityWizardScreenState extends ConsumerState<CreateActivityWizardScreen> {
  int _currentStep = 0;

  // Step 1: Category Selection
  ActivityCategory _selectedCategory = ActivityCategory.sportsSeason;

  // Step 2: Activity Profile & Details
  final _nameController = TextEditingController(text: 'Monsoon Sports Festival 2026');
  final _descriptionController = TextEditingController(
    text: 'Annual multi-sport grassroots championship across village communities and schools.',
  );
  DateTime _startDate = DateTime.now().add(const Duration(days: 7));
  DateTime _endDate = DateTime.now().add(const Duration(days: 21));
  late TextEditingController _startDateController;
  late TextEditingController _endDateController;
  bool _startDateTBD = false;
  bool _endDateTBD = false;
  String _visibility = 'Public';

  @override
  void initState() {
    super.initState();
    _startDateController = TextEditingController(
      text: '${_startDate.year}-${_startDate.month.toString().padLeft(2, "0")}-${_startDate.day.toString().padLeft(2, "0")}',
    );
    _endDateController = TextEditingController(
      text: '${_endDate.year}-${_endDate.month.toString().padLeft(2, "0")}-${_endDate.day.toString().padLeft(2, "0")}',
    );
  }

  // Step 3: Sports Selection (Ordered India's Most Popular First)
  final List<String> _popularSports = [
    'Cricket',
    'Badminton',
    'Football',
    'Volleyball',
    'Athletics',
    'Table Tennis',
    'Chess',
    'Kabaddi',
    'Kho Kho',
    'Carrom',
    'Basketball',
    'Tennis',
    'Hockey',
    'Swimming',
    'Archery',
    'Boxing',
    'Wrestling',
    'Cycling',
    'Running',
    'Skating',
  ];
  final List<String> _extraSports = [
    'Squash',
    'Shooting',
    'Gymnastics',
    'Judo',
    'Taekwondo',
    'Rowing',
    'Sailing',
    'Weightlifting',
  ];
  final Set<String> _selectedSports = {'Cricket', 'Table Tennis', 'Chess', 'Kabaddi'};
  bool _showAllSports = false;

  // Step 4: Per-Sport Venue & Time Config
  final Map<String, String> _sportVenues = {};
  final Map<String, bool> _sportVenueTBD = {};
  final Map<String, bool> _sportDateTBD = {};
  final Map<String, bool> _sportTimeTBD = {};
  final _capacityController = TextEditingController(text: '450');
  final _feeController = TextEditingController(text: '100');

  // Step 5: Competition Format & Type
  String _competitionType = 'Championship';
  String _eligibility = 'Everyone';

  // Step 6: Registration Rules
  bool _registrationRequired = true;
  bool _approvalRequired = false;
  bool _waitlistEnabled = true;

  // Step 7: Optional Capability Switches (16 Modules)
  final Map<String, bool> _modules = {
    'Live Score': true,
    'QR Check-In': true,
    'Certificates': true,
    'Medals': true,
    'Trophy': true,
    'ELO Rating': true,
    'AI Team Formation': true,
    'Referee Assignment': true,
    'Volunteer Management': true,
    'Live Streaming': false,
    'Sponsors': true,
    'Food Coupons': false,
    'Medical Desk': true,
    'Gallery': true,
    'Announcements': true,
    'Push Notifications': true,
  };

  // Step 8: Notification Setup
  bool _notifyMembers = true;
  bool _sendPush = true;
  bool _sendEmail = true;
  bool _sendSMS = false;

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _capacityController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  int get _totalSteps {
    switch (_selectedCategory) {
      case ActivityCategory.sportsSeason:
        return 9;
      case ActivityCategory.tournament:
        return 8;
      case ActivityCategory.standaloneMatch:
        return 7;
      default:
        return 8;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'Create Activity • Sports Operating System Wizard',
      child: Column(
        children: [
          // Step Progress Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${_currentStep + 1} of $_totalSteps: ${_stepTitle(_currentStep)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Chip(
                      avatar: const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                      label: const Text('Draft Auto-Saved'),
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                      labelStyle: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),

          // Main Step Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStepContent(),
            ),
          ),

          // Bottom Wizard Control Navigation Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (_currentStep > 0)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                        onPressed: () => setState(() => _currentStep--),
                      ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Draft'),
                      onPressed: () => _saveDraft(),
                    ),
                  ],
                ),

                if (_currentStep < _totalSteps - 1)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () => setState(() => _currentStep++),
                  )
                else
                  ElevatedButton.icon(
                    icon: const Icon(Icons.rocket_launch),
                    label: const Text('Publish Activity Now', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    ),
                    onPressed: () => _publishActivity(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle(int step) {
    if (step == 0) return 'Select Activity Type';
    if (step == 1) return 'Activity Profile';
    if (step == 2) return 'Select Sports';
    if (step == 3) return 'Per-Sport Config';
    if (step == 4) return 'Format & Rules';
    if (step == 5) return 'Registration Setup';
    if (step == 6) return 'Optional Capabilities';
    if (step == 7) return 'Notifications';
    return 'Final Review & Publish';
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStepCategorySelection();
      case 1:
        return _buildStepActivityProfile();
      case 2:
        return _buildStepSportsSelection();
      case 3:
        return _buildStepPerSportConfig();
      case 4:
        return _buildStepFormatAndRules();
      case 5:
        return _buildStepRegistrationSetup();
      case 6:
        return _buildStepCapabilityModules();
      case 7:
        return _buildStepNotificationSetup();
      case 8:
        return _buildStepFinalReview();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Step 1: Category Selection ---
  Widget _buildStepCategorySelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What would you like to create?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('PlaySphere is a unified Sports Operating System. Everything begins from this single entry point.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),

        _buildCategoryCard(
          ActivityCategory.sportsSeason,
          title: '🏆 Sports Season',
          subtitle: 'Create a festival like IPL, Olympics, CM Cup, or Village Sports Festival',
        ),
        _buildCategoryCard(
          ActivityCategory.tournament,
          title: '🏅 Tournament',
          subtitle: 'Single sport tournament (Cricket Cup, Chess Championship, Kabaddi League)',
        ),
        _buildCategoryCard(
          ActivityCategory.standaloneMatch,
          title: '⚡ Standalone Match',
          subtitle: 'One match (Sunday Cricket Match, Practice Match, Friendly)',
        ),
        _buildCategoryCard(
          ActivityCategory.trainingCamp,
          title: '🏋️ Training Camp',
          subtitle: 'Athlete conditioning, fitness assessment & specialized camp',
        ),
        _buildCategoryCard(
          ActivityCategory.selectionTrials,
          title: '🎯 Selection Trial',
          subtitle: 'State/District trial for scouting top athletes',
        ),
        _buildCategoryCard(
          ActivityCategory.coachingCamp,
          title: '🎓 Coaching Camp',
          subtitle: 'Sports academy regular coaching sessions',
        ),
        _buildCategoryCard(
          ActivityCategory.ceremonyWorkshop,
          title: '🎉 Sports Event',
          subtitle: 'Prize Distribution, Opening/Closing Ceremony, Workshop, Executive Meeting',
        ),
      ],
    );
  }

  Widget _buildCategoryCard(ActivityCategory category, {required String title, required String subtitle}) {
    final isSelected = _selectedCategory == category;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(subtitle, style: const TextStyle(fontSize: 13)),
        ),
        trailing: Radio<ActivityCategory>(
          value: category,
          groupValue: _selectedCategory,
          onChanged: (val) => setState(() => _selectedCategory = val!),
        ),
        onTap: () => setState(() => _selectedCategory = category),
      ),
    );
  }

  // --- Step 2: Activity Profile & Details ---
  Widget _buildStepActivityProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Activity Details & Duration', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Activity Name *',
            hintText: 'e.g. Monsoon Sports Festival 2026',
            prefixIcon: Icon(Icons.badge),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _descriptionController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Overview, objectives, and general guidelines',
            prefixIcon: Icon(Icons.description),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Visibility Dropdown
        DropdownButtonFormField<String>(
          value: _visibility,
          decoration: const InputDecoration(
            labelText: 'Visibility',
            prefixIcon: Icon(Icons.visibility),
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Public', child: Text('Public (Open to All)')),
            DropdownMenuItem(value: 'Private', child: Text('Private (Members Only)')),
            DropdownMenuItem(value: 'Invite Only', child: Text('Invite Only')),
          ],
          onChanged: (val) => setState(() => _visibility = val!),
        ),
        const SizedBox(height: 16),

        // Date Pickers with TBD Checkboxes
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activity Duration', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _startDateController,
                            enabled: !_startDateTBD,
                            decoration: InputDecoration(
                              labelText: 'Start Date (YYYY-MM-DD)',
                              prefixIcon: const Icon(Icons.calendar_month),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today),
                                onPressed: _startDateTBD
                                    ? null
                                    : () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _startDate,
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime.now().add(const Duration(days: 730)),
                                        );
                                        if (picked != null) {
                                          setState(() {
                                            _startDate = picked;
                                            _startDateController.text =
                                                '${picked.year}-${picked.month.toString().padLeft(2, "0")}-${picked.day.toString().padLeft(2, "0")}';
                                          });
                                        }
                                      },
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Start Date: Not Yet Decided (TBD)', style: TextStyle(fontSize: 12)),
                            value: _startDateTBD,
                            onChanged: (val) => setState(() => _startDateTBD = val!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _endDateController,
                            enabled: !_endDateTBD,
                            decoration: InputDecoration(
                              labelText: 'End Date (YYYY-MM-DD)',
                              prefixIcon: const Icon(Icons.calendar_month),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today),
                                onPressed: _endDateTBD
                                    ? null
                                    : () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _endDate,
                                          firstDate: _startDate,
                                          lastDate: DateTime.now().add(const Duration(days: 730)),
                                        );
                                        if (picked != null) {
                                          setState(() {
                                            _endDate = picked;
                                            _endDateController.text =
                                                '${picked.year}-${picked.month.toString().padLeft(2, "0")}-${picked.day.toString().padLeft(2, "0")}';
                                          });
                                        }
                                      },
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('End Date: Not Yet Decided (TBD)', style: TextStyle(fontSize: 12)),
                            value: _endDateTBD,
                            onChanged: (val) => setState(() => _endDateTBD = val!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 3: Sports Selection (India's Most Popular First) ---
  Widget _buildStepSportsSelection() {
    final allSports = _showAllSports ? [..._popularSports, ..._extraSports] : _popularSports;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Included Sports', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          _selectedCategory == ActivityCategory.tournament
              ? 'Select 1 Sport for this Tournament.'
              : 'Multi-select sports to include in this sports experience.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),

        Text('⭐ Most Popular Sports in India', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: allSports.map((sport) {
            final isSelected = _selectedSports.contains(sport);
            return FilterChip(
              avatar: Icon(
                isSelected ? Icons.check_circle : Icons.sports_soccer,
                size: 16,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              label: Text(sport),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (_selectedCategory == ActivityCategory.tournament) {
                    _selectedSports.clear();
                    if (selected) _selectedSports.add(sport);
                  } else {
                    if (selected) {
                      _selectedSports.add(sport);
                    } else {
                      _selectedSports.remove(sport);
                    }
                  }
                });
              },
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        TextButton.icon(
          icon: Icon(_showAllSports ? Icons.expand_less : Icons.expand_more),
          label: Text(_showAllSports ? 'Show Less Sports' : 'View All 100+ Sports Catalog'),
          onPressed: () => setState(() => _showAllSports = !_showAllSports),
        ),
      ],
    );
  }

  // --- Step 4: Per-Sport Config ---
  Widget _buildStepPerSportConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Per-Sport Venue & Schedule Config', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Configure individual venue, date, and capacity rules per sport.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),

        ..._selectedSports.map((sport) {
          final isVenueTBD = _sportVenueTBD[sport] ?? false;
          final isDateTBD = _sportDateTBD[sport] ?? false;
          final isTimeTBD = _sportTimeTBD[sport] ?? false;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sports, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(sport, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const Divider(height: 20),

                  // Venue Row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          enabled: !isVenueTBD,
                          decoration: InputDecoration(
                            labelText: '$sport Venue',
                            hintText: isVenueTBD ? 'Venue TBD' : 'e.g. Shivaji Ground Court 1',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (val) => _sportVenues[sport] = val,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Venue TBD'),
                        selected: isVenueTBD,
                        onSelected: (val) => setState(() => _sportVenueTBD[sport] = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Date & Time TBD Checkboxes
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Date TBD'),
                          value: isDateTBD,
                          onChanged: (val) => setState(() => _sportDateTBD[sport] = val!),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Time TBD'),
                          value: isTimeTBD,
                          onChanged: (val) => setState(() => _sportTimeTBD[sport] = val!),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- Step 5: Competition Format & Type ---
  Widget _buildStepFormatAndRules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Competition Type & Format', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: _competitionType,
          decoration: const InputDecoration(
            labelText: 'Competition Format Type',
            prefixIcon: Icon(Icons.emoji_events),
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Championship', child: Text('Championship League')),
            DropdownMenuItem(value: 'Knockout', child: Text('Knockout Tournament')),
            DropdownMenuItem(value: 'Round Robin', child: Text('Round Robin League')),
            DropdownMenuItem(value: 'Swiss', child: Text('Swiss Tournament Format')),
            DropdownMenuItem(value: 'Friendly', child: Text('Friendly Match')),
            DropdownMenuItem(value: 'Selection Trial', child: Text('Selection Trial')),
          ],
          onChanged: (val) => setState(() => _competitionType = val!),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: _eligibility,
          decoration: const InputDecoration(
            labelText: 'Participant Category & Age Group',
            prefixIcon: Icon(Icons.group_work),
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Everyone', child: Text('Everyone (Open Public)')),
            DropdownMenuItem(value: 'Only Group Members', child: Text('Only Group Members')),
            DropdownMenuItem(value: 'Age 10-14', child: Text('Youth (Age 10-14)')),
            DropdownMenuItem(value: 'Age 15-18', child: Text('Junior (Age 15-18)')),
            DropdownMenuItem(value: 'Women Only', child: Text('Women Only')),
            DropdownMenuItem(value: 'Men Only', child: Text('Men Only')),
          ],
          onChanged: (val) => setState(() => _eligibility = val!),
        ),
      ],
    );
  }

  // --- Step 6: Registration Setup ---
  Widget _buildStepRegistrationSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registration Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Maximum Participants',
                  prefixIcon: Icon(Icons.people),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Entry Fee (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text('Registration Required'),
          subtitle: const Text('Require athletes to submit entry forms before playing.'),
          value: _registrationRequired,
          onChanged: (val) => setState(() => _registrationRequired = val),
        ),
        SwitchListTile(
          title: const Text('Admin Approval Required'),
          subtitle: const Text('Manually review and approve each registration.'),
          value: _approvalRequired,
          onChanged: (val) => setState(() => _approvalRequired = val),
        ),
        SwitchListTile(
          title: const Text('Enable Wait List'),
          subtitle: const Text('Auto-promote waitlisted athletes when entries open.'),
          value: _waitlistEnabled,
          onChanged: (val) => setState(() => _waitlistEnabled = val),
        ),
      ],
    );
  }

  // --- Step 7: Optional Capability Switches (16 Modules) ---
  Widget _buildStepCapabilityModules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Optional Platform Capabilities', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Toggle enterprise capabilities for this activity experience.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),

        ..._modules.keys.map((key) {
          return SwitchListTile(
            title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
            value: _modules[key]!,
            onChanged: (val) => setState(() => _modules[key] = val),
          );
        }),
      ],
    );
  }

  // --- Step 8: Notification Setup ---
  Widget _buildStepNotificationSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notifications & Member Outreach', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text('Notify All Members?'),
          subtitle: const Text('Broadcast activity announcement across organization.'),
          value: _notifyMembers,
          onChanged: (val) => setState(() => _notifyMembers = val),
        ),
        const Divider(),

        CheckboxListTile(
          title: const Text('Send Push Notifications (FCM)'),
          value: _sendPush,
          onChanged: (val) => setState(() => _sendPush = val!),
        ),
        CheckboxListTile(
          title: const Text('Send Email Broadcast'),
          value: _sendEmail,
          onChanged: (val) => setState(() => _sendEmail = val!),
        ),
        CheckboxListTile(
          title: const Text('Send SMS Alerts'),
          value: _sendSMS,
          onChanged: (val) => setState(() => _sendSMS = val!),
        ),
      ],
    );
  }

  // --- Step 9: Pre-Flight Review Screen ---
  Widget _buildStepFinalReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pre-Flight Review Screen', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Review your activity specs before publishing to the organization feed.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),

        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_nameController.text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ],
                ),
                const Divider(height: 24),

                Text('• Type: ${_selectedCategory.name.toUpperCase()}'),
                const SizedBox(height: 4),
                Text('• Sports Included: ${_selectedSports.join(", ")}'),
                const SizedBox(height: 4),
                Text('• Format: $_competitionType • Category: $_eligibility'),
                const SizedBox(height: 4),
                Text('• Capacity: ${_capacityController.text} Players • Fee: ₹${_feeController.text}'),
                const SizedBox(height: 4),
                Text('• Enabled Modules: ${_modules.keys.where((k) => _modules[k]!).join(", ")}'),
                const Divider(height: 24),

                const Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Estimated Member Reach: 3,248 Members will be notified instantly', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _saveDraft() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Draft saved for "${_nameController.text}". You can return anytime.')),
    );
  }

  void _publishActivity() {
    final store = ref.read(playSphereStoreProvider);
    for (final sport in _selectedSports) {
      store.addCompetition(name: '${_nameController.text} - $sport', sport: sport.toLowerCase());
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Activity "${_nameController.text}" published to organization feed!')),
    );
    context.go('/org/${widget.orgId}');
  }
}
