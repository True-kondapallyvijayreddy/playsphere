import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/medical/sports_medicine_library.dart';
import '../../shared/ui_kit.dart';

/// The button that hands somebody off to YouTube.
///
/// One widget rather than a `launchUrl` call at each of the three places
/// these appear, so the two things that must always happen — naming the
/// source, and saying out loud that the tap leaves PlaySphere — cannot be
/// forgotten on one screen and present on the other two.
///
/// It opens in the external application rather than an in-app view. Watching
/// a rehab demonstration is a several-minute job that people pause, scrub and
/// come back to, and a webview wrapper turns that into a worse YouTube with
/// no history and no picture-in-picture.
class VideoLinkButton extends StatelessWidget {
  const VideoLinkButton({
    super.key,
    required this.video,
    this.expanded = true,
  });

  final VideoReference video;

  /// False in the tight row inside an injury card, where the button sits
  /// beside text rather than filling the width.
  final bool expanded;

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(
      video.url,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open YouTube')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.play_circle_outline, size: 18),
      label: Text(
        expanded ? 'Watch on YouTube' : 'Watch',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!expanded) return button;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        const SizedBox(height: 6),
        // The source, every time. It is what tells somebody whether the video
        // they are about to watch is FIFA's own or a stranger's, and it is
        // the part of a video reference that cannot rot.
        Text(
          '${video.title} · ${video.source}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            height: 1.35,
            color: Ps.faint,
          ),
        ),
      ],
    );
  }
}
