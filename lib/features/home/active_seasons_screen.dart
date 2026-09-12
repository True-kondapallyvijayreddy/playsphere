import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart';
import '../../shared/ui_kit.dart';
import 'open_registrations.dart';

/// One of the four lists behind the home screen's tiles.
///
/// ## Why the home screen sends you here rather than listing them
///
/// The dashboard's job is to say what is going on in one screen, and a club
/// running a fifteen-category sports week would own the whole of it. So the
/// home section is four counted tiles — [ActiveSeasonsSection] — and the rows
/// live here, where there is room for all of them and no other section is
/// paying for the space.
///
/// Split by [OpenRegistrationKind] and [RegistrationLens] because the tiles
/// are. Somebody who pressed "Registered tournaments" asked a narrower
/// question than "what is going on"; answering it with seasons they could
/// still enter is answering a question they did not ask.
///
/// It holds no rules of its own. Same provider, same rows, same newest-first
/// order as the count on the tile that opened it — so the number pressed and
/// the number of rows that arrive cannot disagree.
class ActiveSeasonsScreen extends ConsumerWidget {
  const ActiveSeasonsScreen({
    super.key,
    required this.kind,
    required this.lens,
  });

  final OpenRegistrationKind kind;
  final RegistrationLens lens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(entryListProvider((kind: kind, lens: lens)));

    return AppScaffold(
      // The words on the tile that was pressed, so the screen confirms what
      // was asked for rather than renaming it.
      title: lens.labelFor(kind),
      subtitle: rows.isEmpty
          ? 'Nothing here right now'
          : '${rows.length} ${kind.noun}${rows.length == 1 ? '' : 's'} '
              '${lens.blurb}',
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 96),
        children: [
          ContentBounds(
            maxWidth: 980,
            child: rows.isEmpty
                // Reachable by someone who had the list open when the last
                // entry closed, and by anyone who kept the link. It says the
                // one true thing rather than looking broken.
                ? QuietCard(
                    icon: Icons.emoji_events_outlined,
                    title: switch (lens) {
                      RegistrationLens.open => 'Nothing open to enter',
                      RegistrationLens.registered => 'You have entered nothing',
                    },
                    message: switch (lens) {
                      RegistrationLens.open =>
                        'The ${kind.noun}s your clubs open for entry show up '
                            'here until you enter them, and on your home '
                            'screen.',
                      RegistrationLens.registered =>
                        'The ${kind.noun}s you enter show up here until they '
                            'finish.',
                    },
                  )
                : Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Ps.surface,
                      borderRadius: BorderRadius.circular(Ps.radius),
                      border: Border.all(color: Ps.border),
                    ),
                    child: Column(
                      children: [
                        for (final row in rows)
                          OpenRegistrationRow(
                            key: ValueKey(row.key),
                            row: row,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
