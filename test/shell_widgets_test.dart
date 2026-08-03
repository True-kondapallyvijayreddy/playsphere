import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/shared/live_dot.dart';
import 'package:playsphere/shared/playsphere_logo.dart';

/// The two widgets that appear on every signed-in screen, and so are the two
/// whose defects are seen most and noticed least.
void main() {
  group('PlaySphereLogo', () {
    testWidgets('scales down instead of overflowing a slot too narrow for it',
        (tester) async {
      // 224px is what the module drawer actually leaves the wordmark: a 304px
      // Drawer, less its padding, less the close button. At markSize 34 /
      // fontSize 21 the logo wants ~252px, so before it learned to scale it
      // painted the overflow stripes and clipped the tail off "Sphere" on
      // every device, in every session.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 224,
                child: Row(
                  children: [
                    Expanded(
                      child: PlaySphereLogo(markSize: 34, fontSize: 21),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PlaySphereLogo), findsOneWidget);
      expect(tester.getSize(find.byType(PlaySphereLogo)).width,
          lessThanOrEqualTo(224));
    });

    testWidgets('keeps its natural size when there is room', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: PlaySphereLogo())),
        ),
      );

      expect(tester.takeException(), isNull);
      // Unbounded-ish width must not send it through a flex assert.
      expect(find.text('PlaySphere'), findsOneWidget);
    });
  });

  group('LiveDot', () {
    Widget harness({required bool disableAnimations}) => MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: LiveDot()),
          ),
        );

    testWidgets('pulses while a match is live', (tester) async {
      await tester.pumpWidget(harness(disableAnimations: false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('holds still, and solid, when the phone asks for less motion',
        (tester) async {
      await tester.pumpWidget(harness(disableAnimations: true));

      // The assertion is as much that this returns at all: an unconditional
      // repeat() leaves the tree permanently unsettled, which is both a
      // battery cost on a 2GB device and the reason no widget test could
      // pumpAndSettle a screen showing a live match.
      await tester.pumpAndSettle();

      expect(tester.hasRunningAnimations, isFalse);
      final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('starts pulsing if the setting is turned off while open',
        (tester) async {
      await tester.pumpWidget(harness(disableAnimations: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(harness(disableAnimations: false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.hasRunningAnimations, isTrue);
    });
  });
}
