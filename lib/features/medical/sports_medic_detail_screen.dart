import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sports_medic.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/medical/sports_medicine_library.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// One practitioner's page: what they have said about themselves, the number
/// that lets somebody check it, and the ways to reach them.
///
/// The contact buttons are the point of the screen — this directory exists so
/// that a player with a torn hamstring on Saturday can be speaking to a
/// physiotherapist on Sunday. Everything above them is there to make that call
/// an informed one rather than a hopeful one.
class SportsMedicDetailScreen extends ConsumerWidget {
  const SportsMedicDetailScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medic = ref.watch(sportsMedicProvider(uid));
    final isMe = ref.watch(authUidProvider) == uid;

    return AsyncView(
      value: medic,
      onRetry: () => ref.invalidate(sportsMedicProvider(uid)),
      builder: (m) {
        if (m == null) {
          return const AppScaffold(
            title: 'Practitioner',
            body: EmptyState(
              icon: Icons.person_off_outlined,
              title: 'No listing here',
              message: 'This practitioner has not published a profile.',
            ),
          );
        }
        return AppScaffold(
          title: m.displayName,
          subtitle: m.role.label,
          actions: isMe
              ? [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit listing',
                    onPressed: () => context.push(Routes.mySportsMedicProfile),
                  ),
                ]
              : null,
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              ContentBounds(
                maxWidth: 700,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A delisted profile stays reachable by anybody holding
                      // the link, so it has to say so rather than read as a
                      // practice that is open.
                      if (!m.isActive)
                        const _Notice(
                          icon: Icons.visibility_off_outlined,
                          text: 'This listing is switched off and does not '
                              'appear in searches.',
                        ),
                      if (m.isActive && !m.acceptingNewPatients)
                        const _Notice(
                          icon: Icons.event_busy_outlined,
                          text: 'Not taking new patients at the moment. The '
                              'listing is still here for when that changes.',
                        ),

                      if (m.headline?.isNotEmpty == true) ...[
                        Text(
                          m.headline!,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Ps.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: const Icon(
                              Icons.medical_services_outlined,
                              size: 16,
                            ),
                            label: Text(m.role.label),
                          ),
                          if (m.isVerified)
                            const Chip(
                              avatar: Icon(Icons.verified, size: 16),
                              label: Text('Verified'),
                            ),
                          if (m.experienceYears > 0)
                            Chip(
                              label: Text('${m.experienceYears} years'),
                            ),
                          Chip(label: Text(m.feeLabel)),
                          for (final mode in m.consultationModes)
                            Chip(label: Text(mode.label)),
                        ],
                      ),

                      if (m.bio?.isNotEmpty == true) ...[
                        const SizedBox(height: 18),
                        Text(
                          m.bio!,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Ps.ink,
                          ),
                        ),
                      ],

                      _Facts(medic: m),

                      // Printed rather than hidden, and printed next to the
                      // council it belongs to, because a number a patient can
                      // look up on a public register is worth more than any
                      // badge PlaySphere could award by hand.
                      if (m.registrationNumber?.isNotEmpty == true) ...[
                        const SizedBox(height: 14),
                        _Notice(
                          icon: Icons.badge_outlined,
                          text: 'Registration ${m.registrationNumber}'
                              '${m.councilName?.isNotEmpty == true ? ' · ${m.councilName}' : ''}'
                              '. This is the practitioner’s own entry — you '
                              'can check it against the council’s public '
                              'register before your first appointment.',
                        ),
                      ],

                      const SizedBox(height: 16),
                      _ContactBlock(medic: m),

                      const SizedBox(height: 22),
                      _Notice(
                        icon: Icons.info_outline,
                        text: m.isVerified
                            ? 'PlaySphere has checked this practitioner’s '
                                'identity and registration number against a '
                                'public register. That is all it means: it is '
                                'not a clinical endorsement, not a '
                                'recommendation, and not a statement about '
                                'the treatment you will receive.'
                            : 'Everything on this page was written by the '
                                'practitioner and has not been checked by '
                                'PlaySphere. Verify the registration number '
                                'on the council’s public register before your '
                                'first appointment.',
                      ),
                      const _Notice(
                        icon: Icons.emergency_outlined,
                        text: 'In an emergency do not wait for a call back. '
                            'Dial ${EmergencyNumbers.unified} or '
                            '${EmergencyNumbers.ambulance}.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Call, WhatsApp, email — in that order, and only the ones that exist.
///
/// Three buttons rather than one "Contact" that opens a sheet, because the
/// choice between them is not a preference: a clinic landline is answered in
/// working hours and a WhatsApp message is read at nine at night, and somebody
/// deciding which to use is making a real decision about how fast they need an
/// answer.
class _ContactBlock extends StatelessWidget {
  const _ContactBlock({required this.medic});

  final SportsMedicProfile medic;

  Future<void> _open(BuildContext context, Uri uri, String what) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $what on this device')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = medic.contactPhone;
    final whatsapp = medic.whatsappPhone;
    final email = medic.email;

    if (phone == null && whatsapp == null && email == null) {
      return const _Notice(
        icon: Icons.phone_disabled_outlined,
        text: 'This practitioner has not published a way to contact them '
            'directly. Their clinic address is above.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => _open(
              context,
              Uri(scheme: 'tel', path: phone),
              'the dialer',
            ),
            icon: const Icon(Icons.call_outlined),
            label: Text('Call ${medic.displayName.split(' ').first}'),
          ),
        if (whatsapp != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            // `wa.me` rather than a `whatsapp://` scheme: the https form
            // falls back to the browser when WhatsApp is not installed,
            // where the scheme form simply fails to launch.
            onPressed: () => _open(
              context,
              Uri.https('wa.me', '/${_digits(whatsapp)}'),
              'WhatsApp',
            ),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Message on WhatsApp'),
          ),
        ],
        if (email != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => _open(
              context,
              Uri(scheme: 'mailto', path: email),
              'your mail app',
            ),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Email'),
          ),
        ],
      ],
    );
  }

  /// `wa.me` accepts digits only — no plus, no spaces, no dashes — and
  /// silently fails on anything else, which would look to the user like
  /// WhatsApp being broken rather than a number being formatted.
  static String _digits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');
}

/// The list-shaped claims: what they hold, what they treat, where they are.
class _Facts extends StatelessWidget {
  const _Facts({required this.medic});

  final SportsMedicProfile medic;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, List<String>)>[
      (
        Icons.workspace_premium_outlined,
        'Qualifications',
        medic.qualifications,
      ),
      (
        Icons.sports_outlined,
        'Sports',
        medic.sportIds.isEmpty
            // Empty means "all sports" here, not "none" — the opposite of a
            // coach listing, and stated so nobody reads a blank row as a gap
            // in the profile.
            ? const ['All sports']
            : [for (final id in medic.sportIds) SportCatalog.byId(id).name],
      ),
      (
        Icons.healing_outlined,
        'Treats',
        [
          for (final w in medic.bodyPartsTreated) BodyPart.fromWire(w).label,
        ],
      ),
      (Icons.translate_outlined, 'Languages', medic.languages),
      (
        Icons.place_outlined,
        'Clinic',
        [
          if (medic.clinicName.isNotEmpty) medic.clinicName,
          if (medic.address?.isNotEmpty == true) medic.address!,
          if (medic.city.isNotEmpty) medic.city,
          if (medic.district?.isNotEmpty == true) medic.district!,
        ],
      ),
    ];

    final shown = [for (final r in rows) if (r.$3.isNotEmpty) r];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: Ps.surface,
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(color: Ps.border),
          ),
          child: Column(
            children: [
              for (final (icon, label, values) in shown)
                ListTile(
                  dense: true,
                  leading: Icon(icon, size: 19, color: Ps.muted),
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Ps.faint,
                    ),
                  ),
                  subtitle: Text(
                    values.join('  ·  '),
                    style: const TextStyle(fontSize: 13.5, color: Ps.ink),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Ps.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Ps.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
