import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import '../../core/models/organization.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../../domain/ranking/ranking_points.dart';
import '../../domain/tournament/certificate.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/certificate_card.dart';

/// Certificates for everyone who played, generated from the results.
///
/// A grassroots player currently finishes a tournament and receives nothing —
/// the result goes to a Telegram channel, the channel scrolls, and a year later
/// there is no evidence they were there. Nothing on these is typed by hand, so
/// a certificate cannot claim a result the fixtures do not support.
class CertificatesScreen extends ConsumerWidget {
  const CertificatesScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tAsync = ref.watch(tournamentProvider(key));

    return AppScaffold(
      orgId: orgId,
      title: 'Certificates',
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }

          final events =
              ref.watch(tournamentEventsProvider(key)).valueOrNull ??
                  const <Competition>[];
          final fixtures =
              ref.watch(tournamentFixturesProvider(tournamentId)).valueOrNull ??
                  const <Fixture>[];
          final org = ref.watch(organizationProvider(orgId)).valueOrNull;

          final sections = _build(tournament, events, fixtures, org);

          if (sections.isEmpty) {
            return const EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'No certificates yet',
              message: 'Certificates appear once an event is finished — every '
                  'match played and every result in. Nothing here is typed by '
                  'hand, so nothing can claim a result the matches do not '
                  'show.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(
                          section.eventName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final c in section.certificates)
                        _CertificateTile(certificate: c),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// One section per finished event, best placing first.
  List<({String eventName, List<Certificate> certificates})> _build(
    Tournament tournament,
    List<Competition> events,
    List<Fixture> fixtures,
    Organization? org,
  ) {
    final byComp = <String, List<Fixture>>{};
    for (final f in fixtures) {
      byComp.putIfAbsent(f.compId, () => []).add(f);
    }

    final sections = <({String eventName, List<Certificate> certificates})>[];
    for (final event in events) {
      final own = byComp[event.id] ?? const <Fixture>[];
      // Only a finished event certifies anything: half a draw has leaders,
      // not placings, and a certificate handed out early cannot be recalled.
      if (own.isEmpty || own.any((f) => !f.status.isResulted)) continue;

      final awards = RankingPoints.award(
        tournament: tournament,
        event: event,
        fixtures: own,
      );
      if (awards.isEmpty) continue;

      sections.add((
        eventName: event.name,
        certificates: [
          for (final a in awards)
            Certificate(
              recipientName: a.displayName,
              title: CertificateTitle.fromRound(a.round),
              eventName: event.name,
              tournamentName: tournament.name,
              organizerName: org?.name ?? 'PlaySphere',
              sportName: event.sportName,
              categoryLabel: event.category.label,
              date: tournament.endDate ?? tournament.startDate ?? DateTime.now(),
            ),
        ],
      ));
    }
    return sections;
  }
}

class _CertificateTile extends StatelessWidget {
  const _CertificateTile({required this.certificate});

  final Certificate certificate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = certificate;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          c.title.isPodium
              ? Icons.workspace_premium
              : Icons.workspace_premium_outlined,
          color: c.title.isPodium ? theme.colorScheme.primary : null,
        ),
        title: Text(c.recipientName),
        subtitle: Text(c.title.label, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => CertificatePreview.show(context, certificate: c),
      ),
    );
  }
}

/// Full-size preview, with the one button that matters.
class CertificatePreview extends StatefulWidget {
  const CertificatePreview({super.key, required this.certificate});

  final Certificate certificate;

  static Future<void> show(
    BuildContext context, {
    required Certificate certificate,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) => CertificatePreview(certificate: certificate),
      );

  @override
  State<CertificatePreview> createState() => _CertificatePreviewState();
}

class _CertificatePreviewState extends State<CertificatePreview> {
  final _boundary = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The boundary is what gets captured, so it wraps the certificate
            // and nothing else — no dialog chrome, no buttons.
            RepaintBoundary(
              key: _boundary,
              child: CertificateCard(certificate: widget.certificate),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _capture();
      if (bytes == null) throw StateError('Could not render the certificate.');

      await SharePlus.instance.share(
        ShareParams(
          // Bytes rather than a temp file, so this needs no filesystem
          // permission and no extra dependency, and works on web where there
          // is no path to write to.
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: widget.certificate.fileName,
            ),
          ],
          text: '${widget.certificate.recipientName} — '
              '${widget.certificate.title.label}, '
              '${widget.certificate.tournamentName}',
        ),
      );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not share that certificate. $e')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Renders the certificate to a PNG.
  ///
  /// Captured at 3× so it survives being printed, which is the main thing
  /// anybody does with one. At screen resolution an A4 print is visibly soft.
  Future<Uint8List?> _capture() async {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final image = await object.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}
