import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../models/enums.dart';
import '../models/fixture.dart';

/// Turns stored result tokens into text in the reader's language.
///
/// The data layer persists `FixtureStatus.wire` values rather than English
/// phrases, precisely so this decision can be made per reader. A scorecard
/// written by an English-speaking scorer in Hyderabad reads as "రద్దు
/// చేయబడింది" to a Telugu spectator, because the document holds `abandoned`
/// and not the word "Abandoned".
extension FixtureStatusLabel on FixtureStatus {
  /// Named `localizedLabel` rather than `label` because the enum already
  /// carries a hard-coded English `label` field. Shadowing it would make the
  /// translated and untranslated versions indistinguishable at the call site,
  /// which is exactly how an English string ends up on a Telugu screen.
  String localizedLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (this) {
      FixtureStatus.walkover => l10n.resultWalkover,
      FixtureStatus.abandoned => l10n.resultAbandoned,
      FixtureStatus.disputed => l10n.resultDisputed,
      _ => '',
    };
  }
}

/// Renders a stored summary field.
///
/// Most summaries are scores ("21-18, 19-21") and are language-neutral, so
/// they pass through untouched. The administrative outcomes are tokens and
/// get translated. Anything unrecognised is shown as-is rather than blanked,
/// so a summary written by a future build still displays.
String localizedSummary(BuildContext context, String summary) {
  // A score, or nothing, needs no translation — and no localizations lookup,
  // which a list row must not depend on just to print "21-18".
  if (!Fixture.outcomeTokens.contains(summary)) return summary;
  final status = FixtureStatus.fromWire(summary);
  final translated =
      status.wire == summary ? status.localizedLabel(context) : '';
  if (translated.isNotEmpty) return translated;
  // The two outcome tokens that are result types rather than statuses. No
  // translation exists for them yet, but "Conceded" is still better than the
  // raw wire token "conceded" on a scorecard.
  if (summary == MatchResultType.conceded.wire ||
      summary == MatchResultType.noShow.wire) {
    return MatchResultType.fromWire(summary).label;
  }
  return summary;
}

/// A fixture's score as a list row shows it: translated where the summary is
/// an outcome token, and marked — "21-15, 8-3 (R)" — where a ruling ended a
/// match that had a score. See [Fixture.scoreLine].
String localizedScoreLine(BuildContext context, Fixture fixture) =>
    fixture.summaryIsScore
        ? fixture.scoreLine
        : localizedSummary(context, fixture.summary);
