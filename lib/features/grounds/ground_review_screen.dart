/// The queue where a person decides whether a ground listing is real.
///
/// ## Why this screen has to exist for any of the rest to mean anything
///
/// `isVerified` was on the ground model from the beginning. It was written by
/// nothing, set by nobody, and displayed as a tick that no listing in the
/// product had ever earned. A badge with no process behind it is worse than
/// no badge: it tells a booker that PlaySphere checks grounds, which was not
/// true.
///
/// Everything else in this feature produces evidence — on-site photographs,
/// GPS fixes, ownership documents, arrivals, complaints, risk flags. This is
/// the only place it gets read by a human and turned into a decision. Without
/// it, `pending` is a state nothing ever leaves.
///
/// ## What the ordering is for
///
/// There is one person doing this, and there will be one person doing this
/// for a long time. So the queue is sorted by how much damage is currently in
/// progress, not by arrival: complaints first, then submissions carrying the
/// most risk flags, then oldest. A reviewer working top-down is spending
/// their attention correctly even if they only get through four.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/ground.dart';
import '../../core/models/ground_verification.dart';
import '../../core/providers.dart';
import '../../data/ground_repository.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

class GroundReviewScreen extends ConsumerWidget {
  const GroundReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isPlatformAdminProvider);

    return AppScaffold(
      title: 'Ground listings',
      subtitle: 'Verify listings and act on reports',
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            AsyncErrorStrip(value: isAdmin, what: 'your access'),
        data: (admin) {
          // The claim is checked here only so the screen does not present a
          // queue it cannot load. The real gate is `firestore.rules`, which
          // denies the reads outright to anybody without it.
          if (!admin) {
            return const EmptyState(
              icon: Icons.lock_outline,
              title: 'PlaySphere staff only',
              message:
                  'This is where reported and unverified ground listings are '
                  'reviewed.',
            );
          }
          return const _Queue();
        },
      ),
    );
  }
}

class _Queue extends ConsumerWidget {
  const _Queue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(groundReviewQueueProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(groundReviewQueueProvider),
      child: AsyncView(
        value: queue,
        onRetry: () => ref.invalidate(groundReviewQueueProvider),
        builder: (grounds) {
          if (grounds.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 40),
                EmptyState(
                  icon: Icons.done_all,
                  title: 'Nothing waiting',
                  message:
                      'No listing is unreviewed and none has been reported.',
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 760,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in grounds) _ReviewCard(ground: g),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.ground});

  final Ground ground;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _busy = false;
  bool _expanded = false;

  Future<void> _settle(GroundVerificationStatus status) async {
    final g = widget.ground;

    // A note is required for anything that takes a listing down and optional
    // for approval. The owner is shown it, and "your listing was rejected"
    // with no reason is how a genuine operator with a bad photograph becomes
    // a genuine operator who is no longer on PlaySphere.
    String? note;
    if (status != GroundVerificationStatus.verified) {
      note = await _askForNote(status);
      if (note == null) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(groundRepositoryProvider).setVerificationStatus(
            groundId: g.id,
            status: status,
            note: note,
          );
      if (mounted) {
        ref.invalidate(groundReviewQueueProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${g.name}: ${status.label.toLowerCase()}.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForNote(GroundVerificationStatus status) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == GroundVerificationStatus.suspended
            ? 'Suspend this listing'
            : 'Reject this listing'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason shown to the owner',
            hintText: 'e.g. The photographs are of a different ground.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.ground;
    final reports = ref.watch(groundReportsForProvider(g.id));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          g.city,
                          if (g.address != null) g.address!,
                          g.rateLabel,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(g.verificationStatus.label),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // The counters that make a fraud visible at a glance. Bookings
            // against arrivals is the pair that matters: a listing with
            // fourteen bookings and no arrivals is not a busy ground.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Stat(
                  icon: Icons.event_available_outlined,
                  label: '${g.bookingCount} booked',
                ),
                _Stat(
                  icon: Icons.where_to_vote_outlined,
                  label: '${g.checkInCount} arrived',
                  alarming: g.bookingCount >= 5 && g.checkInCount == 0,
                ),
                if (g.reportScore > 0)
                  _Stat(
                    icon: Icons.flag_outlined,
                    label: 'score ${g.reportScore}',
                    alarming: true,
                  ),
                if (g.latitude == null)
                  const _Stat(
                    icon: Icons.location_off_outlined,
                    label: 'no pin',
                    alarming: true,
                  ),
              ],
            ),

            if (g.riskFlags.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final flag in g.riskFlags)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 15, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${flag.label} — ${flag.blurb}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // Complaints in full. The reporter's own words are the most
            // useful thing on this card and the least summarisable.
            ...reports.maybeWhen(
              orElse: () => const <Widget>[],
              data: (list) => list.isEmpty
                  ? const <Widget>[]
                  : [
                      const SizedBox(height: 10),
                      Text('Reports',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      for (final r in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    r.reason.isFraud
                                        ? Icons.priority_high
                                        : Icons.info_outline,
                                    size: 14,
                                    color: r.reason.isFraud
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      r.reason.label,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (r.createdAt != null)
                                    Text(
                                      DateFormat('d MMM').format(r.createdAt!),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                ],
                              ),
                              if (r.note != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 19),
                                  child: Text('“${r.note}”',
                                      style: theme.textTheme.bodySmall),
                                ),
                            ],
                          ),
                        ),
                    ],
            ),

            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(_expanded ? 'Hide evidence' : 'Show the evidence'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (_expanded) _Evidence(groundId: g.id),

            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _settle(GroundVerificationStatus.rejected),
                  child: const Text('Reject'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _settle(GroundVerificationStatus.suspended),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Suspend'),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _settle(GroundVerificationStatus.verified),
                  child: Text(_busy ? 'Saving…' : 'Verify'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The photographs and the ownership document, loaded only when asked for.
///
/// Not eager, because a queue of thirty listings is a hundred and twenty
/// full-size photographs, and a reviewer decides most cards from the counters
/// and the complaints without opening anything.
class _Evidence extends ConsumerWidget {
  const _Evidence({required this.groundId});

  final String groundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final proofs = ref.watch(groundProofsProvider(groundId));
    final claim = ref.watch(groundClaimProvider(groundId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        proofs.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load the photos. $e',
              style: theme.textTheme.bodySmall),
          data: (list) {
            if (list.isEmpty) {
              return Text(
                'No photographs were filed with this listing — it was created '
                'before on-site capture existed, or the submission did not '
                'finish.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              );
            }
            return SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = list[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 150,
                          height: 108,
                          child: PsNetworkImage(
                            url: p.imageUrl,
                            fallback: ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(p.kind.label, style: theme.textTheme.labelSmall),
                      Text(
                        // What makes a photograph evidence rather than a
                        // picture: where it was taken and how sure the phone
                        // was. A reviewer cross-checks these against a map.
                        '${p.latitude.toStringAsFixed(4)}, '
                        '${p.longitude.toStringAsFixed(4)} '
                        '±${p.accuracyMetres.round()}m',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: p.isMocked
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        claim.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (c) {
            if (c == null) {
              return Text('No ownership declaration was filed.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Claim: ${c.claimType.label}',
                    style: theme.textTheme.bodySmall),
                Text('${c.documentKind.label} in the name of ${c.holderName}',
                    style: theme.textTheme.bodySmall),
                if (c.contactPhone != null)
                  Text('Declared number: ${c.contactPhone}',
                      style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: PsNetworkImage(
                      url: c.documentUrl,
                      fallback: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.description_outlined),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, this.alarming = false});

  final IconData icon;
  final String label;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        alarming ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: alarming ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}
