import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the only route into the scoring pad: tapping a match.
///
/// ## The bug class this exists for
///
/// Every fixture list in the app is one of two widgets — `ScheduleBoard` (a
/// list of rows) or `GraphicalScheduleView` (a court-by-time grid) — and both
/// take the tap handler as a parameter, because where a match opens is the
/// screen's business and not the list's.
///
/// An optional parameter is easy to forget, and forgetting it does not fail
/// anything: the schedule renders, the rows look right, and every one of them
/// silently swallows taps. That is what happened to the season's Programme,
/// which drew the whole season's timetable with no `onTapFixture` at all —
/// so on the one screen an organizer stands in front of on match day, no
/// match could be opened, started or scored. Nothing was broken enough to
/// notice; the matches were simply unreachable.
///
/// So: a fixture list that is drawn must say where its matches open. If a
/// screen genuinely has read-only rows, it says so here with a reason, the
/// same way `reachability_test.dart` handles deliberate dead code.
void main() {
  /// Call sites allowed to draw matches nobody can tap, and why.
  const allowedUntappable = <String, String>{};

  test('every fixture list wires a way into the match', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final call in [
        (widget: 'ScheduleBoard', handler: 'onTapFixture'),
        (widget: 'GraphicalScheduleView', handler: 'onOpenMatch'),
      ]) {
        for (final args in _callArguments(source, call.widget)) {
          if (args.contains('${call.handler}:')) continue;
          final site = '${file.path} → ${call.widget}';
          if (allowedUntappable.containsKey(site)) continue;
          offenders.add(
            '$site is drawn without ${call.handler}: — its matches cannot be '
            'opened, so there is no route to the Match Center or the pad.',
          );
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Fixture lists with no tap:\n${offenders.join('\n')}',
    );
  });
}

/// The argument text of every construction of [widget] in [source].
///
/// Skips the constructor's own declaration — `const ScheduleBoard({` inside
/// the widget's own file is not a call site — and reads to the matching close
/// paren so a nested `Text(...)` argument does not end the scan early.
List<String> _callArguments(String source, String widget) {
  final out = <String>[];
  final pattern = RegExp('(?<![A-Za-z0-9_])$widget\\(');
  for (final match in pattern.allMatches(source)) {
    // `const Widget({` / `Widget({` — the declaration, which is followed by a
    // brace rather than by arguments.
    if (source.startsWith('{', match.end)) continue;

    var depth = 1;
    var i = match.end;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
      i++;
    }
    out.add(source.substring(match.end, i));
  }
  return out;
}
