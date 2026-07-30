import 'dart:async';

import '../core/firebase/firestore_refs.dart';
import '../core/models/firestore_codec.dart';
import '../domain/career/career_stats.dart';
import '../domain/rating/glicko2.dart';

/// One sport's line on a career profile: what you played and how you rate.
///
/// Ratings and career stats live in two sibling subcollections written by the
/// same finalize batch, and every screen wants them together. Joining them here
/// rather than in the widget keeps the profile from having to reason about a
/// sport that has a rating but no stats (rated a walkover) or stats but no
/// rating (a performance sport that Glicko does not apply to).
class CareerLine {
  const CareerLine({
    required this.sportId,
    required this.stats,
    required this.rating,
  });

  final String sportId;
  final CareerStats? stats;
  final Rating? rating;

  int get matchesPlayed => stats?.matchesPlayed ?? 0;

  /// Sorting key for "what is this player best known for".
  ///
  /// Matches played, not rating: a strong rating off two games says less about
  /// someone than a long record does, and Glicko already tells us that through
  /// [Rating.isProvisional].
  int get prominence => matchesPlayed;
}

/// Reads the lifelong profile.
///
/// ## Note on what was already here
///
/// `users/{uid}/ratings/{sportId}` and `users/{uid}/career_stats/{sportId}`
/// have been written on every match finalize since ratings shipped. Nothing had
/// ever read them: there was no decoder for career stats and no screen for
/// either. So this class is not new plumbing for new data — it is the first
/// reader of data the app has been accumulating all along.
class CareerRepository {
  const CareerRepository();

  /// Every sport this player has a record in, most-played first.
  Stream<List<CareerLine>> watchCareer(String uid) {
    final stats = Refs.userCareerStats(uid).snapshots();
    final ratings = Refs.userRatings(uid).snapshots();

    // Two listeners combined by hand rather than with a stream-zip package:
    // zip would wait for both to tick, and a player with ratings but no stats
    // yet would show nothing until the second collection happened to change.
    return _combineLatest(stats, ratings, (statsSnap, ratingsSnap) {
      final byId = <String, CareerStats>{
        for (final d in statsSnap.docs)
          d.id: CareerStats.fromMap(
            d.data(),
            d.id,
            uid: uid,
            lastPlayedAt: Fs.dateOrNull(d.data()['lastPlayedAt']),
          ),
      };
      final ratingById = <String, Rating>{
        for (final d in ratingsSnap.docs) d.id: Rating.fromMap(d.data()),
      };

      // Chess is rated per time control (`chess:blitz`), so a rating id is not
      // always a sport id. Union the keys so neither source is dropped.
      final sportIds = <String>{...byId.keys, ...ratingById.keys};

      final lines = [
        for (final id in sportIds)
          CareerLine(
            sportId: id,
            stats: byId[id],
            rating: ratingById[id],
          ),
      ]..sort((a, b) {
          final byProminence = b.prominence.compareTo(a.prominence);
          return byProminence != 0
              ? byProminence
              : a.sportId.compareTo(b.sportId);
        });
      return lines;
    });
  }

  Future<CareerStats?> statsFor(String uid, String sportId) async {
    final snap = await Refs.userCareerStat(uid, sportId).get();
    if (!snap.exists) return null;
    return CareerStats.fromMap(
      snap.data(),
      sportId,
      uid: uid,
      lastPlayedAt: Fs.dateOrNull(snap.data()?['lastPlayedAt']),
    );
  }
}

/// Emits whenever either source emits, once both have produced a value.
Stream<R> _combineLatest<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;

  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;

  void emit() {
    if (hasA && hasB) controller.add(combine(latestA as A, latestB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (v) {
          latestA = v;
          hasA = true;
          emit();
        },
        onError: controller.addError,
      );
      subB = b.listen(
        (v) {
          latestB = v;
          hasB = true;
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );

  return controller.stream;
}
