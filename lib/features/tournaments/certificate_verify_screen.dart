import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../domain/ranking/ranking_points.dart';
import '../../domain/tournament/certificate.dart';
import 'widgets/certificate_card.dart';

/// The page a certificate's QR code and short code lead to.
///
/// ## Why this re-derives rather than looking a record up
///
/// SRS §27.4 asks for a public verification URL, and without one a certificate
/// is a PNG — something anybody can reproduce with a different name on it,
/// which leaves the "verifiable proof for a career resume" claim the whole
/// feature rests on worth nothing. Worse than nothing, because it looks like
/// evidence.
///
/// The obvious implementation is a `certificates/{id}` collection written when
/// an event finishes. This does not do that, because `Certificate`'s own doc
/// comment states the property worth keeping: every field on it is already a
/// fact in the database. A written record is a second copy of those facts —
/// one that can disagree with the fixtures it came from, and that somebody has
/// to keep in step when a result is corrected or a protest is upheld.
///
/// So this recomputes the award from the same documents the issuing screen
/// read: `RankingPoints.award` over the event's own fixtures. Four outcomes,
/// each an honest answer rather than a generic failure:
///
///   * the award exists, and this renders the identical certificate;
///   * the event exists, finished, and shows no placing for this entrant —
///     the certificate is not genuine, whatever it says;
///   * the event has not finished, so no genuine certificate exists yet;
///   * nothing is readable, because the club is unlisted. Not the
///     certificate's fault, and saying "invalid" here would accuse somebody
///     holding a real one of forgery.
///
/// A corrected result therefore changes what verifies. That is right: the
/// certificate was always a statement about the result, never about itself.
///
/// Signed out on purpose — see `_isPublicRoute`. A certificate is shown to a
/// selector, an employer or an admissions office, and a verification page that
/// demands an account is a page nobody checks.
class CertificateVerifyScreen extends ConsumerWidget {
  const CertificateVerifyScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
    required this.compId,
    required this.entrantId,
  });

  final String orgId;
  final String tournamentId;
  final String compId;
  final String entrantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ref0 = CompRef(orgId, compId);
    final event = ref.watch(competitionProvider(ref0));
    final fixtures = ref.watch(fixturesProvider(ref0));

    return Scaffold(
      appBar: AppBar(title: const Text('Verify a certificate')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _body(context, ref, event, fixtures),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Competition?> event,
    AsyncValue<List<Fixture>> fixtures,
  ) {
    final theme = Theme.of(context);

    if (event.isLoading || fixtures.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // A permission error is the unlisted-club case. Distinguished from a
    // forgery on purpose: they are opposite conclusions and a page that
    // conflated them would call a genuine certificate fake.
    if (event.hasError || fixtures.hasError) {
      return _Verdict(
        icon: Icons.visibility_off_outlined,
        tone: theme.colorScheme.outline,
        headline: 'This event is not public',
        detail: 'The club that ran it has not published its results, so this '
            'certificate cannot be checked here. Ask the club to confirm it '
            'directly.',
        code: _code,
      );
    }

    final comp = event.valueOrNull;
    if (comp == null) {
      return _Verdict(
        icon: Icons.help_outline,
        tone: theme.colorScheme.error,
        headline: 'No such event',
        detail: 'This code does not point at an event on PlaySphere. Check it '
            'was typed correctly.',
        code: _code,
      );
    }

    final own = fixtures.valueOrNull ?? const <Fixture>[];
    // The issuing screen refuses to certify an unfinished event, so a
    // certificate claiming otherwise did not come from it.
    if (own.isEmpty || own.any((f) => !f.status.isResulted)) {
      return _Verdict(
        icon: Icons.hourglass_empty,
        tone: theme.colorScheme.error,
        headline: 'This event has not finished',
        detail: 'Placings are certified only once every match is resulted, so '
            'no genuine certificate exists for it yet.',
        code: _code,
      );
    }

    // The tournament carries the grade that weights an award, which is why it
    // is part of the certificate's identity rather than looked up: a verifier
    // that guessed at it would be re-deriving the award from a different
    // document than the one that produced it.
    final tournament = ref
        .watch(tournamentProvider((orgId: orgId, tournamentId: tournamentId)))
        .valueOrNull;
    if (tournament == null) {
      return _Verdict(
        icon: Icons.help_outline,
        tone: theme.colorScheme.error,
        headline: 'No such tournament',
        detail: 'This code names a tournament PlaySphere does not hold.',
        code: _code,
      );
    }

    final awards = RankingPoints.award(
      tournament: tournament,
      event: comp,
      fixtures: own,
    );
    final award =
        awards.where((a) => a.entrantId == entrantId).firstOrNull;

    if (award == null) {
      return _Verdict(
        icon: Icons.cancel_outlined,
        tone: theme.colorScheme.error,
        headline: 'No award for this entrant',
        detail: 'The event is on PlaySphere and has finished, and its results '
            'show no placing for whoever this certificate names. It did not '
            'come from us.',
        code: _code,
      );
    }

    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final certificate = Certificate(
      recipientName: award.displayName,
      title: CertificateTitle.fromRound(award.round),
      eventName: comp.name,
      tournamentName: tournament.name,
      organizerName: org?.name ?? 'PlaySphere',
      sportName: comp.sportName,
      categoryLabel: comp.category.label,
      date: comp.endDate ?? comp.startDate ?? DateTime.now(),
      orgId: orgId,
      tournamentId: tournamentId,
      compId: compId,
      entrantId: entrantId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Verdict(
          icon: Icons.verified_outlined,
          tone: const Color(0xFF2F6B33),
          headline: 'Genuine',
          detail: 'PlaySphere holds the results behind this certificate. What '
              'is drawn below is rebuilt from them rather than from the copy '
              'you were shown — so if the two differ, trust this one.',
          code: _code,
        ),
        const SizedBox(height: 24),
        CertificateCard(certificate: certificate),
      ],
    );
  }

  /// The short code, recomputed here so the page can echo back what the person
  /// typed. Derived from the ids in the URL, so it cannot disagree with them.
  String? get _code => Certificate(
        recipientName: '',
        title: CertificateTitle.participation,
        eventName: '',
        tournamentName: '',
        organizerName: '',
        sportName: '',
        date: DateTime(2000),
        orgId: orgId,
        tournamentId: tournamentId,
        compId: compId,
        entrantId: entrantId,
      ).verifyCode;
}

/// The answer, stated first and plainly.
///
/// A verification page's whole job is one sentence somebody can act on. The
/// certificate underneath is supporting evidence; the verdict is the product.
class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.icon,
    required this.tone,
    required this.headline,
    required this.detail,
    this.code,
  });

  final IconData icon;
  final Color tone;
  final String headline;
  final String detail;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tone, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(detail, style: theme.textTheme.bodyMedium),
              if (code != null) ...[
                const SizedBox(height: 10),
                // Echoed back so somebody who typed a code by hand can see
                // they typed the one they meant to.
                Text(
                  'Code $code',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
