import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against code that is written, tested, and wired to nothing.
///
/// ## The bug class this exists for
///
/// A review of `lib/` found 3,549 lines across 22 files that no import chain
/// from `main.dart` could reach — and they were not stray helpers. They were
/// whole subsystems: a payments layer with a state machine and a refund
/// policy, a guardian-consent pipeline, a government analytics cube, and
/// `SwissPairing.nextSwissRound`, which was the only thing that could produce
/// round two of a Swiss tournament. Most of them had passing tests.
///
/// That is the expensive kind of dead code. It costs maintenance, it reads as
/// shipped when someone greps for it, and its green tests actively mislead —
/// `swiss_pairing.dart` was covered by four of them while an organizer who
/// picked Swiss got one round of fixtures and a dead end. Nothing failed,
/// because nothing was asking whether the code ran at all.
///
/// ## Why an allowlist rather than "unreachable is forbidden"
///
/// Some files are legitimately unreachable and should stay that way. A
/// reference implementation that pins a formula the server computes is not
/// dead code; it is a spec with tests. So the rule is not "everything must be
/// reachable" — it is **every unreachable file must have a stated reason**.
/// Adding a file to [_allowedUnreachable] is cheap; doing it without a reason
/// is what this test makes visible in review.
///
/// A file that becomes reachable is also a failure here, so the allowlist
/// cannot rot into a list of things that were wired up years ago.
void main() {
  /// Files that are allowed to be unreachable from `main.dart`, and why.
  ///
  /// Grouped by reason, because the reasons call for different actions: a
  /// spec stays forever, a deferred subsystem is a decision to revisit, and
  /// an unrouted screen is a bug someone has not noticed yet.
  const allowedUnreachable = <String, String>{
    // ---- Reference implementations. Unreachable by design. ----
    //
    // The talent boards are built server-side, because no client may read
    // across a district's profiles. That puts the scoring formula in two
    // places, and `test/talent_trend_test.dart` is the cross-implementation
    // contract that fixes the exact numbers both must produce. Deleting the
    // Dart side would delete the only executable check that
    // `functions/talent.js` still computes what it is supposed to.
    'lib/domain/scout/talent_trend.dart':
        'Reference implementation; contract-tested against functions/talent.js',

    // ---- Deferred subsystems. Built, not wired, decision pending. ----
    //
    // A complete payments layer — state machine, webhook processor, ledger
    // reconciliation, refund policy, GST invoicing, split and route payouts.
    // The money that actually moves is handled server-side by
    // `functions/razorpay.js`, which covers the happy path only. Whether this
    // becomes the server's refund/invoice path or gets deleted is an open
    // product decision, not an oversight.
    'lib/core/models/payment.dart': 'Payments layer: deferred, not wired',
    'lib/domain/payments/payment_webhook_processor.dart':
        'Payments layer: deferred, not wired',
    'lib/domain/payments/payment_state_machine.dart':
        'Payments layer: deferred, not wired',
    'lib/domain/payments/reconciliation.dart':
        'Payments layer: deferred, not wired',
    'lib/domain/payments/refund_policy.dart':
        'Payments layer: deferred, not wired',
    'lib/domain/payments/gst_invoice.dart':
        'Payments layer: deferred, not wired',
    'lib/domain/payments/split_pay.dart': 'Payments layer: deferred, not wired',
    'lib/domain/payments/route_split.dart':
        'Payments layer: deferred, not wired',

    // The DPDP-facing consent pipeline: age gating, consent scope, expiry.
    // `firestore.rules` independently requires an unrevoked
    // `guardianConsents/{scoutUid}` before a scout sees a minor, and that
    // rule IS enforced and emulator-tested — so this being unwired is not an
    // open door. What does not run is the policy layer above it.
    'lib/core/models/guardian_consent.dart':
        'Consent pipeline: deferred; the rules-level check is what enforces today',
    'lib/core/models/scout_access.dart':
        'Consent pipeline: deferred; the rules-level check is what enforces today',
    'lib/domain/consent/consent_policy.dart':
        'Consent pipeline: deferred; the rules-level check is what enforces today',
    'lib/domain/consent/consent_decision.dart':
        'Consent pipeline: deferred; the rules-level check is what enforces today',
    'lib/domain/scout/talent_search.dart':
        'Consent pipeline: deferred; ScoutRepository uses a simpler substitute',

    // The full Telangana Sports Policy cube — period × geo × sport × age ×
    // gender × disability, with k-anonymity suppression. `functions/gov.js`
    // deliberately computes a coarser subset instead, because registration
    // does not yet collect the fields the full cube needs. This is the schema
    // to grow into, kept on purpose.
    'lib/domain/gov/gov_aggregator.dart':
        'Gov analytics: full cube deferred; functions/gov.js ships the subset',
    'lib/domain/gov/gov_aggregate.dart':
        'Gov analytics: full cube deferred; functions/gov.js ships the subset',
    'lib/domain/gov/gov_export.dart':
        'Gov analytics: full cube deferred; functions/gov.js ships the subset',
    'lib/domain/gov/participation_entry.dart':
        'Gov analytics: full cube deferred; functions/gov.js ships the subset',

    // ---- Known bug, not yet fixed. ----
    //
    // A complete club-announcements UI — compose, pin, attach a poll — that
    // no route or tab mounts, which makes it the only way to post an
    // announcement and also unreachable. The model, the repository and the
    // security rules for announcements are all live; only this is orphaned.
    // Deleting it would remove the feature outright, so it stays listed until
    // it is mounted.
    'lib/features/orgs/tabs/club_feed_tab.dart':
        'BUG: the only announcement-composer UI, mounted by no route',
  };

  /// Every `.dart` file under `lib/`.
  Set<String> allLibFiles() {
    final dir = Directory('lib');
    return {
      for (final f in dir.listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) _norm(f.path),
    };
  }

  /// Resolves the import and export targets of [file] that point inside
  /// `lib/`, handling both `package:playsphere/…` and relative forms.
  ///
  /// `export` counts as an edge as much as `import` does: a barrel file makes
  /// everything it re-exports reachable, and treating it as a leaf would
  /// report live code as dead.
  Set<String> edgesOf(String file, Set<String> known) {
    final src = File(file).readAsStringSync();
    final pattern = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final out = <String>{};
    for (final m in pattern.allMatches(src)) {
      final raw = m.group(1)!;
      String target;
      if (raw.startsWith('package:playsphere/')) {
        target = _norm('lib/${raw.substring('package:playsphere/'.length)}');
      } else if (raw.startsWith('dart:') || raw.startsWith('package:')) {
        continue;
      } else {
        target = _norm(
          File('${File(file).parent.path}/$raw').uri.normalizePath().toFilePath(),
        );
      }
      if (known.contains(target)) out.add(target);
    }
    return out;
  }

  test('every file under lib/ is reachable from main.dart, or listed with a '
      'reason', () {
    final all = allLibFiles();
    expect(
      all,
      contains('lib/main.dart'),
      reason: 'the walk has to start somewhere',
    );

    final seen = <String>{};
    final stack = <String>['lib/main.dart'];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!seen.add(current)) continue;
      stack.addAll(edgesOf(current, all));
    }

    final unreachable = all.difference(seen);
    final allowed = allowedUnreachable.keys.toSet();

    // New dead code. This is the failure the whole file exists to produce.
    final undocumented = (unreachable.difference(allowed).toList())..sort();
    expect(
      undocumented,
      isEmpty,
      reason: 'These files cannot be reached from main.dart by any import '
          'chain, so nothing in the running app uses them. Either wire them '
          'up, delete them, or add them to `allowedUnreachable` with the '
          'reason they are allowed to stay.',
    );

    // The allowlist has to shrink as things get fixed, or it stops meaning
    // anything. A file that is now reachable must not keep its exemption.
    final staleExemptions = (allowed.difference(unreachable).toList())..sort();
    expect(
      staleExemptions,
      isEmpty,
      reason: 'These are listed in `allowedUnreachable` but ARE reachable '
          'now. Remove them from the list — a stale allowlist hides the next '
          'real one.',
    );
  });

  test('allowlisted files still exist', () {
    final missing = [
      for (final path in allowedUnreachable.keys)
        if (!File(path).existsSync()) path,
    ]..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Deleted, but still exempted. Drop them from the list.',
    );
  });
}

/// Repo-relative, forward-slashed, so the same file has one spelling however
/// it was reached — an absolute path from a relative import and a
/// `package:` URI must not look like two different files.
String _norm(String path) {
  var p = path.replaceAll(r'\', '/');
  final marker = p.lastIndexOf('/lib/');
  if (marker != -1) p = p.substring(marker + 1);
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  return p;
}
