import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PlaySphere';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionDone => 'Done';

  @override
  String get actionCreate => 'Create';

  @override
  String get actionJoin => 'Join';

  @override
  String get actionShare => 'Share';

  @override
  String get actionUndo => 'Undo';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInTagline => 'Run competitions, score matches live, and let everyone follow along from anywhere.';

  @override
  String get signInWithGoogle => 'Continue with Google';

  @override
  String get signInInProgress => 'Signing in…';

  @override
  String get signInWatchWithoutAccount => 'You can watch any public live match without signing in — just open the link someone shares with you.';

  @override
  String get signOut => 'Sign out';

  @override
  String get profileSetupTitle => 'Complete your profile';

  @override
  String get profileName => 'Full name';

  @override
  String get profileDateOfBirth => 'Date of birth';

  @override
  String get profileGender => 'Gender';

  @override
  String get profilePhone => 'Phone number';

  @override
  String get profileDistrict => 'District';

  @override
  String get profileMandal => 'Mandal';

  @override
  String get profileVillage => 'Village';

  @override
  String get orgsTitle => 'Clubs';

  @override
  String get orgCreate => 'Create a club';

  @override
  String get orgJoinByCode => 'Join with a code';

  @override
  String get orgMembers => 'Members';

  @override
  String get orgFeed => 'Feed';

  @override
  String orgPendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending requests',
      one: '1 pending request',
      zero: 'No pending requests',
    );
    return '$_temp0';
  }

  @override
  String get competitionsTitle => 'Events';

  @override
  String get competitionCreate => 'Create an event';

  @override
  String competitionEntrants(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrants',
      one: '1 entrant',
    );
    return '$_temp0';
  }

  @override
  String get competitionStandings => 'Table';

  @override
  String get competitionFixtures => 'Matches';

  @override
  String get standingsPlayed => 'P';

  @override
  String get standingsWon => 'W';

  @override
  String get standingsDrawn => 'D';

  @override
  String get standingsLost => 'L';

  @override
  String get standingsPoints => 'Pts';

  @override
  String get standingsNetRunRate => 'NRR';

  @override
  String get scoringTitle => 'Scoring';

  @override
  String get scoringFinishMatch => 'End match';

  @override
  String get scoringReopen => 'Reopen to correct';

  @override
  String scoringOfflinePending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Scoring offline — $count events pending',
      one: 'Scoring offline — 1 event pending',
      zero: 'All changes saved',
    );
    return '$_temp0';
  }

  @override
  String get scoringUndoConfirm => 'Undo the last entry?';

  @override
  String get scoringNothingToUndo => 'There is nothing to undo yet.';

  @override
  String get matchSetupTitle => 'Match setup';

  @override
  String get matchSetupLineups => 'Line-ups';

  @override
  String get matchSetupToss => 'Toss';

  @override
  String get matchSetupTossWonBy => 'Toss won by';

  @override
  String get matchSetupElectedTo => 'Elected to';

  @override
  String get matchSetupBat => 'Bat';

  @override
  String get matchSetupField => 'Field';

  @override
  String get matchSetupBalanceTeams => 'Balance teams';

  @override
  String get spectatorWatching => 'Watching live';

  @override
  String get spectatorNoMatches => 'No matches are live right now.';

  @override
  String get resultWalkover => 'Walkover';

  @override
  String get resultAbandoned => 'Abandoned';

  @override
  String get resultDisputed => 'Under dispute';

  @override
  String get resultDrawn => 'Drawn';

  @override
  String resultWonBy(String winner) {
    return '$winner won';
  }

  @override
  String get errorGeneric => 'Something went wrong.';

  @override
  String get errorNetwork => 'No connection. Your work is saved on this device and will sync when you are back online.';

  @override
  String get errorPermission => 'You do not have permission to do that.';

  @override
  String get errorConflict => 'Someone else scored that ball first. The score has been refreshed.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTelugu => 'తెలుగు';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageSystemDefault => 'System default';

  @override
  String get languageSettingTitle => 'Language';
}
