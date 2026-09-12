import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/enums.dart';
import '../../core/models/membership_application.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import 'widgets/applicant_review_sheet.dart';

class JoinOrgScreen extends ConsumerStatefulWidget {
  const JoinOrgScreen({super.key, this.initialCode});

  /// Carried by an invite link or a scanned QR. Prefills the box and looks
  /// the club up straight away; it never joins anything on its own.
  final String? initialCode;

  @override
  ConsumerState<JoinOrgScreen> createState() => _JoinOrgScreenState();
}

class _JoinOrgScreenState extends ConsumerState<JoinOrgScreen> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  final _note = TextEditingController();
  InviteTarget? _found;
  bool _busy = false;
  String? _notFound;

  @override
  void initState() {
    super.initState();
    // Arriving from an invite link, the code is already known. Looking it up
    // straight away means the person sees the club they were invited to
    // rather than a form they have to poke first.
    if ((widget.initialCode ?? '').trim().length >= 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _code.text.trim();
    if (code.length < 4) return;

    setState(() {
      _busy = true;
      _notFound = null;
      _found = null;
    });
    try {
      final org = await ref.read(orgRepositoryProvider).findByInviteCode(code);
      setState(() {
        _found = org;
        _notFound = org == null
            ? 'No organization uses that code. Check it with whoever invited '
                'you — codes never contain the letter O or the digit 0.'
            : null;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final target = _found;
    // The acting profile — the signed-in guardian, or a managed child
    // they're currently "managing as" — so joining a club works the same
    // way asking to join a team already does.
    final user = ref.read(actingProfileProvider);
    if (target == null || user == null) return;

    setState(() => _busy = true);
    try {
      // The repository reports the status actually written. The screen used to
      // announce "You have joined" purely from the club's setting while the
      // membership was written as pending regardless — the user walked away
      // believing they were in.
      final status = await ref.read(orgRepositoryProvider).requestToJoin(
            orgId: target.orgId,
            user: user,
            requiresApproval: target.requiresApprovalToJoin,
            application: _application(user),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == MembershipStatus.active
                ? 'You have joined ${target.orgName}.'
                : 'Request sent. An admin at ${target.orgName} will review it.',
          ),
        ),
      );
      // The join is done, so the form must not stay behind the club list —
      // backing into it would invite a second request for a club already
      // joined.
      context.pushReplacement(Routes.orgs);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The introduction that travels with the request.
  ///
  /// Built here rather than in the repository because it describes the person
  /// applying, and this screen is the only place that has all three sources
  /// open at once — the profile, their own career record, and what they just
  /// typed. See [MembershipApplication] for why a club reads this rather than
  /// the profile itself.
  ///
  /// The career read is `valueOrNull`: somebody applying to their first club
  /// on a slow connection must not be made to wait on a stream whose only job
  /// is to enrich a message. An application with no sports on it is honest —
  /// a brand-new player genuinely has none.
  MembershipApplication _application(AppUser user) {
    final career = ref.read(careerProvider(user.uid)).valueOrNull ?? const [];
    final played = [
      for (final line in career)
        if (line.matchesPlayed > 0)
          ApplicantSport(
            sportId: line.sportId,
            matchesPlayed: line.matchesPlayed,
          ),
    ]..sort((a, b) => b.matchesPlayed.compareTo(a.matchesPlayed));

    return buildApplication(
      user: user,
      // Four is what the review sheet can show without becoming a scroll.
      // Somebody who plays more than four sports is described well enough by
      // their four biggest.
      sports: played.take(4).toList(),
      note: _note.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = _found;

    return Scaffold(
      appBar: AppBar(title: const Text('Join an organization')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the invite code',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Your coach, teacher or club admin will have shared a '
                'six-character code.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'ABC123',
                  border: const OutlineInputBorder(),
                  errorText: _notFound,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _lookup(),
                onChanged: (_) {
                  if (_found != null || _notFound != null) {
                    setState(() {
                      _found = null;
                      _notFound = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              if (target == null)
                FilledButton(
                  onPressed: _busy ? null : _lookup,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Looking…' : 'Find organization'),
                )
              else ...[
                Card(
                  child: ListTile(
                    // `InviteTarget` carries no logo — it is the public
                    // preview a stranger reads before joining — so this gets
                    // the generated crest, seeded on the org id so it matches
                    // the one they will see inside.
                    leading: PsCrest(
                      name: target.orgName,
                      seed: target.orgId,
                      size: 40,
                    ),
                    title: Text(target.orgName),
                    subtitle: Text(
                      [
                        target.orgType.label,
                        if (target.city != null) target.city!,
                      ].join(' · '),
                    ),
                  ),
                ),
                if (target.requiresApprovalToJoin) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _note,
                    maxLines: 3,
                    maxLength: MembershipApplication.maxNoteLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Anything they should know? (optional)',
                      hintText: 'I played U-19 cricket in Warangal and have '
                          'just moved here.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  // Said plainly rather than buried in a policy screen. This
                  // is the moment the sharing happens, and it is the only
                  // moment at which saying so can change what somebody does.
                  Text(
                    'Your name, age, district and the sports you have played '
                    'are sent to this club\u2019s admins so they can decide. '
                    'Nothing is shared with anyone else.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _join,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    _busy
                        ? 'Sending…'
                        : target.requiresApprovalToJoin
                            ? 'Request to join'
                            : 'Join',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
