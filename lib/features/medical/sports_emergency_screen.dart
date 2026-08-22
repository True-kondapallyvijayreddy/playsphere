import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../domain/medical/sports_medicine_library.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'video_link_button.dart';

/// On-field emergencies: concussion, collapse, heat stroke, fractures,
/// bleeding.
///
/// The one screen in PlaySphere designed to be read by somebody kneeling on a
/// pitch with one hand. Three consequences follow, and all three are
/// deliberate departures from the rest of the product:
///
/// * The call buttons are at the top and are duplicated inside every protocol
///   that needs one, because scrolling back up is a thing that does not happen
///   in that moment.
/// * The protocols are expanded, not collapsed. A tap to reveal is one tap too
///   many, and the "what not to do" list is exactly what gets skipped when it
///   is hidden behind a chevron.
/// * The [EmergencyProtocol.oneLine] is set larger than the body text on every
///   card, because if only one line is read it must be that one.
class SportsEmergencyScreen extends StatelessWidget {
  const SportsEmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'On-field emergencies',
      subtitle: 'Call first. Read second.',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ContentBounds(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CallRow(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Text(
                    'These are recognition-and-response protocols for people '
                    'who are not clinicians. They follow published first-aid '
                    'and sports-medicine guidance, and each card names which. '
                    'They do not replace training — if you run a club, get '
                    'two people on a first-aid course.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Ps.muted,
                    ),
                  ),
                ),
                for (final p in SportsMedicineLibrary.emergencies)
                  _ProtocolCard(protocol: p),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Ps.live,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => launchUrl(
                Uri(scheme: 'tel', path: EmergencyNumbers.unified),
              ),
              icon: const Icon(Icons.call, size: 19),
              label: const Text(
                'Call ${EmergencyNumbers.unified}',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Ps.live,
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(color: Ps.live.withValues(alpha: 0.5)),
              ),
              onPressed: () => launchUrl(
                Uri(scheme: 'tel', path: EmergencyNumbers.ambulance),
              ),
              icon: const Icon(Icons.local_hospital_outlined, size: 19),
              label: const Text(
                'Ambulance ${EmergencyNumbers.ambulance}',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.protocol});

  final EmergencyProtocol protocol;

  @override
  Widget build(BuildContext context) {
    final urgent = protocol.callEmergency;
    final accent = urgent ? Ps.live : Ps.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(
          color: urgent ? Ps.live.withValues(alpha: 0.35) : Ps.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  urgent
                      ? Icons.emergency_share_outlined
                      : Icons.medical_information_outlined,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    protocol.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Larger than the body text on purpose: if only one line of this
            // card is read, it has to be this one.
            Text(
              protocol.oneLine,
              style: const TextStyle(
                fontSize: 15.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),

            if (urgent) ...[
              const SizedBox(height: 12),
              // Repeated inside the card rather than left to the row at the
              // top of the screen. Scrolling back up is a thing that does not
              // happen while somebody is on the ground.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Ps.live,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () => launchUrl(
                  Uri(scheme: 'tel', path: EmergencyNumbers.unified),
                ),
                icon: const Icon(Icons.call, size: 18),
                label: const Text('Call an ambulance now'),
              ),
            ],

            const SizedBox(height: 16),
            _List(
              icon: Icons.visibility_outlined,
              title: 'Recognise it',
              items: protocol.recognise,
              color: Ps.muted,
            ),
            _List(
              icon: Icons.checklist_rtl_outlined,
              title: 'Do this, in order',
              items: protocol.steps,
              color: accent,
              numbered: true,
            ),
            _List(
              icon: Icons.block_outlined,
              title: 'Never',
              items: protocol.neverDo,
              color: Ps.live,
              bullet: '✕',
            ),

            if (protocol.source != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Follows ${protocol.source}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Ps.faint,
                  ),
                ),
              ),

            VideoLinkButton(video: protocol.video),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.icon,
    required this.title,
    required this.items,
    required this.color,
    this.numbered = false,
    this.bullet = '•',
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final Color color;

  /// Numbered where order is the instruction. "Recognise it" and "Never" are
  /// sets, not sequences, and numbering them would imply a first thing to
  /// check that the guidance does not claim.
  final bool numbered;

  /// The marker for an unnumbered list. A cross on the "Never" list, because
  /// the shape of the line has to say *not this* before the words are read.
  final String bullet;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      numbered ? '${i + 1}.' : bullet,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      items[i],
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Ps.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
