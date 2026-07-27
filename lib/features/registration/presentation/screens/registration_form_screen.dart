import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../core/network/firebase_service.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class RegistrationFormScreen extends ConsumerStatefulWidget {
  const RegistrationFormScreen({
    super.key,
    required this.orgId,
    required this.eventId,
  });

  final String orgId;
  final String eventId;

  @override
  ConsumerState<RegistrationFormScreen> createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends ConsumerState<RegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _skillLevel = 'Intermediate (1200-1400 ELO)';
  String _entrantType = 'Individual';
  bool _medicalAttested = true;
  bool _registered = false;
  String _ticketCode = '';

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final member = store.member;

    return PortalScaffold(
      title: 'Tournament Registration',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(Icons.how_to_reg, color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Event Entry Form',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text('Event ID: ${widget.eventId} • Org: ${widget.orgId}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Player Details
                    Text('Registrant Profile', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: member.name,
                      decoration: const InputDecoration(
                        labelText: 'Player Name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),

                    // Skill Level Dropdown
                    DropdownButtonFormField<String>(
                      value: _skillLevel,
                      decoration: const InputDecoration(
                        labelText: 'Self-Declared Skill Bracket',
                        prefixIcon: Icon(Icons.sports_score),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Beginner (<1200 ELO)', child: Text('Beginner (<1200 ELO)')),
                        DropdownMenuItem(value: 'Intermediate (1200-1400 ELO)', child: Text('Intermediate (1200-1400 ELO)')),
                        DropdownMenuItem(value: 'Advanced (1400-1600 ELO)', child: Text('Advanced (1400-1600 ELO)')),
                        DropdownMenuItem(value: 'Elite (>1600 ELO)', child: Text('Elite (>1600 ELO)')),
                      ],
                      onChanged: (val) => setState(() => _skillLevel = val!),
                    ),
                    const SizedBox(height: 16),

                    // Entrant Type / Category
                    DropdownButtonFormField<String>(
                      value: _entrantType,
                      decoration: const InputDecoration(
                        labelText: 'Entrant Category (Individual, Club, College, Corporate)',
                        prefixIcon: Icon(Icons.group),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Individual', child: Text('👤 Individual Player Singles Entry')),
                        DropdownMenuItem(value: 'Club', child: Text('🛡️ Club / Sports Group Entry')),
                        DropdownMenuItem(value: 'College', child: Text('🎓 College / University Team Entry')),
                        DropdownMenuItem(value: 'Corporate', child: Text('🏢 Corporate / Company Team Entry')),
                        DropdownMenuItem(value: 'Community', child: Text('🏘️ Community / Village Team Entry')),
                      ],
                      onChanged: (val) => setState(() => _entrantType = val!),
                    ),
                    const SizedBox(height: 16),

                    if (_entrantType != 'Individual') ...[
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: '$_entrantType / Organization Name *',
                          hintText: 'e.g. Kakatiya University Sports Club',
                          prefixIcon: const Icon(Icons.business),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (val) => val == null || val.isEmpty ? 'Please enter your $_entrantType name' : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Medical & Consent Checkbox
                    CheckboxListTile(
                      value: _medicalAttested,
                      onChanged: (val) => setState(() => _medicalAttested = val!),
                      title: const Text('I attest to medical fitness for physical sport activity'),
                      subtitle: const Text('Complies with PlaySphere Trust & Safety guidelines'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Confirm & Complete Registration', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            setState(() {
                              _registered = true;
                              _ticketCode = 'PLAYSPHERE-TICKET-${widget.eventId}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                            });

                            // Save registration directly to Firebase Firestore
                            FirebaseService.saveRegistration(
                              eventId: widget.eventId,
                              memberId: store.member.id,
                              entrantType: _entrantType,
                              registrationData: {
                                'skill_level': _skillLevel,
                                'medical_attested': _medicalAttested,
                                'ticket_code': _ticketCode,
                              },
                            );

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Registration Saved in Firebase Firestore! Ticket generated.')),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Digital Ticket Card (Shown on Successful Registration)
          if (_registered) ...[
            const SizedBox(height: 20),
            Card(
              color: Colors.green.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 28),
                        SizedBox(width: 8),
                        Text('Digital Event Pass & Check-In Ticket', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    QrImageView(
                      data: _ticketCode,
                      version: QrVersions.auto,
                      size: 160.0,
                    ),
                    const SizedBox(height: 12),
                    Text(_ticketCode, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 12)),
                    const SizedBox(height: 4),
                    const Text('Present this QR code at the venue entrance for check-in.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
