import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/portal_scaffold.dart';

class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.district,
    required this.type,
    required this.capacity,
    required this.facilities,
    required this.courtsCount,
  });

  final String id;
  final String name;
  final String district;
  final String type;
  final int capacity;
  final List<String> facilities;
  final int courtsCount;
}

class VenueManagementScreen extends ConsumerStatefulWidget {
  const VenueManagementScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<VenueManagementScreen> createState() => _VenueManagementScreenState();
}

class _VenueManagementScreenState extends ConsumerState<VenueManagementScreen> {
  final List<Venue> _venues = [
    const Venue(
      id: 'v1',
      name: 'Maram Community Indoor Court',
      district: 'Hyderabad',
      type: 'Indoor Badminton & TT Hall',
      capacity: 350,
      facilities: ['Floodlights', 'Synthetic Flooring', 'Changing Rooms', 'First Aid'],
      courtsCount: 4,
    ),
    const Venue(
      id: 'v2',
      name: 'Garlapati Village Sports Ground',
      district: 'Rangareddy',
      type: 'Outdoor Cricket & Football Field',
      capacity: 1200,
      facilities: ['Cricket Turf', 'Floodlights', 'PA System'],
      courtsCount: 2,
    ),
    const Venue(
      id: 'v3',
      name: 'Telangana State Sports Complex',
      district: 'Hyderabad',
      type: 'Multi-Sport Stadium Complex',
      capacity: 5000,
      facilities: ['Olympic Pool', 'Synthetic Track', 'Kabaddi Mats', 'Gymnasium'],
      courtsCount: 12,
    ),
  ];

  String _selectedDistrict = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = _venues.where((v) {
      return _selectedDistrict == 'All' || v.district == _selectedDistrict;
    }).toList();

    return PortalScaffold(
      title: 'Infrastructure & Venue Manager',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Filter Header Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.location_city, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text('Filter District:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All Districts')),
                        DropdownMenuItem(value: 'Hyderabad', child: Text('Hyderabad')),
                        DropdownMenuItem(value: 'Rangareddy', child: Text('Rangareddy')),
                      ],
                      onChanged: (val) => setState(() => _selectedDistrict = val!),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Venues List
          ...filtered.map((venue) {
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            venue.district.toUpperCase(),
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        Chip(
                          avatar: const Icon(Icons.stadium, size: 14),
                          label: Text('${venue.courtsCount} Courts/Fields'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      venue.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(venue.type, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 12),

                    // Facilities Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: venue.facilities.map((fac) {
                        return Chip(
                          label: Text(fac),
                          backgroundColor: Colors.grey.withValues(alpha: 0.1),
                          labelStyle: const TextStyle(fontSize: 11),
                        );
                      }).toList(),
                    ),
                    const Divider(height: 24),

                    // Actions Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Capacity: ${venue.capacity} spectators', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.event_seat, size: 16),
                          label: const Text('Book Facility Slot'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                          onPressed: () {
                            _showBookingDialog(context, venue);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showBookingDialog(BuildContext context, Venue venue) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Book Slot: ${venue.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Select Court / Field for ${venue.type}:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: 'Court 1',
                items: List.generate(venue.courtsCount, (i) => DropdownMenuItem(value: 'Court ${i + 1}', child: Text('Court ${i + 1}'))),
                onChanged: (_) {},
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Booking Time (e.g. 09:00 AM - 11:00 AM)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Slot confirmed for ${venue.name}! No schedule conflicts.')),
                );
              },
              child: const Text('Confirm Slot'),
            ),
          ],
        );
      },
    );
  }
}
