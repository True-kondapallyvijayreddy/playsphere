import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/fixture.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../domain/scoring/stream_link.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';
import '../../../shared/web/inline_frame.dart';
import 'stream_link_editor.dart';

/// The video, above the scoreboard, when a match is being broadcast.
///
/// ## Why it is a link to YouTube and not a stream of our own
///
/// Streaming is not a feature this product should build. A grassroots match
/// that gets broadcast at all is broadcast by a volunteer with a phone on a
/// tripod behind the bowler's arm, going out on the club's own YouTube or
/// Facebook page — where the club already has followers, already has a
/// channel, and already knows how to go live. Rebuilding that would mean
/// ingest, transcoding and bandwidth for a platform whose entire cost model
/// is "one document listener per spectator".
///
/// So PlaySphere carries the LINK and puts the picture and the score on one
/// page, which is the part nobody else does: a parent following their child's
/// school match gets the video and the ball-by-ball in the same place instead
/// of a YouTube tab and an app.
///
/// ## What "watch it here" actually means on each platform
///
/// **Web** — genuinely inline. A real `<iframe>` on YouTube's documented
/// embed endpoint, through `InlineFrame`, which is where most remote viewers
/// are anyway: a shared match link opens the web build, signed out.
///
/// **Android and iOS** — the poster frame, a play button, and a hand-off to
/// the YouTube app. Not a compromise dressed up as a feature: Flutter has no
/// built-in web view, the project carries no web-view package (see
/// `InlineFrame`'s stub for what adding one would cost), and the phone
/// already has a better player than anything that could be embedded. The
/// panel is honest about it — the button says where it is about to send you.
///
/// **Anything that is not YouTube** — a link, never a frame. See `StreamLink`.
///
/// ## When there is no link
///
/// Nothing, for a spectator. An empty video box on a match nobody is filming
/// is a broken feature rather than a placeholder. The people who CAN do
/// something about it — the scorer, the club's organizers — get a quiet
/// prompt instead, which is how the link gets set in the first place.
class LiveStreamPanel extends ConsumerWidget {
  const LiveStreamPanel({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = StreamLink.parse(fixture.streamUrl);
    final canEdit = ref
        .watch(myCapabilitiesProvider(fixture.orgId))
        .contains(Capability.manageCompetitions);

    // Nothing at all, not an empty box with a gap above it. The callers that
    // lay this out do not add spacing around it for exactly that reason —
    // the panel carries its own, so a spectator on a match nobody is filming
    // sees the scoreboard where the scoreboard has always been.
    if (link == null) {
      if (!canEdit) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _AddStreamPrompt(fixture: fixture),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Player(link: link),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.videocam_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Live on ${link.label}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _open(context, link.url),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text('Open on ${link.label}'),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Change the stream link',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          showStreamLinkEditor(context, ref, fixture),
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

Future<void> _open(BuildContext context, String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// The 16:9 rectangle: a real frame on the web, a poster and a play button
/// everywhere else.
class _Player extends StatelessWidget {
  const _Player({required this.link});

  final StreamLink link;

  @override
  Widget build(BuildContext context) {
    final embed = link.embedUrl;
    final frame = embed == null
        ? null
        : InlineFrame.build(embed, title: 'Live match stream');

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: frame ?? _Poster(link: link),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.link});

  final StreamLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Black behind the poster, not the surface colour: a 16:9 thumbnail is
    // 4:3 letterboxed inside it, and grey bars either side of a video read as
    // a layout mistake where black bars read as a video.
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: PsNetworkImage(
            url: link.thumbnailUrl,
            fit: BoxFit.cover,
            fallback: const ColoredBox(color: Colors.black),
          ),
        ),
        // A scrim under the button, so a play control stays visible over a
        // bright daytime pitch.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
        Center(
          child: FilledButton.icon(
            onPressed: () => _open(context, link.url),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Watch on ${link.label}'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// What an organizer sees on a match with no link yet.
///
/// Deliberately a quiet strip and not an empty video frame. It is an offer to
/// the two or three people who can act on it, on a screen whose subject is
/// the score; a dashed 16:9 box saying "no stream" would take a third of the
/// first screen to say nothing.
class _AddStreamPrompt extends ConsumerWidget {
  const _AddStreamPrompt({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(
          Icons.videocam_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Streaming this match?'),
        subtitle: const Text(
          'Paste the YouTube link and it plays right here, above the score.',
        ),
        trailing: const Icon(Icons.add_link),
        onTap: () => showStreamLinkEditor(context, ref, fixture),
      ),
    );
  }
}
