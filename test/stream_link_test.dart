import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/scoring/stream_link.dart';

/// The link an organizer pastes is the one thing in the live-stream feature
/// that arrives as free text from outside, so it is the one part worth
/// testing exhaustively. Everything downstream interpolates the extracted id
/// into a URL.
void main() {
  group('StreamLink.parse — YouTube shapes people actually paste', () {
    const id = 'dQw4w9WgXcQ';

    test('the share sheet gives a youtu.be link', () {
      final link = StreamLink.parse('https://youtu.be/$id');
      expect(link!.videoId, id);
      expect(link.platform, StreamPlatform.youtube);
      expect(link.isEmbeddable, isTrue);
    });

    test('the address bar gives a watch URL', () {
      expect(StreamLink.parse('https://www.youtube.com/watch?v=$id')?.videoId,
          id);
    });

    test('a timestamped watch URL keeps only the id', () {
      expect(
        StreamLink.parse('https://www.youtube.com/watch?v=$id&t=91s')?.videoId,
        id,
      );
    });

    test('the Create dashboard gives a /live/ link', () {
      expect(StreamLink.parse('https://youtube.com/live/$id')?.videoId, id);
    });

    test('an embed or shorts link resolves too', () {
      expect(StreamLink.parse('https://www.youtube.com/embed/$id')?.videoId, id);
      expect(StreamLink.parse('https://youtube.com/shorts/$id')?.videoId, id);
    });

    test('m.youtube.com — the link a phone copies', () {
      expect(
        StreamLink.parse('https://m.youtube.com/watch?v=$id')?.videoId,
        id,
      );
    });

    test('surrounding whitespace from a paste is tolerated', () {
      expect(StreamLink.parse('  https://youtu.be/$id  ')?.videoId, id);
    });
  });

  group('StreamLink.parse — what must NOT become an embed', () {
    test('a channel page is not a video', () {
      final link = StreamLink.parse('https://www.youtube.com/@someclub');
      expect(link, isNotNull);
      expect(link!.videoId, isNull);
      expect(link.isEmbeddable, isFalse);
    });

    test('a YouTube URL whose v= is not an id is refused as an id', () {
      // Eleven characters is the whole definition. Anything else in the slot
      // is not an id, whatever it was doing in the URL.
      expect(
        StreamLink.parse('https://youtube.com/watch?v=notanid')?.videoId,
        isNull,
      );
      expect(
        StreamLink.parse('https://youtube.com/watch?v=waytoolongforanid')
            ?.videoId,
        isNull,
      );
    });

    test('a lookalike host does not get a player', () {
      final link = StreamLink.parse('https://youtube.com.evil.test/watch?v=x');
      expect(link!.videoId, isNull);
      expect(link.isEmbeddable, isFalse);
    });

    test('a javascript: URL is not a link at all', () {
      expect(StreamLink.parse('javascript:alert(1)'), isNull);
    });

    test('a sentence is not a link', () {
      expect(StreamLink.parse("on the club's facebook page"), isNull);
      expect(StreamLink.parse(''), isNull);
      expect(StreamLink.parse(null), isNull);
    });
  });

  group('StreamLink — other platforms are links, never frames', () {
    test('Facebook is recognised and named, but not embeddable', () {
      final link = StreamLink.parse('https://www.facebook.com/club/videos/12');
      expect(link!.platform, StreamPlatform.other);
      expect(link.label, 'Facebook');
      expect(link.isEmbeddable, isFalse);
      expect(link.embedUrl, isNull);
      expect(link.thumbnailUrl, isNull);
    });

    test('an unknown host falls back to its own name', () {
      expect(
        StreamLink.parse('https://stream.someschool.edu/match')?.label,
        'stream.someschool.edu',
      );
    });
  });

  group('StreamLink — the URLs built from an id', () {
    const id = 'dQw4w9WgXcQ';
    final link = StreamLink.parse('https://youtu.be/$id')!;

    test('the player is the privacy-enhanced host', () {
      expect(link.embedUrl, startsWith('https://www.youtube-nocookie.com/embed/$id'));
    });

    test('the player does not autoplay', () {
      // A scoreboard page that starts making noise on its own gets closed.
      expect(link.embedUrl, isNot(contains('autoplay=1')));
    });

    test('the poster is hqdefault, which every video has', () {
      expect(link.thumbnailUrl, 'https://i.ytimg.com/vi/$id/hqdefault.jpg');
    });

    test('the original link is what a viewer leaving the app follows', () {
      expect(link.url, 'https://youtu.be/$id');
    });
  });
}
