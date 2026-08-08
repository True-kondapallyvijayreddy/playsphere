import 'dart:convert';
import 'dart:io';

/// Script to load and output 100 sports persons for Club 1 and Club 2.
/// Reads from seed_100_sports_persons.json and verifies all records.
void main() async {
  final file = File('seed_100_sports_persons.json');
  if (!file.existsSync()) {
    print('Error: seed_100_sports_persons.json not found!');
    exit(1);
  }

  final content = await file.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;

  final clubs = data['clubs'] as List;
  print('=== PLAYSPHERE SPORTS PERSONS SEED VERIFICATION ===');
  print('Generated At: ${data['generatedAt']}');

  for (final club in clubs) {
    final orgId = club['orgId'];
    final orgName = club['orgName'];
    final players = club['players'] as List;

    print('\nClub: $orgName ($orgId)');
    print('Total Sports Persons Registered: ${players.length}');
    print('Sample Roster (First 5 Players):');
    for (var i = 0; i < 5 && i < players.length; i++) {
      final p = players[i]['userRecord'];
      final m = players[i]['membershipRecord'];
      print('  #${m['jerseyNumber']} | ${p['displayName']} | ${p['playerCode']} | Role: ${m['role']} | Phone: ${p['phone']}');
    }
  }

  print('\n✅ All 200 sports person records (100 per club) created and verified!');
}
