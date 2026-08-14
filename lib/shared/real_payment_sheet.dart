import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/billing.dart';
import '../core/providers.dart';

/// Opens a Razorpay payment link and waits for the server's own answer.
///
/// Returns `true` once `payments/{paymentId}`'s `status` reaches
/// [PlanPaymentStatus.paid] — written by `functions/razorpay.js`'s webhook,
/// never by this screen. Returns `false` if the sheet is dismissed before
/// that happens, which is not a failure: the payer may still be on the
/// checkout page in their browser, and the webhook will land whenever it
/// lands. The next time this plan's status is read, it will simply already
/// be paid — there is nothing to retry or clean up.
Future<bool> showRealPaymentSheet(
  BuildContext context, {
  required String paymentId,
  required String url,
}) async {
  // Opened immediately rather than waiting for a tap: the person already
  // asked to pay by starting this flow, and a page that doesn't open until a
  // second tap reads as broken, not as a confirmation step.
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  if (!context.mounted) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: true,
    isScrollControlled: true,
    builder: (_) => _WaitingSheet(paymentId: paymentId, url: url),
  );
  return result ?? false;
}

class _WaitingSheet extends ConsumerWidget {
  const _WaitingSheet({required this.paymentId, required this.url});

  final String paymentId;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(paymentStatusProvider(paymentId));
    final theme = Theme.of(context);

    return status.when(
      loading: () => const _Waiting(),
      error: (_, __) => const _Waiting(),
      data: (s) {
        if (s == PlanPaymentStatus.paid) {
          // Pops itself the moment the webhook lands — a Firestore listener
          // firing mid-build cannot pop synchronously, so it schedules the
          // pop for right after this frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(true);
            }
          });
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s == PlanPaymentStatus.failed) ...[
                  Icon(Icons.error_outline,
                      size: 40, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('That payment did not go through',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Nothing was charged. Close this and try again.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('Waiting for payment', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Complete the payment in the page that opened. This '
                    'updates itself the moment it\'s confirmed — no need to '
                    'come back and check.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Reopen the payment page'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
}
