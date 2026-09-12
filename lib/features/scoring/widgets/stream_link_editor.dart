import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../core/providers.dart';
import '../../../domain/scoring/stream_link.dart';
import '../../../shared/app_scaffold.dart';

/// Where an organizer puts the link to the broadcast.
///
/// ## Why it validates before it saves
///
/// The value of this field is that a spectator taps once and sees a picture.
/// A link that cannot be resolved to a player produces the opposite — a box
/// that never loads, on the one screen where a viewer has the least patience
/// — and the person who pasted it has already walked away to the boundary.
/// So the parse happens here, in front of the person who can fix it, and the
/// sheet says what it made of what they typed before they commit to it.
///
/// It refuses nothing that is a real address, though. A Facebook or an
/// Instagram live link saves happily and shows as a link rather than a
/// player; only something that is not a URL at all is rejected, because that
/// is the one case where nothing downstream can do anything useful with it.
Future<void> showStreamLinkEditor(
  BuildContext context,
  WidgetRef ref,
  Fixture fixture,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _StreamLinkEditor(fixture: fixture),
    ),
  );
}

class _StreamLinkEditor extends ConsumerStatefulWidget {
  const _StreamLinkEditor({required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<_StreamLinkEditor> createState() => _StreamLinkEditorState();
}

class _StreamLinkEditorState extends ConsumerState<_StreamLinkEditor> {
  late final _controller =
      TextEditingController(text: widget.fixture.streamUrl ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({required bool clear}) async {
    setState(() => _busy = true);
    try {
      await ref.read(competitionRepositoryProvider).setStreamUrl(
            orgId: widget.fixture.orgId,
            compId: widget.fixture.compId,
            fixtureId: widget.fixture.id,
            url: clear ? null : _controller.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _controller.text.trim();
    final link = StreamLink.parse(typed);
    final hasExisting = (widget.fixture.streamUrl ?? '').trim().isNotEmpty;
    // A blank box is not an error — it is what "remove the link" looks like
    // on the way to the Remove button.
    final isBroken = typed.isNotEmpty && link == null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Live stream link', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'A YouTube link plays inside the match page. Anything else is '
              'offered as a link the viewer can open.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Paste the link',
                hintText: 'https://youtube.com/live/…',
                border: const OutlineInputBorder(),
                errorText: isBroken
                    ? 'That is not a web address. Paste the whole link, '
                        'starting with https://'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (link != null) _Verdict(link: link),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy || link == null ? null : () => _save(clear: false),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save the link'),
            ),
            if (hasExisting) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _save(clear: true),
                child: const Text('Remove the stream'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the app made of what was typed, before it is saved.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.link});

  final StreamLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = link.isEmbeddable;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          good ? Icons.play_circle_outline : Icons.link,
          size: 18,
          color: good ? theme.colorScheme.primary : theme.hintColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            good
                ? 'Recognised as ${link.label}. It will play inside the match '
                    'page on the web, and open in the ${link.label} app on a '
                    'phone.'
                : 'Recognised as ${link.label}. It cannot be played inside '
                    'the app, so viewers will get a button that opens it.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
