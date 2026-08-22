import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/medical/sports_medicine_library.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// The front door of the Sports Medicine & Performance hub.
///
/// A hub, not a feed, for the same reason `GiveHomeScreen` is: the person
/// arriving here has exactly one of four questions, and three of them are
/// urgent. The emergency card sits above everything — including above the
/// directory — because the one journey that must never require reading a
/// screen first is the one where somebody is on the ground.
///
/// Deliberately org-free. An injury belongs to a person, not to whichever of
/// their clubs they happen to have selected.
class SportsMedicineScreen extends ConsumerWidget {
  const SportsMedicineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mine = ref.watch(mySportsMedicProfileProvider).valueOrNull;
    final signedIn = ref.watch(currentUidProvider) != null;

    return AppScaffold(
      title: 'Sports medicine',
      subtitle: 'Doctors, physios, warm-ups and injuries',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _EmergencyBanner(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    'Find a sports doctor or physiotherapist near you, warm '
                    'up the way your sport actually needs, and know what to '
                    'do in the first ten minutes after an injury.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
                const SizedBox(height: 8),

                _HubTile(
                  icon: Icons.medical_services_outlined,
                  title: 'Doctors & physiotherapists',
                  subtitle:
                      'Search by city, sport and specialty — then call them',
                  onTap: () => context.push(Routes.sportsMedics),
                ),
                _HubTile(
                  icon: Icons.directions_run_outlined,
                  title: 'Pre-match warm-ups',
                  subtitle:
                      '${SportsMedicineLibrary.workouts.length} routines — '
                      'FIFA 11+, RAMP, fast bowling, court footwork',
                  onTap: () => context.push(Routes.sportsWarmups),
                ),
                _HubTile(
                  icon: Icons.healing_outlined,
                  title: 'Injuries & first aid',
                  subtitle:
                      '${SportsMedicineLibrary.injuries.length} injuries by '
                      'body part — what to do, and when to see a doctor',
                  onTap: () => context.push(Routes.sportsInjuries),
                ),
                _HubTile(
                  icon: Icons.emergency_outlined,
                  title: 'On-field emergencies',
                  subtitle:
                      'Concussion, collapse, heat stroke, fractures, bleeding',
                  onTap: () => context.push(Routes.sportsEmergency),
                  tint: Ps.live,
                ),

                const SizedBox(height: 18),
                if (signedIn)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.local_hospital_outlined,
                        color: Ps.primary,
                      ),
                      title: Text(
                        mine == null
                            ? 'Are you a doctor or physiotherapist?'
                            : 'Your practice listing',
                      ),
                      subtitle: Text(
                        mine == null
                            ? 'List your practice and be found by players and '
                                'clubs near you'
                            : mine.isActive
                                ? '${mine.role.label} · '
                                    '${mine.city.isEmpty ? 'no city set' : mine.city}'
                                : 'Currently delisted',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.mySportsMedicProfile),
                    ),
                  ),

                const SizedBox(height: 16),
                const _StandingDisclaimer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The red block at the top of the hub.
///
/// Above the fold and above every other tile on purpose. Everything else on
/// this screen is read at leisure; this is the one that is opened with one
/// hand while kneeling next to somebody, and a person in that state should
/// not have to find a menu item.
class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Ps.live.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.live.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emergency_share_outlined, size: 20, color: Ps.live),
              SizedBox(width: 8),
              Text(
                'Someone is down right now?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Ps.live,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Not breathing normally, neck pain, a seizure, confusion in the '
            'heat, or a limb at the wrong angle — call an ambulance first '
            'and read second.',
            style: TextStyle(fontSize: 13, height: 1.45, color: Ps.ink),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Ps.live,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  // `tel:` rather than a dialer intent, so it works
                  // identically on Android, iOS and the web build — where it
                  // hands off to whatever the machine has registered.
                  onPressed: () => launchUrl(
                    Uri(scheme: 'tel', path: EmergencyNumbers.unified),
                  ),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call 112'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Ps.live,
                    minimumSize: const Size.fromHeight(46),
                    side: BorderSide(
                      color: Ps.live.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: () => launchUrl(
                    Uri(scheme: 'tel', path: EmergencyNumbers.ambulance),
                  ),
                  icon: const Icon(Icons.local_hospital_outlined, size: 18),
                  label: const Text('Ambulance 108'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The line that has to appear wherever this content does.
///
/// PlaySphere is publishing warm-ups and first-aid protocols to people who
/// are not clinicians. Saying plainly that none of it is a diagnosis is not
/// legal decoration — it is the difference between a reference somebody uses
/// alongside a doctor and one they use instead of a doctor.
class _StandingDisclaimer extends StatelessWidget {
  const _StandingDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Ps.muted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Everything in this section is general guidance drawn from '
              'published sports-medicine protocols. It is not a diagnosis '
              'and it does not replace seeing a doctor. Practitioners listed '
              'here write their own profiles; PlaySphere does not employ '
              'them and does not vouch for their treatment.',
              style: TextStyle(fontSize: 12, height: 1.45, color: Ps.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Ps.primary;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Ps.radiusSm),
          ),
          child: Icon(icon, size: 21, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
