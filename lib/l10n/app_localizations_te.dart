import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appTitle => 'PlaySphere';

  @override
  String get actionSave => 'సేవ్ చేయి';

  @override
  String get actionCancel => 'రద్దు';

  @override
  String get actionRetry => 'మళ్లీ ప్రయత్నించండి';

  @override
  String get actionDone => 'పూర్తయింది';

  @override
  String get actionCreate => 'సృష్టించు';

  @override
  String get actionJoin => 'చేరు';

  @override
  String get actionShare => 'పంచుకో';

  @override
  String get actionUndo => 'వెనక్కి తీసుకో';

  @override
  String get signInTitle => 'సైన్ ఇన్';

  @override
  String get signInWithGoogle => 'Google తో కొనసాగించండి';

  @override
  String get signOut => 'సైన్ అవుట్';

  @override
  String get profileSetupTitle => 'మీ ప్రొఫైల్ పూర్తి చేయండి';

  @override
  String get profileName => 'పూర్తి పేరు';

  @override
  String get profileDateOfBirth => 'పుట్టిన తేదీ';

  @override
  String get profileGender => 'లింగం';

  @override
  String get profilePhone => 'ఫోన్ నంబర్';

  @override
  String get profileDistrict => 'జిల్లా';

  @override
  String get profileMandal => 'మండలం';

  @override
  String get profileVillage => 'గ్రామం';

  @override
  String get orgsTitle => 'క్లబ్‌లు';

  @override
  String get orgCreate => 'క్లబ్ సృష్టించండి';

  @override
  String get orgJoinByCode => 'కోడ్‌తో చేరండి';

  @override
  String get orgMembers => 'సభ్యులు';

  @override
  String get orgFeed => 'ఫీడ్';

  @override
  String orgPendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count పెండింగ్ అభ్యర్థనలు',
      one: '1 పెండింగ్ అభ్యర్థన',
      zero: 'పెండింగ్ అభ్యర్థనలు లేవు',
    );
    return '$_temp0';
  }

  @override
  String get competitionsTitle => 'ఈవెంట్‌లు';

  @override
  String get competitionCreate => 'ఈవెంట్ సృష్టించండి';

  @override
  String competitionEntrants(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count పోటీదారులు',
      one: '1 పోటీదారు',
    );
    return '$_temp0';
  }

  @override
  String get competitionStandings => 'పట్టిక';

  @override
  String get competitionFixtures => 'మ్యాచ్‌లు';

  @override
  String get standingsPlayed => 'ఆ';

  @override
  String get standingsWon => 'గె';

  @override
  String get standingsDrawn => 'డ్రా';

  @override
  String get standingsLost => 'ఓ';

  @override
  String get standingsPoints => 'పా';

  @override
  String get standingsNetRunRate => 'NRR';

  @override
  String get scoringTitle => 'స్కోరింగ్';

  @override
  String get scoringFinishMatch => 'మ్యాచ్ ముగించు';

  @override
  String get scoringReopen => 'సరిచేయడానికి తిరిగి తెరవండి';

  @override
  String scoringOfflinePending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ఆఫ్‌లైన్ స్కోరింగ్ — $count ఈవెంట్‌లు పెండింగ్',
      one: 'ఆఫ్‌లైన్ స్కోరింగ్ — 1 ఈవెంట్ పెండింగ్',
      zero: 'అన్ని మార్పులు సేవ్ అయ్యాయి',
    );
    return '$_temp0';
  }

  @override
  String get scoringUndoConfirm => 'చివరి ఎంట్రీని వెనక్కి తీసుకోవాలా?';

  @override
  String get scoringNothingToUndo => 'వెనక్కి తీసుకోవడానికి ఇంకా ఏమీ లేదు.';

  @override
  String get matchSetupTitle => 'మ్యాచ్ సెటప్';

  @override
  String get matchSetupLineups => 'జట్ల జాబితా';

  @override
  String get matchSetupToss => 'టాస్';

  @override
  String get matchSetupTossWonBy => 'టాస్ గెలిచినవారు';

  @override
  String get matchSetupElectedTo => 'ఎంచుకున్నది';

  @override
  String get matchSetupBat => 'బ్యాటింగ్';

  @override
  String get matchSetupField => 'ఫీల్డింగ్';

  @override
  String get matchSetupBalanceTeams => 'జట్లను సమతుల్యం చేయి';

  @override
  String get spectatorWatching => 'ప్రత్యక్ష ప్రసారం';

  @override
  String get spectatorNoMatches => 'ప్రస్తుతం ఏ మ్యాచ్ ప్రత్యక్షంగా లేదు.';

  @override
  String get resultWalkover => 'వాక్‌ఓవర్';

  @override
  String get resultAbandoned => 'రద్దు చేయబడింది';

  @override
  String get resultDisputed => 'వివాదంలో ఉంది';

  @override
  String get resultDrawn => 'డ్రా';

  @override
  String resultWonBy(String winner) {
    return '$winner గెలిచారు';
  }

  @override
  String get errorGeneric => 'ఏదో తప్పు జరిగింది.';

  @override
  String get errorNetwork => 'కనెక్షన్ లేదు. మీ పని ఈ పరికరంలో సేవ్ అయింది, ఆన్‌లైన్‌కు వచ్చాక సింక్ అవుతుంది.';

  @override
  String get errorPermission => 'అది చేయడానికి మీకు అనుమతి లేదు.';

  @override
  String get errorConflict => 'మరొకరు ఆ బంతిని ముందుగా నమోదు చేశారు. స్కోరు రిఫ్రెష్ చేయబడింది.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTelugu => 'తెలుగు';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageSystemDefault => 'పరికర భాష';

  @override
  String get languageSettingTitle => 'భాష';
}
