import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class JoinClubScreen extends ConsumerStatefulWidget {
  const JoinClubScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<JoinClubScreen> createState() => _JoinClubScreenState();
}

class _JoinClubScreenState extends ConsumerState<JoinClubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController(text: 'KAKATIYA-2026');

  final List<Map<String, String>> _pendingRequests = [
    {
      'id': 'req-1',
      'name': 'Rahul Verma',
      'sport': 'Cricket & Badminton',
      'date': 'Just now',
    },
    {
      'id': 'req-2',
      'name': 'Priya Patel',
      'sport': 'Table Tennis',
      'date': '10 mins ago',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final activeOrg = store.activeOrganization;
    final inviteCode = '${activeOrg.name.split(" ").first.toUpperCase()}-2026';
    final shareUrl = 'https://playsphere.app/join/$inviteCode';

    return PortalScaffold(
      title: 'Club Join & Member Invites',
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Join Club by Code'),
              Tab(icon: Icon(Icons.share), text: 'Admin WhatsApp Invite Hub'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Enter Invite Code to Join
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(Icons.vpn_key, color: Theme.of(context).colorScheme.primary, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Have a Club Invite Code?', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  const Text('Enter the code shared by your Club Admin to join and register for club events.', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Enter 6-Digit Club Invite Code *',
                        hintText: 'e.g. KAKATIYA-2026',
                        prefixIcon: Icon(Icons.lock_open),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      icon: const Icon(Icons.group_add),
                      label: const Text('Accept Invite & Join Club', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Joined club successfully with code ${_codeController.text}! You can now register for club events.')),
                        );
                      },
                    ),
                  ],
                ),

                // Tab 2: Admin WhatsApp Share & Join Requests Hub
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              'Share ${activeOrg.name} Invite Link',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            QrImageView(
                              data: shareUrl,
                              version: QrVersions.auto,
                              size: 160.0,
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              'Invite Code: $inviteCode',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(shareUrl, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 16),

                            ElevatedButton.icon(
                              icon: const Icon(Icons.send),
                              label: const Text('Share Invite on WhatsApp'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Copied WhatsApp invite link for $inviteCode!')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text('Pending Member Join Requests', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    if (_pendingRequests.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: Text('No pending join requests.')),
                        ),
                      )
                    else
                      ..._pendingRequests.map((req) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.withValues(alpha: 0.2),
                              child: Text(req['name']![0]),
                            ),
                            title: Text(req['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${req['sport']} • Requested ${req['date']}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle, color: Colors.green),
                                  onPressed: () {
                                    setState(() => _pendingRequests.remove(req));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Approved ${req['name']}! Added to club roster.')),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red),
                                  onPressed: () {
                                    setState(() => _pendingRequests.remove(req));
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
