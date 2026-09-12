import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_router.dart';

/// The one place the product asks somebody to upgrade.
///
/// ## Why it says what the free version still does
///
/// A paywall that only lists what is locked reads as a punishment for having
/// been a free user, and the honest position here is the opposite: nothing a
/// free member could already do has been taken away. So every call passes a
/// message that names the perk AND names what stays free, and the sheet has
/// a plain "Not now" that closes it without argument.
///
/// Nothing needed to take part in sport is ever behind this — see
/// `PremiumScreen`'s class doc, which this is the enforcement half of.
Future<void> showPremiumRequired(
  BuildContext context, {
  required String title,
  required String message,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(message, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push(Routes.premium);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('See Premium'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Not now'),
              ),
            ],
          ),
        );
      },
    );
