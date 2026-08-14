import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'PlaySphere';

  @override
  String get actionSave => 'सहेजें';

  @override
  String get actionCancel => 'रद्द करें';

  @override
  String get actionRetry => 'फिर कोशिश करें';

  @override
  String get actionDone => 'हो गया';

  @override
  String get actionCreate => 'बनाएँ';

  @override
  String get actionJoin => 'शामिल हों';

  @override
  String get actionShare => 'साझा करें';

  @override
  String get actionUndo => 'वापस लें';

  @override
  String get signInTitle => 'साइन इन';

  @override
  String get signInTagline => 'प्रतियोगिताएं चलाएं, मैचों को लाइव स्कोर करें, और सभी को कहीं से भी साथ जुड़ने दें।';

  @override
  String get signInWithGoogle => 'Google से जारी रखें';

  @override
  String get signInInProgress => 'साइन इन हो रहा है…';

  @override
  String get signInWatchWithoutAccount => 'आप बिना साइन इन किए कोई भी सार्वजनिक लाइव मैच देख सकते हैं — बस कोई साझा किया गया लिंक खोलें।';

  @override
  String get signOut => 'साइन आउट';

  @override
  String get profileSetupTitle => 'अपनी प्रोफ़ाइल पूरी करें';

  @override
  String get profileName => 'पूरा नाम';

  @override
  String get profileDateOfBirth => 'जन्म तिथि';

  @override
  String get profileGender => 'लिंग';

  @override
  String get profilePhone => 'फ़ोन नंबर';

  @override
  String get profileDistrict => 'ज़िला';

  @override
  String get profileMandal => 'मंडल';

  @override
  String get profileVillage => 'गाँव';

  @override
  String get orgsTitle => 'क्लब';

  @override
  String get orgCreate => 'क्लब बनाएँ';

  @override
  String get orgJoinByCode => 'कोड से शामिल हों';

  @override
  String get orgMembers => 'सदस्य';

  @override
  String get orgFeed => 'फ़ीड';

  @override
  String orgPendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count लंबित अनुरोध',
      one: '1 लंबित अनुरोध',
      zero: 'कोई लंबित अनुरोध नहीं',
    );
    return '$_temp0';
  }

  @override
  String get competitionsTitle => 'आयोजन';

  @override
  String get competitionCreate => 'आयोजन बनाएँ';

  @override
  String competitionEntrants(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count प्रतिभागी',
      one: '1 प्रतिभागी',
    );
    return '$_temp0';
  }

  @override
  String get competitionStandings => 'तालिका';

  @override
  String get competitionFixtures => 'मैच';

  @override
  String get standingsPlayed => 'ख';

  @override
  String get standingsWon => 'जी';

  @override
  String get standingsDrawn => 'ड्रॉ';

  @override
  String get standingsLost => 'हा';

  @override
  String get standingsPoints => 'अंक';

  @override
  String get standingsNetRunRate => 'NRR';

  @override
  String get scoringTitle => 'स्कोरिंग';

  @override
  String get scoringFinishMatch => 'मैच समाप्त करें';

  @override
  String get scoringReopen => 'सुधार के लिए फिर से खोलें';

  @override
  String scoringOfflinePending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ऑफ़लाइन स्कोरिंग — $count इवेंट लंबित',
      one: 'ऑफ़लाइन स्कोरिंग — 1 इवेंट लंबित',
      zero: 'सभी बदलाव सहेजे गए',
    );
    return '$_temp0';
  }

  @override
  String get scoringUndoConfirm => 'अंतिम प्रविष्टि वापस लें?';

  @override
  String get scoringNothingToUndo => 'वापस लेने के लिए अभी कुछ नहीं है।';

  @override
  String get matchSetupTitle => 'मैच सेटअप';

  @override
  String get matchSetupLineups => 'टीम सूची';

  @override
  String get matchSetupToss => 'टॉस';

  @override
  String get matchSetupTossWonBy => 'टॉस जीता';

  @override
  String get matchSetupElectedTo => 'चुना';

  @override
  String get matchSetupBat => 'बल्लेबाज़ी';

  @override
  String get matchSetupField => 'गेंदबाज़ी';

  @override
  String get matchSetupBalanceTeams => 'टीमें संतुलित करें';

  @override
  String get spectatorWatching => 'लाइव देख रहे हैं';

  @override
  String get spectatorNoMatches => 'अभी कोई मैच लाइव नहीं है।';

  @override
  String get resultWalkover => 'वॉकओवर';

  @override
  String get resultAbandoned => 'रद्द';

  @override
  String get resultDisputed => 'विवादित';

  @override
  String get resultDrawn => 'ड्रॉ';

  @override
  String resultWonBy(String winner) {
    return '$winner जीता';
  }

  @override
  String get errorGeneric => 'कुछ गड़बड़ हो गई।';

  @override
  String get errorNetwork => 'कनेक्शन नहीं है। आपका काम इस डिवाइस पर सहेजा गया है और ऑनलाइन होते ही सिंक हो जाएगा।';

  @override
  String get errorPermission => 'आपके पास ऐसा करने की अनुमति नहीं है।';

  @override
  String get errorConflict => 'किसी और ने वह गेंद पहले दर्ज कर दी। स्कोर ताज़ा कर दिया गया है।';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTelugu => 'తెలుగు';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageSystemDefault => 'डिवाइस की भाषा';

  @override
  String get languageSettingTitle => 'भाषा';
}
