import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../models/enums.dart';

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
  final status = FixtureStatus.fromWire(summary);
  final translated = status.localizedLabel(context);
  return translated.isEmpty ? summary : translated;
}
