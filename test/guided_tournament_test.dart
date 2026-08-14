import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/shared/wizard.dart';

/// The wizard shell that four creation flows share.
///
/// The behaviour worth protecting is the navigation contract, not the
/// chrome: a step that cannot be advanced past must not be advanceable, the
/// back arrow must walk the steps rather than abandon the form, and a slow
/// submit must not be pressable twice. Each of those failures produces a
/// duplicate tournament or a lost form, which is what people notice.
void main() {
  Widget harness({
    required List<WizardStep> steps,
    required Future<void> Function() onSubmit,
    bool submitting = false,
    String submitLabel = 'Create',
  }) {
    return MaterialApp(
      home: WizardScaffold(
        title: 'Create Tournament',
        steps: steps,
        onSubmit: onSubmit,
        submitLabel: submitLabel,
        submitting: submitting,
      ),
    );
  }

  List<WizardStep> threeSteps({bool Function()? gateFirst}) => [
        WizardStep(
          title: 'Details',
          canAdvance: gateFirst,
          builder: (_) => const Text('step one body'),
        ),
        WizardStep(title: 'Format', builder: (_) => const Text('step two body')),
        WizardStep(title: 'Review', builder: (_) => const Text('step three body')),
      ];

  testWidgets('shows the step counter and advances through steps',
      (tester) async {
    await tester.pumpWidget(harness(steps: threeSteps(), onSubmit: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('step one body'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Format'), findsOneWidget);
  });

  testWidgets('the last step swaps Next for the submit label', (tester) async {
    await tester.pumpWidget(harness(
      steps: threeSteps(),
      onSubmit: () async {},
      submitLabel: 'Create Tournament',
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Create Tournament'), findsOneWidget);
  });

  testWidgets('submit runs only on the final step', (tester) async {
    var submits = 0;
    await tester.pumpWidget(harness(
      steps: threeSteps(),
      onSubmit: () async => submits++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(submits, 0, reason: 'Next on a middle step must not create anything');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(submits, 1);
  });

  testWidgets('a step that cannot advance disables Next', (tester) async {
    // Wrapped in a stateful host that rebuilds the whole WizardScaffold,
    // which is exactly how the real flows work: a step's field calls
    // setState on the flow's own State, and the footer re-reads canAdvance
    // on the rebuild that follows.
    await tester.pumpWidget(const MaterialApp(home: _GatedHost()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Still on step one: a required field that is empty must block, or the
    // flow creates a tournament with no name.
    expect(find.text('Step 1 of 3'), findsOneWidget);

    await tester.tap(find.text('fill the field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('the back arrow walks back a step rather than leaving',
      (tester) async {
    await tester.pumpWidget(harness(steps: threeSteps(), onSubmit: () async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous step'));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('step one body'), findsOneWidget);
  });

  testWidgets('a submit in flight cannot be pressed twice', (tester) async {
    await tester.pumpWidget(harness(
      steps: threeSteps(),
      onSubmit: () async {},
      submitting: true,
    ));
    // pump, not pumpAndSettle: the in-flight state renders a
    // CircularProgressIndicator, which animates forever and would time
    // settling out.
    await tester.pump();

    // A double-tap on a slow network is how one tournament becomes two.
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a completed step can be revisited from the dots',
      (tester) async {
    await tester.pumpWidget(harness(steps: threeSteps(), onSubmit: () async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);

    // Tapping dot 1 goes back. Tapping forward past the current step must
    // not, because the skipped step may hold a required field.
    // Found by the dot's own digit — the counter above reads "Step 3 of 3",
    // so a bare "1" belongs only to the dot row.
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(
      find.text('Step 1 of 3'),
      findsOneWidget,
      reason: 'jumping forward past an unvisited step must not be allowed',
    );
  });
}

/// A flow whose first step is blocked until something in it is filled in.
class _GatedHost extends StatefulWidget {
  const _GatedHost();

  @override
  State<_GatedHost> createState() => _GatedHostState();
}

class _GatedHostState extends State<_GatedHost> {
  bool _filled = false;

  @override
  Widget build(BuildContext context) {
    return WizardScaffold(
      title: 'Create Tournament',
      onSubmit: () async {},
      steps: [
        WizardStep(
          title: 'Details',
          canAdvance: () => _filled,
          builder: (_) => TextButton(
            onPressed: () => setState(() => _filled = true),
            child: const Text('fill the field'),
          ),
        ),
        WizardStep(title: 'Format', builder: (_) => const Text('step two body')),
        WizardStep(title: 'Review', builder: (_) => const Text('step three')),
      ],
    );
  }
}
