/// Where a match is being broadcast, and what the app can safely do with it.
///
/// ## Why the link is parsed rather than embedded as given
///
/// A club's organizer pastes whatever their phone gave them: a
/// `youtu.be/xxxx` share link, a `youtube.com/watch?v=xxxx&t=91s` address bar,
/// a `/live/xxxx` link from the Create dashboard, sometimes a Facebook or an
/// Instagram URL. Handing any of that to an `<iframe>` gets a blank rectangle
/// — YouTube refuses to frame its watch page — and handing an arbitrary
/// pasted string to a frame is how a scoreboard becomes somebody else's
/// advertising slot.
///
/// So a link is reduced to a [StreamLink] first: a KNOWN platform and an id
/// this file extracted itself. An embed is built from the id, never from the
/// text that was pasted. Anything unrecognised stays a link — offered as
/// "open in the browser", never framed.
///
/// Pure, and deliberately in `domain/` rather than beside the widget: this is
/// the part with edge cases worth testing (`test/stream_link_test.dart`), and
/// the part that must behave identically on a phone and on the web.
enum StreamPlatform {
  /// The only platform that gets an inline player. YouTube publishes a
  /// documented embed endpoint that allows framing; nothing else here does.
  youtube,

  /// A recognised address on a platform with no frameable player. Shown with
  /// its name and opened outside the app.
  other,
}

class StreamLink {
  const StreamLink({
    required this.platform,
    required this.url,
    this.videoId,
    this.label = 'Live stream',
  });

  final StreamPlatform platform;

  /// The link as it will actually be opened — always the original, so a
  /// viewer who chooses to leave the app lands where the organizer pointed.
  final String url;

  /// The YouTube video id, when one could be extracted. Null for everything
  /// else, and the single condition for an inline player existing at all.
  final String? videoId;

  /// What to call it on a button: "YouTube", "Facebook", the host name.
  final String label;

  /// Whether this can be shown inside the app rather than opened outside it.
  bool get isEmbeddable => videoId != null;

  /// The frameable player URL.
  ///
  /// `youtube-nocookie.com` rather than `youtube.com`: the viewer of a school
  /// match did not ask to be tracked across the web for watching it, and the
  /// privacy-enhanced host is the same player with the same reliability.
  /// `playsinline` keeps an iPhone from taking over the whole screen the
  /// moment the video starts, which on a page that also carries a scoreboard
  /// is the wrong default.
  String? get embedUrl => videoId == null
      ? null
      : 'https://www.youtube-nocookie.com/embed/$videoId'
          '?rel=0&playsinline=1&modestbranding=1';

  /// The poster frame, for the platforms that cannot be framed inline.
  ///
  /// `hqdefault` rather than `maxresdefault`: every video has one, including
  /// a live stream that started four minutes ago, whereas `maxresdefault`
  /// 404s for a large share of them and would show a broken image exactly
  /// when the match is most worth watching.
  String? get thumbnailUrl => videoId == null
      ? null
      : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  /// Reads a pasted link.
  ///
  /// Returns null for anything that is not an http(s) URL at all, which is
  /// what an organizer typing "on the club's facebook page" produces and what
  /// the editor refuses to save.
  static StreamLink? parse(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;

    final id = _youTubeIdOf(uri);
    if (id != null) {
      return StreamLink(
        platform: StreamPlatform.youtube,
        url: text,
        videoId: id,
        label: 'YouTube',
      );
    }

    return StreamLink(
      platform: StreamPlatform.other,
      url: text,
      label: _nameOfHost(uri.host),
    );
  }

  /// The eleven characters YouTube calls a video id, from any of the five
  /// shapes a person can end up pasting.
  ///
  /// The id is validated rather than merely extracted. Everything downstream
  /// interpolates it into a URL, and an id taken on trust is the one place
  /// this feature could be talked into loading something nobody chose.
  static String? _youTubeIdOf(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // youtu.be/<id>
    if (host == 'youtu.be') {
      return segments.isEmpty ? null : _validId(segments.first);
    }

    if (host != 'youtube.com' &&
        host != 'm.youtube.com' &&
        host != 'music.youtube.com' &&
        host != 'youtube-nocookie.com') {
      return null;
    }

    // youtube.com/watch?v=<id>
    final v = uri.queryParameters['v'];
    if (v != null) {
      final id = _validId(v);
      if (id != null) return id;
    }

    // youtube.com/live/<id>, /embed/<id>, /shorts/<id>, /v/<id>
    if (segments.length >= 2 &&
        const {'live', 'embed', 'shorts', 'v'}.contains(segments.first)) {
      return _validId(segments[1]);
    }

    return null;
  }

  /// A YouTube id is exactly eleven characters of `A-Za-z0-9_-`. Anything
  /// else is not an id, whatever it was doing in the URL.
  static String? _validId(String candidate) {
    final id = candidate.split('?').first.split('&').first.trim();
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
  }

  /// "Facebook", "Instagram", or the bare host for anything else. A button
  /// that says "Open on Facebook" tells the viewer where they are about to
  /// go; one that says "Open link" does not.
  static String _nameOfHost(String host) {
    final bare = host.toLowerCase().replaceFirst('www.', '');
    return switch (bare) {
      'facebook.com' || 'fb.watch' || 'm.facebook.com' => 'Facebook',
      'instagram.com' => 'Instagram',
      'twitch.tv' => 'Twitch',
      'x.com' || 'twitter.com' => 'X',
      _ => bare,
    };
  }
}
