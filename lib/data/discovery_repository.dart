import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
import '../core/models/organization.dart';
import '../core/models/player_listing.dart';
import '../domain/geo/geohash.dart';
import '../domain/gov/age_group.dart';
import 'org_repository.dart' show guard, guardStream;

/// How wide a search is. A newcomer to a city usually means "this city";
/// somebody in a village means "anywhere I can reasonably travel".
enum SearchRadius {
  near(10, 'Within 10 km'),
  city(25, 'Within 25 km'),
  wide(50, 'Within 50 km'),
  region(150, 'Within 150 km');

  const SearchRadius(this.km, this.label);

  final double km;
  final String label;
}

/// Everything a discovery search can be narrowed by.
///
/// One object rather than a pile of named parameters because the screen holds
/// it as state, the provider keys off it, and both halves of the screen
/// (clubs and people) read the same fields — a person who has typed
/// "Warangal" and picked cricket should not have to type it again when they
/// switch tab.
class DiscoveryFilters {
  const DiscoveryFilters({
    this.sportId,
    this.district,
    this.ageGroup,
    this.gender,
    this.intent,
    this.query = '',
    this.radius = SearchRadius.city,
    this.lat,
    this.lng,
    this.useMyLocation = false,
  });

  static const none = DiscoveryFilters();

  final String? sportId;

  /// Free text, matched case-insensitively against the district a club or a
  /// listing published. Free text rather than a picker because there is no
  /// district reference list in the product yet, and inventing one that only
  /// covers Telangana would quietly make the rest of the country unfindable.
  final String? district;

  /// Players only — a club has no age.
  final AgeGroup? ageGroup;

  final Gender? gender;

  /// Players only. "Show me people looking for a club."
  final PlayerIntent? intent;

  /// Matched against names, so somebody can find the club they were told
  /// about by name rather than by browsing.
  final String query;

  final SearchRadius radius;

  /// Where "near me" is. Set together, or not at all.
  final double? lat;
  final double? lng;

  /// Whether [lat]/[lng] should actually drive the search. Held apart from
  /// the coordinates so turning the radius search off does not throw away a
  /// fix the person waited on GPS for.
  final bool useMyLocation;

  bool get hasPoint => lat != null && lng != null;
  bool get isRadiusSearch => useMyLocation && hasPoint;

  DiscoveryFilters copyWith({
    String? sportId,
    String? district,
    AgeGroup? ageGroup,
    Gender? gender,
    PlayerIntent? intent,
    String? query,
    SearchRadius? radius,
    double? lat,
    double? lng,
    bool? useMyLocation,
    bool clearSport = false,
    bool clearDistrict = false,
    bool clearAgeGroup = false,
    bool clearGender = false,
    bool clearIntent = false,
  }) =>
      DiscoveryFilters(
        sportId: clearSport ? null : (sportId ?? this.sportId),
        district: clearDistrict ? null : (district ?? this.district),
        ageGroup: clearAgeGroup ? null : (ageGroup ?? this.ageGroup),
        gender: clearGender ? null : (gender ?? this.gender),
        intent: clearIntent ? null : (intent ?? this.intent),
        query: query ?? this.query,
        radius: radius ?? this.radius,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        useMyLocation: useMyLocation ?? this.useMyLocation,
      );

  @override
  bool operator ==(Object other) =>
      other is DiscoveryFilters &&
      other.sportId == sportId &&
      other.district == district &&
      other.ageGroup == ageGroup &&
      other.gender == gender &&
      other.intent == intent &&
      other.query == query &&
      other.radius == radius &&
      other.lat == lat &&
      other.lng == lng &&
      other.useMyLocation == useMyLocation;

  @override
  int get hashCode => Object.hash(sportId, district, ageGroup, gender, intent,
      query, radius, lat, lng, useMyLocation);

  /// The half of these filters that Firestore is actually asked about.
  ///
  /// Splitting the object in two is not tidiness — it is what stops a search
  /// box from being a network request per keystroke. `query`, `ageGroup`,
  /// `gender` and `intent` are all decided in memory over a result set that
  /// is already in hand, so a screen that keys its fetch on this record
  /// refetches when somebody taps a district or a sport and not when they
  /// type a letter.
  DiscoveryQuery get serverQuery => DiscoveryQuery(
        sportId: sportId,
        district: district?.trim(),
        radius: radius,
        lat: useMyLocation ? lat : null,
        lng: useMyLocation ? lng : null,
      );
}

/// What actually reaches Firestore. See [DiscoveryFilters.serverQuery].
class DiscoveryQuery {
  const DiscoveryQuery({
    this.sportId,
    this.district,
    this.radius = SearchRadius.city,
    this.lat,
    this.lng,
  });

  final String? sportId;
  final String? district;
  final SearchRadius radius;

  /// Non-null only when the searcher asked for a radius search AND has a
  /// point — the two are folded together here so nothing downstream has to
  /// check both.
  final double? lat;
  final double? lng;

  bool get isRadiusSearch => lat != null && lng != null;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryQuery &&
      other.sportId == sportId &&
      other.district == district &&
      other.radius == radius &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(sportId, district, radius, lat, lng);
}

/// Finding clubs and people you have no connection to yet.
///
/// ## The one job nothing else in the product does
///
/// Every other route into a club runs through somebody who is already in it:
/// an invite code read out in a WhatsApp group, a QR on a noticeboard, a
/// coach who adds you. That is the right primary path and it stays the
/// primary path — but it is useless to the person this repository is for.
/// Somebody who has just moved city, or just arrived in the country, or has
/// simply never belonged to a club, knows nobody to get a code from. Without
/// a search they can only sit on an empty home screen, which is where a large
/// share of new accounts stop.
///
/// ## Why the club search filters on the client
///
/// Clubs are already world-readable when `visibility == 'public'`, and the
/// filters people actually use (district text, name text, sport) are a
/// substring match, a substring match and a derivation — none of which
/// Firestore can index. Fetching a bounded page of public clubs and filtering
/// it here is honest about that, and at the size this platform is today it is
/// also faster than the alternative. [maxClubsScanned] is the ceiling, and
/// the screen says so when it is hit rather than pretending the list is
/// exhaustive.
///
/// The people search is the opposite: `playerDirectory` is a purpose-built
/// collection with the exact fields a filter needs, so district and sport go
/// to the server and only the text match stays here.
class DiscoveryRepository {
  const DiscoveryRepository();

  /// How many public clubs one search reads before it stops. Deliberately not
  /// unbounded: this is a browse, and a browse that pages through ten
  /// thousand documents on a phone is a bill, not a feature.
  static const maxClubsScanned = 300;

  /// How many directory listings one search reads.
  static const maxListingsScanned = 200;

  /// Every public club, as one bounded page.
  ///
  /// Deliberately takes no filters. Nothing a person types or taps on the
  /// discovery screen can be expressed as a Firestore constraint — a district
  /// and a name are substring matches, and "runs cricket" is derived from the
  /// competitions a club is putting on rather than stored on it. So the query
  /// is constant, the listener is opened once, and [filterClubs] does the
  /// work. Keying the stream on the filters instead would tear down and
  /// rebuild a snapshot listener on every keystroke.
  Stream<List<Organization>> watchPublicClubs({int limit = maxClubsScanned}) {
    return guardStream(() => Refs.orgs
        .where('visibility', isEqualTo: OrgVisibility.public.wire)
        .limit(limit)
        .snapshots()
        .map((snap) => [
              for (final doc in snap.docs)
                if (!Organization.fromDoc(doc).isDeleted)
                  Organization.fromDoc(doc),
            ]));
  }

  /// Narrows [clubs] to what the screen is asking for. Pure, so the screen can
  /// re-run it as fast as somebody can type.
  ///
  /// [sportOrgIds] is the set of clubs known to actually run the chosen sport,
  /// supplied by the caller because it is derived from competitions rather
  /// than stored on the club — see `sportClubsProvider`, which this
  /// deliberately reuses rather than re-deriving. Null means no sport filter.
  List<Organization> filterClubs(
    List<Organization> clubs,
    DiscoveryFilters filters, {
    Set<String>? sportOrgIds,
  }) {
    final district = _norm(filters.district);
    final query = _norm(filters.query);

    final hits = <Organization>[];
    for (final org in clubs) {
      if (sportOrgIds != null && !sportOrgIds.contains(org.id)) continue;
      if (district != null && !_placeMatches(org, district)) continue;
      if (query != null && !(_norm(org.name) ?? '').contains(query)) continue;
      hits.add(org);
    }

    // Biggest first inside the filtered set. A newcomer with no other signal
    // is better served by the club that has people in it than by whichever
    // document Firestore happened to return first.
    hits.sort((a, b) => b.memberCount.compareTo(a.memberCount));
    return hits;
  }

  /// Whether a club sits in the place somebody typed.
  ///
  /// Checks the nested hierarchy and the legacy flat `district`/`city`,
  /// because clubs created before `GeoLocation` existed have their location
  /// only in the flat fields — see that class's `fromDocData`. Missing both
  /// means the club is excluded from a place search rather than included in
  /// every one: a club that never said where it is is not evidence that it is
  /// here.
  bool _placeMatches(Organization org, String needle) {
    for (final part in [
      org.geo.district,
      org.geo.state,
      org.geo.mandal,
      org.geo.village,
      org.district,
      org.city,
    ]) {
      final p = _norm(part);
      if (p != null && p.contains(needle)) return true;
    }
    return false;
  }

  /// Fetches directory listings for [query].
  ///
  /// Two shapes, picked by whether the caller supplied a point:
  ///
  ///  * **Radius** — the geohash trick `GroundRepository.searchNearby` already
  ///    uses: cover the circle with nine cells, run a prefix range query per
  ///    cell, then let [rankPlayers] filter by true great-circle distance.
  ///    Only listings whose owner published a point can be found this way,
  ///    which is exactly the consent boundary intended.
  ///  * **District** — an equality filter, which is what somebody who typed a
  ///    place name rather than tapping "near me" asked for.
  ///
  /// Sport goes to the server in the district shape and stays in memory in the
  /// radius shape: a range query has already spent the one inequality
  /// Firestore allows.
  Future<List<PlayerListing>> fetchPlayers(DiscoveryQuery query) =>
      guard(() async {
        if (query.isRadiusSearch) return _byRadius(query);
        return _byDistrict(query);
      });

  /// Applies the in-memory half of [filters] to already-fetched [listings],
  /// attaches a distance where there is one, and orders the result.
  ///
  /// Pure and cheap on purpose — this is what runs on every keystroke.
  List<PlayerNearby> rankPlayers(
    List<PlayerListing> listings,
    DiscoveryFilters filters,
  ) {
    final radius = filters.isRadiusSearch;

    final hits = <PlayerNearby>[];
    for (final l in listings) {
      if (!_playerMatches(l, filters)) continue;
      double? distance;
      if (radius) {
        if (!l.hasPoint) continue;
        distance = Geohash.distanceKm(
          filters.lat!,
          filters.lng!,
          l.geo.lat!,
          l.geo.lng!,
        );
        if (distance > filters.radius.km) continue;
      }
      hits.add(PlayerNearby(listing: l, distanceKm: distance));
    }

    hits.sort((a, b) {
      final da = a.distanceKm;
      final db = b.distanceKm;
      if (da != null && db != null) return da.compareTo(db);
      // No distance to sort on: the most complete listing first, which in
      // practice is the person who has actually played.
      return b.listing.matchesPlayed.compareTo(a.listing.matchesPlayed);
    });
    return hits;
  }

  Future<List<PlayerListing>> _byRadius(DiscoveryQuery q) async {
    final precision = Geohash.precisionForRadiusKm(q.radius.km);
    final cells = Geohash.neighborsOf(q.lat!, q.lng!, precision);

    final snapshots = await Future.wait(cells.map((cell) {
      final (start, end) = Geohash.queryBoundsFor(cell);
      return Refs.playerDirectory
          .where('geohash', isGreaterThanOrEqualTo: start)
          .where('geohash', isLessThan: end)
          .limit(maxListingsScanned)
          .get();
    }));

    final byId = <String, PlayerListing>{};
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        byId[doc.id] = PlayerListing.fromDoc(doc);
      }
    }
    return byId.values.toList();
  }

  Future<List<PlayerListing>> _byDistrict(DiscoveryQuery q) async {
    Query<Map<String, dynamic>> fsQuery = Refs.playerDirectory;

    // Exact match, not a substring: this one goes to the server, and a server
    // cannot do `contains`. It is why the listing editor stores the district
    // as typed and the search seeds its box from the searcher's own profile
    // rather than leaving them to guess the spelling.
    final district = q.district;
    if (district != null && district.isNotEmpty) {
      fsQuery = fsQuery.where('district', isEqualTo: district);
    }
    if (q.sportId != null) {
      fsQuery = fsQuery.where('sportIds', arrayContains: q.sportId);
    }

    final snap = await fsQuery.limit(maxListingsScanned).get();
    return [for (final doc in snap.docs) PlayerListing.fromDoc(doc)];
  }

  bool _playerMatches(PlayerListing l, DiscoveryFilters f) {
    if (f.sportId != null && !l.sportIds.contains(f.sportId)) return false;
    if (f.ageGroup != null && l.ageGroup != f.ageGroup) return false;
    if (f.gender != null && l.gender != f.gender) return false;
    if (f.intent != null && !l.intents.contains(f.intent)) return false;
    final query = _norm(f.query);
    if (query != null) {
      final name = _norm(l.displayName) ?? '';
      final code = _norm(l.playerCode) ?? '';
      if (!name.contains(query) && !code.contains(query)) return false;
    }
    // A district typed for a radius search still narrows the result, so the
    // two filters compose instead of one silently winning.
    final district = _norm(f.district);
    if (f.isRadiusSearch && district != null) {
      final theirs = _norm(l.geo.district);
      if (theirs == null || !theirs.contains(district)) return false;
    }
    return true;
  }

  // --- The listing somebody publishes about themselves -------------------

  Stream<PlayerListing?> watchMyListing(String uid) => guardStream(
        () => Refs.playerListing(uid).snapshots().map(
              (doc) => doc.exists ? PlayerListing.fromDoc(doc) : null,
            ),
      );

  Future<PlayerListing?> fetchListing(String uid) => guard(() async {
        final doc = await Refs.playerListing(uid).get();
        return doc.exists ? PlayerListing.fromDoc(doc) : null;
      });

  /// Publishes or replaces a listing. Whole-document, see [PlayerListing.toMap].
  Future<void> saveListing(PlayerListing listing) => guard(
        () => Refs.playerListing(listing.uid).set(listing.toMap()),
      );

  /// Takes somebody out of the directory entirely.
  ///
  /// A delete rather than a hidden flag. "Remove me from search" has to mean
  /// the document is gone, or the next feature that reads the collection
  /// without knowing about the flag puts them back in.
  Future<void> removeListing(String uid) =>
      guard(() => Refs.playerListing(uid).delete());

  /// Lower-cased and trimmed, or null when there was nothing to match on.
  static String? _norm(String? raw) {
    final s = raw?.trim().toLowerCase();
    return s == null || s.isEmpty ? null : s;
  }
}
