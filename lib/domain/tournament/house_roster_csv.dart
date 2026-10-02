/// Turns a competition's house roster into a downloadable CSV — TC-ADM-033.
///
/// Kept pure (no Firestore, no widgets) for the same reason [house_roster]
/// is: the escaping rules are worth testing on their own, without a
/// competition or a screen to stand one up first.
library;

import '../../core/models/competition.dart';
import '../../core/models/enums.dart';

class HouseRosterCsv {
  const HouseRosterCsv._();

  static const List<String> _header = [
    'Member UID',
    'Name',
    'House Name',
    'Assigned Sport',
  ];

  /// One row per still-active registration. Withdrawn and rejected entrants
  /// are left out — they are not standing in any house any more.
  static String build({
    required List<Registration> registrations,
    required String sportName,
  }) {
    final rows = registrations
        .where((r) =>
            r.status != RegistrationStatus.withdrawn &&
            r.status != RegistrationStatus.rejected)
        .map((r) => [
              r.uid,
              r.displayName,
              r.houseName ?? 'Unassigned',
              sportName,
            ]);

    final buffer = StringBuffer()
      // A BOM, so Excel on Windows — the overwhelming case for a school or
      // college office opening this file — reads names with diacritics
      // correctly instead of guessing the wrong codepage.
      ..write('﻿')
      ..write(_header.map(_cell).join(','))
      ..write('\r\n');
    for (final row in rows) {
      buffer
        ..write(row.map(_cell).join(','))
        ..write('\r\n');
    }
    return buffer.toString();
  }

  /// Escapes one cell, and neutralises formula injection: a cell starting
  /// with `=`, `+`, `-` or `@` opens as a live formula the instant a
  /// spreadsheet app loads this file, which is how somebody's display name
  /// becomes a way to run a command on whoever opens the export. Prefixing
  /// with a single quote is the standard mitigation — spreadsheet CSV
  /// importers show the cell literally rather than evaluating it.
  static String _cell(String value) {
    var v = value;
    if (v.isNotEmpty && RegExp(r'^[=+\-@]').hasMatch(v)) {
      v = "'$v";
    }
    if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      v = '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
