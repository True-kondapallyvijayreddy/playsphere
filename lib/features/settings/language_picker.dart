import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_controller.dart';
import '../../l10n/app_localizations.dart';

/// Lets a user pick their language.
///
/// Every option is written in its own script — someone looking for Telugu is
/// looking for "తెలుగు", not for the word "Telugu" rendered in Latin. A picker
/// that lists languages in English is useless to precisely the people who
/// need it.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeControllerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            l10n.languageSettingTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        // "Follow the device" is the right default on a shared or borrowed
        // phone, so it stays reachable rather than being a one-way door.
        RadioListTile<Locale?>(
          value: null,
          groupValue: current,
          onChanged: (v) => ref.read(localeControllerProvider.notifier).set(v),
          title: Text(l10n.languageSystemDefault),
        ),
        for (final locale in supportedLocales)
          RadioListTile<Locale?>(
            value: locale,
            groupValue: current,
            onChanged: (v) =>
                ref.read(localeControllerProvider.notifier).set(v),
            title: Text(LocaleController.labelFor(locale)),
          ),
      ],
    );
  }
}

/// Opens the picker as a sheet. Kept here so no caller has to know how the
/// picker is presented.
Future<void> showLanguagePicker(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(child: LanguagePicker()),
    );
