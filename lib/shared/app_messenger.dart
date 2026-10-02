import 'dart:async';

import 'package:flutter/material.dart';

import '../data/competition_repository.dart';
import '../data/tournament_repository.dart';
import 'app_scaffold.dart' show errorMessage;

/// The app's one root [ScaffoldMessenger], reachable without a
/// [BuildContext].
///
/// ## Why a key and not `ScaffoldMessenger.of(context)`
///
/// Two kinds of message arrive after the screen that caused them is gone:
///
/// - A write queued offline and rejected by the server minutes later. Season
///   creation, venue creation and every "fire and forget" write in the
///   competition and tournament repositories report on `writeFailures`, and
///   until this existed nothing subscribed — a refused season disappeared
///   from the organizer's phone with no word said.
/// - Work that finishes after navigation, such as a season's artwork, which
///   uploads once the season page is already open.
///
/// Both need somewhere to speak that outlives the screen.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows [message] (a sentence, or any error [errorMessage] understands) on
/// whatever screen is current. A no-op before the app has built.
void showAppMessage(Object message) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(errorMessage(message)),
        duration: const Duration(seconds: 6),
      ),
    );
}

/// Subscribes to every repository failure stream that has no screen of its
/// own to report to. Returned so the app shell can cancel it.
List<StreamSubscription<Object>> listenForBackgroundWriteFailures() => [
      TournamentRepository.writeFailures.listen(showAppMessage),
      CompetitionRepository.writeFailures.listen(showAppMessage),
    ];
