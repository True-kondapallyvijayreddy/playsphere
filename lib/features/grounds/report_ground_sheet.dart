/// Telling PlaySphere that a listing is not what it claims to be.
///
/// ## Why this is worth a screen of its own
///
/// It is the only route by which the product learns that a ground is fake.
/// Every other signal — the capture, the risk flags, the arrivals — is
/// evidence gathered before or around the fraud. This is the one that comes
/// from the person it happened to, and it arrives in the hour after they were
/// asked for ₹2000 on UPI, which is the only hour in which the next booker
/// can still be saved.
///
/// So the flow is short: pick the thing that happened, add a line if you
/// want, done. No sign-in wall beyond the one already there, no "are you
/// sure", no free-text-only box that produces a hundred unsortable
/// paragraphs. The reasons are a closed list because they are weighted — see
/// `GroundReportReason` — and a weighted list is what lets two credible fraud
/// reports take a listing down tonight instead of on Monday.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ground.dart';
import '../../core/models/ground_verification.dart';
import '../../core/providers.dart';
import '../../data/ground_repository.dart';
import '../../shared/app_scaffold.dart';

/// Opens the report sheet for [ground]. Returns true if something was filed.
Future<bool> showReportGroundSheet(
  BuildContext context, {
  required Ground ground,
  String? bookingId,
}) async {
  final filed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => _ReportSheet(
        ground: ground,
        bookingId: bookingId,
        scrollController: controller,
      ),
    ),
  );
  return filed ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.ground,
    required this.bookingId,
    required this.scrollController,
  });

  final Ground ground;
  final String? bookingId;
  final ScrollController scrollController;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  GroundReportReason? _reason;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final me = ref.read(actingProfileProvider);
    final reason = _reason;
    if (me == null || reason == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(groundRepositoryProvider).reportGround(
            ground: widget.ground,
            reporter: me,
            reason: reason,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            bookingId: widget.bookingId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reported. If others report the same thing the listing comes '
            'down automatically.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = ref.watch(authUidProvider);

    // Somebody who already reported this listing sees what they said rather
    // than an empty form. Filing again would only overwrite it, and a form
    // that silently replaces an earlier answer is how a considered report
    // becomes an accidental retraction.
    final existing = uid == null
        ? const AsyncValue<GroundReport?>.data(null)
        : ref.watch(myGroundReportProvider(
            (groundId: widget.ground.id, uid: uid),
          ));

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Report ${widget.ground.name}',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'What happened? Your name is not shown to the ground owner.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        if (existing.valueOrNull != null) ...[
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('You already reported this'),
              subtitle: Text(existing.value!.reason.label),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choosing a different reason below replaces what you said.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
        ],
        for (final reason in GroundReportReason.values)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: _reason == reason
                ? theme.colorScheme.primaryContainer
                : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _reason = reason),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _reason == reason
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _reason == reason
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  reason.label,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              // The money ones are marked. A person scanning
                              // this list in a temper needs the one that
                              // matches their situation to be findable in a
                              // second, and "he asked me to pay" is the
                              // situation this list exists for.
                              if (reason.isFraud)
                                Icon(
                                  Icons.priority_high,
                                  size: 16,
                                  color: theme.colorScheme.error,
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            reason.blurb,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Anything else? (optional)',
            hintText:
                'e.g. He asked for ₹2000 on GPay to hold Sunday 6pm, then '
                'blocked my number.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Do not include your bank details or a screenshot of a payment '
          'here. If you have already lost money, report it to your bank and '
          'to cybercrime.gov.in as well as here.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || _reason == null ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(_busy ? 'Sending…' : 'Send report'),
        ),
      ],
    );
  }
}
