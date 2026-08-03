import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

enum DisputeStatus {
  /// Raised, awaiting a referee.
  open('open', 'Open'),

  /// Upheld — the result was changed.
  upheld('upheld', 'Upheld'),

  /// Rejected — the result stands.
  rejected('rejected', 'Rejected'),

  /// Withdrawn by whoever raised it.
  withdrawn('withdrawn', 'Withdrawn');

  const DisputeStatus(this.wire, this.label);

  final String wire;
  final String label;

  bool get isResolved => this != DisputeStatus.open;

  static DisputeStatus fromWire(String? w) => DisputeStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => DisputeStatus.open,
      );
}

enum DisputeReason {
  wrongScore('wrong_score', 'The score is wrong'),
  ineligiblePlayer('ineligible_player', 'A player was not eligible'),
  conduct('conduct', 'Conduct'),
  officiating('officiating', 'An officiating decision'),
  other('other', 'Something else');

  const DisputeReason(this.wire, this.label);

  final String wire;
  final String label;

  static DisputeReason fromWire(String? w) => DisputeReason.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => DisputeReason.other,
      );
}

/// A formal protest against a result, at
/// `orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}/disputes/{id}`.
///
/// ## Why a result needs a way to be challenged
///
/// The event log is append-only and the scorer is locked, which makes the
/// record *tamper-proof*. It does not make it *right*: a scorer can press the
/// wrong button, a player can be a year too old for the category, and somebody
/// has to be able to say so afterwards. Without a protest path that argument
/// happens on WhatsApp and the app becomes the thing everybody is arguing
/// about rather than the thing that settles it.
///
/// ## Why there is a window
///
/// Every federation closes protests a fixed time after the result, and for the
/// same reason: a bracket cannot advance while any earlier match might still
/// be overturned, and a tournament where last week's quarter-final can be
/// reopened has no results at all. The window is short and it is stated up
/// front.
class Dispute {
  const Dispute({
    required this.id,
    required this.orgId,
    required this.compId,
    required this.fixtureId,
    required this.raisedByUid,
    required this.raisedByName,
    required this.reason,
    required this.status,
    this.detail,
    this.entrantId,
    this.resolvedByUid,
    this.resolutionNote,
    this.raisedAt,
    this.resolvedAt,
  });

  final String id;
  final String orgId;
  final String compId;
  final String fixtureId;

  final String raisedByUid;
  final String raisedByName;

  /// Which side is protesting. Recorded because a referee needs to know
  /// whether the complaint comes from a competitor or a spectator.
  final String? entrantId;

  final DisputeReason reason;
  final String? detail;
  final DisputeStatus status;

  /// The referee who decided it. Never the same person who raised it — see
  /// `firestore.rules`.
  final String? resolvedByUid;

  /// Why it was upheld or rejected, in the referee's own words. The part that
  /// makes a decision defensible rather than merely final.
  final String? resolutionNote;

  final DateTime? raisedAt;
  final DateTime? resolvedAt;

  factory Dispute.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Dispute(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      compId: Fs.str(d['compId']),
      fixtureId: Fs.str(d['fixtureId']),
      raisedByUid: Fs.str(d['raisedByUid']),
      raisedByName: Fs.str(d['raisedByName'], 'Someone'),
      entrantId: Fs.strOrNull(d['entrantId']),
      reason: DisputeReason.fromWire(Fs.strOrNull(d['reason'])),
      detail: Fs.strOrNull(d['detail']),
      status: DisputeStatus.fromWire(Fs.strOrNull(d['status'])),
      resolvedByUid: Fs.strOrNull(d['resolvedByUid']),
      resolutionNote: Fs.strOrNull(d['resolutionNote']),
      raisedAt: Fs.dateOrNull(d['raisedAt']),
      resolvedAt: Fs.dateOrNull(d['resolvedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'compId': compId,
        'fixtureId': fixtureId,
        'raisedByUid': raisedByUid,
        'raisedByName': raisedByName,
        'entrantId': entrantId,
        'reason': reason.wire,
        'detail': detail,
        'status': DisputeStatus.open.wire,
        'resolvedByUid': null,
        'resolutionNote': null,
        'raisedAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      };
}

/// How long after a result a protest may still be raised.
///
/// Deliberately a constant rather than a per-competition setting for now: a
/// window that varies by event is a window nobody can remember, and the
/// question "can I still protest?" has to be answerable at the desk without
/// looking anything up. One hour is long enough to walk off court, look at the
/// scorecard and object; short enough that the next round is not held up.
const protestWindow = Duration(hours: 1);

/// Whether a result is still open to protest.
bool withinProtestWindow(DateTime? completedAt, {DateTime? now}) {
  if (completedAt == null) return false;
  return (now ?? DateTime.now()).difference(completedAt) <= protestWindow;
}

/// Whether a scorecard is final — past the window with nothing outstanding.
///
/// This is what a bracket should check before advancing anybody. A match still
/// inside its window, or with an open dispute, is not yet a result to build on.
bool scorecardIsLocked({
  required DateTime? completedAt,
  required bool hasOpenDispute,
  DateTime? now,
}) {
  if (completedAt == null) return false;
  if (hasOpenDispute) return false;
  return !withinProtestWindow(completedAt, now: now);
}
