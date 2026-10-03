import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/tournament_invite.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/tournament/invitation_letter.dart';
import '../../../shared/app_messenger.dart' show showAppMessage;
import '../../../shared/app_scaffold.dart' show showError;
import '../../../shared/identity.dart';
import '../../../shared/ui_kit.dart';

/// One club's invitation to another, as the invited club receives it.
///
/// ## Why a letter and not a notification row
///
/// "Nizampet Sports Club has invited you" in a list of forty notifications is
/// a line people scroll past. An invitation is an offer to come and play, and
/// it reads like one: who is hosting, which sports, when, where, the host's
/// own words — and one button that goes straight to the registration page.
///
/// ## What "Register now" does
///
/// For somebody who runs the invited club it accepts the invitation first,
/// because the rules only let an invited club enter a side once it has said
/// yes, and then opens the registration page. Two taps — accept, then find
/// the season, then find the event — became one. Everybody else at the club
/// goes to the same page, where they can say they are available.
class InvitationCard extends ConsumerStatefulWidget {
  const InvitationCard({super.key, required this.invite});

  final TournamentInvite invite;

  @override
  ConsumerState<InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends ConsumerState<InvitationCard> {
  bool _busy = false;

  /// The host's letter, or — for an invitation sent before letters existed —
  /// the one the host would have been offered.
  String get _letter {
    final i = widget.invite;
    final written = i.message?.trim() ?? '';
    if (written.startsWith(InvitationLetter.greeting)) return written;
    final composed = InvitationLetter.compose(
      hostClubName: i.fromOrgName,
      seasonName: i.tournamentName,
      kind: i.kind,
      sports: i.sportNames,
      startDate: i.startDate,
      endDate: i.endDate,
      place: i.place,
    );
    // An old one-line note is kept, under the letter, in the host's words.
    return written.isEmpty ? composed : '$composed\n\n“$written”';
  }

  Future<void> _register({required bool canAnswer}) async {
    final i = widget.invite;
    if (_busy) return;
    if (canAnswer && (i.isPending || i.canChangeAnswer(DateTime.now()))) {
      setState(() => _busy = true);
      try {
        await ref
            .read(tournamentRepositoryProvider)
            .respondToInvite(inviteId: i.id, status: 'accepted');
      } catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          showError(context, e);
        }
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
    }
    if (!mounted) return;
    context.push(Routes.seasonRegister(i.fromOrgId, i.tournamentId));
  }

  Future<void> _decline() async {
    if (_busy) return;
    // The host plans next season around the answers it gets, so a "no" asks
    // why (TC-CLUB-011). One tap on a common reason, or their own words.
    final reason = await _askDeclineReason(context, widget.invite.fromOrgName);
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    // Held here, not read again in the Undo: the card may have rebuilt or
    // left the list by the time somebody presses it.
    final repo = ref.read(tournamentRepositoryProvider);
    final inviteId = widget.invite.id;
    try {
      await repo.respondToInvite(
        inviteId: inviteId,
        status: 'declined',
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              content: Text(
                'Declined. ${widget.invite.fromOrgName} will see your answer. '
                'You can change it for 24 hours.',
              ),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => repo
                    .undoDecline(inviteId: inviteId)
                    .catchError(showAppMessage),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _commonReasons = [
    'The dates clash with our own fixtures',
    'We do not have enough players',
    'The venue is too far for us',
    'Our members are in exams',
  ];

  static Future<String?> _askDeclineReason(BuildContext context, String host) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final text = controller.text.trim();
          return AlertDialog(
            title: const Text('Not this time?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tell $host why — it helps them plan the next one.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in _commonReasons)
                        ChoiceChip(
                          label: Text(r),
                          selected: text == r,
                          onSelected: (_) => setState(() {
                            controller.text = r;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLength: 300,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed:
                    text.isEmpty ? null : () => Navigator.of(ctx).pop(text),
                child: const Text('Decline'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invite;
    // Answering is for the people who run the INVITED club — the same line
    // the rules draw on `tournamentInvites` updates.
    final canAnswer = ref
        .watch(myCapabilitiesProvider(i.toOrgId))
        .contains(Capability.manageCompetitions);
    final when = InvitationLetter.dateSpan(i.startDate, i.endDate);
    final sports = InvitationLetter.sportList(i.sportNames);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Ps.surface,
          borderRadius: BorderRadius.circular(Ps.radius),
          border: Border.all(color: Ps.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- The masthead: who is asking, and for what ------------
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F766E), Ps.primary],
                ),
              ),
              child: Row(
                children: [
                  PsCrest(name: i.fromOrgName, seed: i.fromOrgId, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'INVITATION · ${i.kind.label.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          i.tournamentName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          'From ${i.fromOrgName} to ${i.toOrgName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!i.isPending) _StatusPill(invite: i),
                ],
              ),
            ),

            // ---- The facts, at a glance ------------------------------
            if (sports.isNotEmpty || when.isNotEmpty || i.place != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (sports.isNotEmpty)
                      _Fact(icon: Icons.sports_outlined, text: sports),
                    if (when.isNotEmpty)
                      _Fact(
                        icon: Icons.event_outlined,
                        // "from 12 Aug to 24 Aug 2026" reads better as a fact
                        // without its preposition.
                        text: when.replaceFirst(RegExp(r'^(from|on) '), ''),
                      ),
                    if (i.place != null)
                      _Fact(icon: Icons.place_outlined, text: i.place!),
                  ],
                ),
              ),

            // ---- The letter ------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _letter,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Ps.ink,
                ),
              ),
            ),

            if (i.isDeclined && (i.declineReason ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  '${i.toOrgName} declined: “${i.declineReason}”',
                  style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Ps.ink,
                  ),
                ),
              ),

            // ---- The answer ------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (canAnswer && i.isPending)
                    TextButton(
                      onPressed: _busy ? null : _decline,
                      child: const Text('Not this time'),
                    ),
                  if (canAnswer && i.canChangeAnswer(DateTime.now()))
                    FilledButton.icon(
                      onPressed:
                          _busy ? null : () => _register(canAnswer: canAnswer),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Changed our mind — accept'),
                    ),
                  if (!i.isDeclined && !i.isWithdrawn)
                    FilledButton.icon(
                      onPressed:
                          _busy ? null : () => _register(canAnswer: canAnswer),
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.how_to_reg_outlined, size: 18),
                      label: Text(
                        canAnswer
                            ? (i.isPending ? 'Accept & register' : 'Register')
                            : 'Open registration',
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => context.push(
                        Routes.publicTournament(i.fromOrgId, i.tournamentId),
                      ),
                      child: const Text('Have a look'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Ps.primary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Ps.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.invite});

  final TournamentInvite invite;

  @override
  Widget build(BuildContext context) {
    final label = switch (invite.status) {
      'accepted' => 'Coming',
      'declined' => 'Declined',
      'withdrawn' => 'Withdrawn',
      _ => 'Waiting',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
