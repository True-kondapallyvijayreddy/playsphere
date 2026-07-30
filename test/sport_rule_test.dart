import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/sport_rule.dart';
import 'package:playsphere/data/sport_rule_repository.dart';

void main() {
  group('Multi-Sport Official Rule Database System', () {
    test('SportRule model serializes and deserializes governing body citations', () {
      const rule = SportRule(
        id: 'cricket_no_ball',
        sportId: 'cricket',
        category: 'Bowling',
        title: 'No Ball & Free Hit Rule',
        description: 'No ball awards 1 run penalty and a Free Hit.',
        officialSource: 'ICC Law 21.5',
        keywords: ['no ball', 'free hit', 'penalty'],
      );

      final map = rule.toMap();
      expect(map['sportId'], equals('cricket'));
      expect(map['officialSource'], equals('ICC Law 21.5'));

      final restored = SportRule.fromDoc(map, 'cricket_no_ball');
      expect(restored.title, equals('No Ball & Free Hit Rule'));
      expect(restored.officialSource, equals('ICC Law 21.5'));
    });

    test('SportRuleRepository filters rules by sport and real-time search query', () async {
      const repo = SportRuleRepository();

      final cricketRules = await repo.watchRules(sportId: 'cricket').first;
      expect(cricketRules.isNotEmpty, isTrue);
      expect(cricketRules.every((r) => r.sportId == 'cricket'), isTrue);

      final freeHitSearch = await repo.watchRules(searchQuery: 'free hit').first;
      expect(freeHitSearch.isNotEmpty, isTrue);
      expect(freeHitSearch.first.officialSource, contains('ICC'));

      final offsideSearch = await repo.watchRules(searchQuery: 'offside').first;
      expect(offsideSearch.isNotEmpty, isTrue);
      expect(offsideSearch.first.officialSource, contains('FIFA'));

      final doOrDieSearch = await repo.watchRules(searchQuery: 'do or die').first;
      expect(doOrDieSearch.isNotEmpty, isTrue);
      expect(doOrDieSearch.first.officialSource, contains('AKFI'));
    });
  });
}
