import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';
import 'package:playsphere/shared/identity.dart';
import 'package:playsphere/shared/ps_banner.dart';
import 'package:playsphere/shared/ui_kit.dart';

/// The generated identity layer is what makes every upload in PlaySphere
/// optional. If a club with no crest, a player with no photo or a season with
/// no banner ever renders as a hole, an "optional" picture stops being
/// optional in practice — so the no-image path is the one worth pinning down.
void main() {
  group('initials', () {
    test('a person gets one letter and a club gets two', () {
      expect(PsIdentity.initials('Vijay Reddy'), 'V');
      expect(PsIdentity.initials('Warangal Sports Club', max: 2), 'WS');
    });

    test('a one-word club name does not invent a second letter', () {
      expect(PsIdentity.initials('Gymkhana', max: 2), 'G');
    });

    test('an empty or blank name is a question mark, never a crash', () {
      expect(PsIdentity.initials(''), '?');
      expect(PsIdentity.initials('   '), '?');
      expect(PsIdentity.initials('   ', max: 2), '?');
    });

    test('a multi-code-unit first glyph survives whole', () {
      // The bug in every hand-rolled `name[0]` this replaced: slicing a
      // Devanagari or Telugu cluster mid-way renders a replacement box. The
      // whole grapheme cluster is kept — "वि" is one written glyph (व plus
      // its vowel sign), not two — which is the point.
      expect(PsIdentity.initials('विजय'), 'वि');
      expect(PsIdentity.initials('तेलंगाना खेल', max: 2), 'तेखे');
      expect(PsIdentity.initials('తెలంగాణ క్రీడలు', max: 2), isNotEmpty);
      expect(PsIdentity.initials('తెలంగాణ క్రీడలు', max: 2), isNot(contains('\uFFFD')));
    });

    test('runs of whitespace do not produce empty words', () {
      expect(PsIdentity.initials('Warangal    Sports', max: 2), 'WS');
    });
  });

  group('colour', () {
    test('is stable for the same seed', () {
      expect(PsIdentity.color('org-123'), PsIdentity.color('org-123'));
    });

    test('is keyed on the seed, so a rename keeps the colour', () {
      // Both calls pass the id; the display name is not part of the input.
      expect(PsIdentity.color('org-123'), PsIdentity.color('org-123'));
      expect(PsIdentity.color('org-123'), isNot(PsIdentity.color('org-124')));
    });

    test('a null or empty seed still yields a colour rather than throwing', () {
      expect(PsIdentity.color(null), isA<Color>());
      expect(PsIdentity.color(''), isA<Color>());
    });

    test('the hash never goes negative, so the palette index is always valid',
        () {
      for (final seed in ['', 'a', 'org-999', '🏏', 'తెలంగాణ']) {
        expect(PsIdentity.hash(seed), greaterThanOrEqualTo(0));
      }
    });
  });

  group('every sport has a visual', () {
    test('SportVisual covers the whole catalogue', () {
      // A sport added to `SportCatalog` without a colour here falls through to
      // the grey fallback, which now costs it a crest colour and a banner as
      // well as an icon. Five sports were in exactly that state.
      final missing = [
        for (final spec in SportCatalog.all)
          if (!SportVisual.knownIds.contains(spec.id)) spec.id,
      ];
      expect(missing, isEmpty, reason: 'sports with no SportVisual entry');
    });
  });

  group('nothing needs an image to render', () {
    testWidgets('a person with no photo still draws', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PsAvatar(name: 'Vijay Reddy'))),
      );
      expect(find.text('V'), findsOneWidget);
    });

    testWidgets('a club with no crest still draws', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PsCrest(name: 'Warangal Sports Club', seed: 'org-1'),
          ),
        ),
      );
      expect(find.text('WS'), findsOneWidget);
    });

    testWidgets('an event with no banner still draws a header', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PsBanner(
              sportId: 'cricket',
              seed: 'comp-1',
              child: Text('Sports Week 2026'),
            ),
          ),
        ),
      );
      expect(find.text('Sports Week 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a season with no sport and no banner still draws',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PsBanner(
              seed: 'tournament-1',
              fallbackIcon: Icons.emoji_events_outlined,
              child: Text('District Championship'),
            ),
          ),
        ),
      );
      expect(find.text('District Championship'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
