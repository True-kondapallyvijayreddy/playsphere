import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/data/image_composer.dart';
import 'package:playsphere/shared/identity.dart';
import 'package:playsphere/shared/ps_banner.dart';
import 'package:playsphere/shared/season_branding_field.dart';

/// A season's crest and banner are the one pair of pictures in the product
/// that are chosen *before* the thing they belong to exists. That is what
/// these pin down: the preview has to draw bytes that have not been uploaded,
/// and a season with neither picture still has to render as a finished header
/// rather than as two empty boxes.
void main() {
  // A 1x1 transparent PNG. Small enough to inline, real enough that
  // `Image.memory` decodes it instead of throwing.
  final png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  PickedImage image() => PickedImage(bytes: png, contentType: 'image/png');

  group('PsBanner crest', () {
    testWidgets('draws no crest when there is no logo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PsBanner(
              seed: 'season-1',
              fallbackIcon: Icons.emoji_events_outlined,
              child: Text('District Championship'),
            ),
          ),
        ),
      );

      // The empty state is a complete header, not a header with a hole in it.
      expect(find.byType(PsCrest), findsNothing);
      expect(find.text('District Championship'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws the crest beside the name when there is one',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PsBanner(
              logoBytes: png,
              logoName: 'Nizampet Sports Week',
              seed: 'season-1',
              child: const Text('Nizampet Sports Week'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PsCrest), findsOneWidget);
      expect(find.text('Nizampet Sports Week'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('staged bytes are drawn without a network fetch',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PsBanner(imageBytes: png, seed: 'season-1'),
          ),
        ),
      );
      await tester.pump();

      // `Image.memory`, not `CachedNetworkImage`: on a create form there is no
      // URL to fetch, and a preview that silently fell back to generated art
      // would tell the organizer their pick had not registered.
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('SeasonBrandingField', () {
    testWidgets('offers both pictures by name before either is picked',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeasonBrandingField(
              branding: SeasonBranding(),
              name: 'Nizampet Sports Week 2026',
              onChanged: () {},
            ),
          ),
        ),
      );

      // The complaint this block answers was "I cannot add a logo or a
      // banner". Both have to be findable as words, not only as a tappable
      // picture somebody has to guess is a button.
      expect(find.text('Add logo'), findsOneWidget);
      expect(find.text('Add banner'), findsOneWidget);
      expect(find.text('Nizampet Sports Week 2026'), findsOneWidget);
    });

    testWidgets('a staged pick flips the labels and offers a way back',
        (tester) async {
      final branding = SeasonBranding(logo: image(), banner: image());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeasonBrandingField(
              branding: branding,
              name: 'Season',
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Change logo'), findsOneWidget);
      expect(find.text('Change banner'), findsOneWidget);
      expect(find.text('Clear picked images'), findsOneWidget);
    });

    testWidgets('artwork already saved counts as present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeasonBrandingField(
              branding: SeasonBranding(),
              name: 'Season',
              logoUrl: 'https://example.test/logo.png',
              bannerUrl: 'https://example.test/banner.jpg',
              onChanged: () {},
            ),
          ),
        ),
      );

      // Editing an existing tournament must not invite the organizer to "add"
      // a logo it already has, and with nothing newly picked there is nothing
      // to take back.
      expect(find.text('Change logo'), findsOneWidget);
      expect(find.text('Change banner'), findsOneWidget);
      expect(find.text('Clear picked images'), findsNothing);
    });
  });

  group('SeasonBranding', () {
    test('is empty until something is picked', () {
      final branding = SeasonBranding();
      expect(branding.isEmpty, isTrue);
      branding.logo = image();
      expect(branding.isEmpty, isFalse);
    });
  });

  group('the models carry both pictures', () {
    test('a season round-trips its logo and its banner', () {
      const season = Tournament(
        id: 't1',
        orgId: 'org1',
        name: 'Nizampet Sports Week',
        status: TournamentStatus.entriesOpen,
        logoUrl: 'https://example.test/logo.png',
        bannerUrl: 'https://example.test/banner.jpg',
      );

      expect(season.toCreate()['logoUrl'], 'https://example.test/logo.png');
      expect(season.toCreate()['bannerUrl'], 'https://example.test/banner.jpg');

      // Neither may travel on `toUpdate`: the edit sheet does not own them,
      // and an organizer fixing a typo in the name must not wipe artwork
      // somebody else uploaded. `uploadSeasonLogo`/`uploadSeasonBanner` are
      // one-field writes for exactly this reason.
      expect(season.toUpdate().containsKey('logoUrl'), isFalse);
      expect(season.toUpdate().containsKey('bannerUrl'), isFalse);
    });
  });
}
