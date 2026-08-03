import 'package:flutter/material.dart';

import '../../../domain/tournament/certificate.dart';

/// The certificate itself, as a widget so it can be both previewed and
/// captured to an image from the same code.
///
/// Fixed at a 1.414:1 landscape ratio — A4 — because the thing people do with
/// these is print them, and a certificate that comes out of a printer with a
/// white band down one side looks like what it is.
///
/// Styled independently of the app theme, on purpose. A certificate is shared
/// outside the app and printed on paper: it must read the same to a viewer in
/// dark mode, and ink on white is the only version of it that survives a
/// printer.
class CertificateCard extends StatelessWidget {
  const CertificateCard({super.key, required this.certificate});

  final Certificate certificate;

  static const aspectRatio = 1.414;

  /// Deep indigo and gold. Chosen to survive photocopying, which a grassroots
  /// certificate reliably meets.
  static const _ink = Color(0xFF1A1A3E);
  static const _gold = Color(0xFF9A7B2F);
  static const _muted = Color(0xFF5A5A72);

  @override
  Widget build(BuildContext context) {
    final c = certificate;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        color: Colors.white,
        child: Stack(
          children: [
            // Double border — the visual convention that says "certificate"
            // faster than any wording can.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _gold, width: 3),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _gold.withValues(alpha: 0.45)),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(44, 34, 44, 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        Text(
                          c.organizerName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          c.title.label.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ink,
                            fontSize: c.title.isPodium ? 30 : 22,
                            height: 1.1,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(width: 90, height: 2, color: _gold),
                      ],
                    ),

                    Column(
                      children: [
                        Text(
                          c.citation,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.recipientName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          c.achievement,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c.eventLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          c.tournamentName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(width: 110, height: 1, color: _muted),
                              const SizedBox(height: 4),
                              Text(
                                Certificate.formatDate(c.date),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                ),
                              ),
                              if (c.venueName != null)
                                Text(
                                  c.venueName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            Icon(Icons.emoji_events,
                                color: _gold, size: c.title.isPodium ? 30 : 22),
                            const SizedBox(height: 2),
                            Text(
                              c.sportName,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 9,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(width: 110, height: 1, color: _muted),
                              const SizedBox(height: 4),
                              const Text(
                                'Organizer',
                                style: TextStyle(color: _muted, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
