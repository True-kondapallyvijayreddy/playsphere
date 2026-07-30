import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('te')
  ];

  /// The product name. Not translated — it is a proper noun.
  ///
  /// In en, this message translates to:
  /// **'PlaySphere'**
  String get appTitle;

  /// Generic save button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// Generic cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Retry after a failure
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// Finish and close
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// Create a new thing
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get actionCreate;

  /// Join a club
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get actionJoin;

  /// Share a link or scorecard
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// Withdraw the last scoring event
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// Sign-in screen heading
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// Google sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get signInWithGoogle;

  /// Sign out menu item
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// Heading on the profile completion screen
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get profileSetupTitle;

  /// Name field label
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get profileName;

  /// DOB field label. Required because every age category rule depends on it.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get profileDateOfBirth;

  /// Gender field label
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get profileGender;

  /// Phone field label
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get profilePhone;

  /// District field label
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get profileDistrict;

  /// Mandal field label — the administrative tier between village and district in Telangana
  ///
  /// In en, this message translates to:
  /// **'Mandal'**
  String get profileMandal;

  /// Village field label
  ///
  /// In en, this message translates to:
  /// **'Village'**
  String get profileVillage;

  /// Clubs list heading
  ///
  /// In en, this message translates to:
  /// **'Clubs'**
  String get orgsTitle;

  /// Create club button
  ///
  /// In en, this message translates to:
  /// **'Create a club'**
  String get orgCreate;

  /// Join club by invite code
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get orgJoinByCode;

  /// Members tab
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get orgMembers;

  /// Club announcements feed tab
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get orgFeed;

  /// Count of membership requests awaiting approval
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pending requests} =1{1 pending request} other{{count} pending requests}}'**
  String orgPendingRequests(int count);

  /// Competitions list heading
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get competitionsTitle;

  /// Create competition button
  ///
  /// In en, this message translates to:
  /// **'Create an event'**
  String get competitionCreate;

  /// Number of teams or players entered
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entrant} other{{count} entrants}}'**
  String competitionEntrants(int count);

  /// League table tab
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get competitionStandings;

  /// Fixtures tab
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get competitionFixtures;

  /// League table column: matches played. Keep short — it is a column heading.
  ///
  /// In en, this message translates to:
  /// **'P'**
  String get standingsPlayed;

  /// League table column: won
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get standingsWon;

  /// League table column: drawn
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get standingsDrawn;

  /// League table column: lost
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get standingsLost;

  /// League table column: points
  ///
  /// In en, this message translates to:
  /// **'Pts'**
  String get standingsPoints;

  /// League table column: net run rate (cricket only)
  ///
  /// In en, this message translates to:
  /// **'NRR'**
  String get standingsNetRunRate;

  /// Scoring pad heading
  ///
  /// In en, this message translates to:
  /// **'Scoring'**
  String get scoringTitle;

  /// Finalise the result
  ///
  /// In en, this message translates to:
  /// **'End match'**
  String get scoringFinishMatch;

  /// Reopen a finished match
  ///
  /// In en, this message translates to:
  /// **'Reopen to correct'**
  String get scoringReopen;

  /// Badge telling the scorer how many events have not reached the server. Shown on grounds with no signal, so it must be reassuring rather than alarming.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{All changes saved} =1{Scoring offline — 1 event pending} other{Scoring offline — {count} events pending}}'**
  String scoringOfflinePending(int count);

  /// Confirmation before withdrawing a scoring event
  ///
  /// In en, this message translates to:
  /// **'Undo the last entry?'**
  String get scoringUndoConfirm;

  /// Shown when undo is pressed on an empty match
  ///
  /// In en, this message translates to:
  /// **'There is nothing to undo yet.'**
  String get scoringNothingToUndo;

  /// Lineup and toss screen heading
  ///
  /// In en, this message translates to:
  /// **'Match setup'**
  String get matchSetupTitle;

  /// Lineup section heading
  ///
  /// In en, this message translates to:
  /// **'Line-ups'**
  String get matchSetupLineups;

  /// Toss section heading
  ///
  /// In en, this message translates to:
  /// **'Toss'**
  String get matchSetupToss;

  /// Who won the toss
  ///
  /// In en, this message translates to:
  /// **'Toss won by'**
  String get matchSetupTossWonBy;

  /// What the toss winner chose
  ///
  /// In en, this message translates to:
  /// **'Elected to'**
  String get matchSetupElectedTo;

  /// Toss decision: bat first
  ///
  /// In en, this message translates to:
  /// **'Bat'**
  String get matchSetupBat;

  /// Toss decision: field first
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get matchSetupField;

  /// Run the AI team shuffle
  ///
  /// In en, this message translates to:
  /// **'Balance teams'**
  String get matchSetupBalanceTeams;

  /// Spectator screen status
  ///
  /// In en, this message translates to:
  /// **'Watching live'**
  String get spectatorWatching;

  /// Empty state on the live matches screen
  ///
  /// In en, this message translates to:
  /// **'No matches are live right now.'**
  String get spectatorNoMatches;

  /// Match awarded without play
  ///
  /// In en, this message translates to:
  /// **'Walkover'**
  String get resultWalkover;

  /// Match called off
  ///
  /// In en, this message translates to:
  /// **'Abandoned'**
  String get resultAbandoned;

  /// Result contested by a captain
  ///
  /// In en, this message translates to:
  /// **'Under dispute'**
  String get resultDisputed;

  /// Match ended level
  ///
  /// In en, this message translates to:
  /// **'Drawn'**
  String get resultDrawn;

  /// Result line naming the winning side
  ///
  /// In en, this message translates to:
  /// **'{winner} won'**
  String resultWonBy(String winner);

  /// Fallback error message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get errorGeneric;

  /// Offline error. Must reassure — the scorer's data is not lost.
  ///
  /// In en, this message translates to:
  /// **'No connection. Your work is saved on this device and will sync when you are back online.'**
  String get errorNetwork;

  /// Authorisation failure
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do that.'**
  String get errorPermission;

  /// Lost a race for a sequence number
  ///
  /// In en, this message translates to:
  /// **'Someone else scored that ball first. The score has been refreshed.'**
  String get errorConflict;

  /// Language name, shown in its own language
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Telugu language name, in Telugu
  ///
  /// In en, this message translates to:
  /// **'తెలుగు'**
  String get languageTelugu;

  /// Hindi language name, in Hindi
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get languageHindi;

  /// Follow the device language rather than pinning one
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystemDefault;

  /// Language picker heading
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettingTitle;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'hi', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'hi': return AppLocalizationsHi();
    case 'te': return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
