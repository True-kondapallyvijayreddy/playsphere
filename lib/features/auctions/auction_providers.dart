import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/auction.dart';
import '../../core/providers.dart';
import '../../data/auction_repository.dart';

/// Providers for the auction space.
///
/// Feature-local rather than in `core/providers.dart`, following
/// `club_network_providers.dart`: nothing outside this feature reads an
/// auction, and the root provider file is already the largest in the project.

final auctionRepositoryProvider = Provider((ref) => const AuctionRepository());

/// Every auction this person is in, whatever their role.
///
/// Keyed on the CURRENT profile rather than the signed-in account, so a
/// guardian who has switched into a child's profile sees the child's
/// auctions. Same rule the rest of the product follows — see
/// `currentUidProvider`.
final myAuctionsProvider =
    StreamProvider<List<AuctionParticipant>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(auctionRepositoryProvider).watchMyAuctions(uid);
});

/// The public board. Null sport means every sport.
final publicAuctionsProvider =
    StreamProvider.family<List<Auction>, String?>((ref, sportId) {
  return ref
      .watch(auctionRepositoryProvider)
      .watchPublicAuctions(sportId: sportId);
});

final auctionProvider =
    StreamProvider.family<Auction?, String>((ref, auctionId) {
  return ref.watch(auctionRepositoryProvider).watchAuction(auctionId);
});

final auctionParticipantsProvider =
    StreamProvider.family<List<AuctionParticipant>, String>((ref, auctionId) {
  return ref.watch(auctionRepositoryProvider).watchParticipants(auctionId);
});

/// The caller's own standing in one auction, or null if they are not in it.
///
/// The single source for "may I see a bid box", "may I approve people", "is
/// my application still pending" — every screen in the feature branches on
/// this rather than re-deriving it.
final myAuctionPlaceProvider =
    StreamProvider.family<AuctionParticipant?, String>((ref, auctionId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(auctionRepositoryProvider).watchMyPlace(auctionId, uid);
});

final auctionTeamsProvider =
    StreamProvider.family<List<AuctionTeam>, String>((ref, auctionId) {
  return ref.watch(auctionRepositoryProvider).watchTeams(auctionId);
});

final auctionTeamProvider = StreamProvider.family<AuctionTeam?,
    ({String auctionId, String teamId})>((ref, key) {
  return ref
      .watch(auctionRepositoryProvider)
      .watchTeam(key.auctionId, key.teamId);
});

/// The caller's own side, if they have one. Also the id every bid is written
/// under, since a team's id IS its owner's uid.
final myAuctionTeamProvider =
    StreamProvider.family<AuctionTeam?, String>((ref, auctionId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(auctionRepositoryProvider).watchTeam(auctionId, uid);
});

final auctionLotsProvider =
    StreamProvider.family<List<AuctionLot>, String>((ref, auctionId) {
  return ref.watch(auctionRepositoryProvider).watchLots(auctionId);
});

final auctionLotProvider = StreamProvider.family<AuctionLot?,
    ({String auctionId, String lotId})>((ref, key) {
  return ref.watch(auctionRepositoryProvider).watchLot(key.auctionId, key.lotId);
});

final auctionSquadProvider = StreamProvider.family<List<AuctionLot>,
    ({String auctionId, String teamId})>((ref, key) {
  return ref
      .watch(auctionRepositoryProvider)
      .watchSquad(key.auctionId, key.teamId);
});

/// Every bid on one lot.
///
/// Returns exactly one document before the reveal — the caller's own, because
/// that is all the rules hand over — and all of them afterwards. The widget
/// does not branch on which; the list is simply longer once the lots are
/// open. See `AuctionBid` for why the losing bids become public at all.
final auctionLotBidsProvider = StreamProvider.family<List<AuctionBid>,
    ({String auctionId, String lotId})>((ref, key) {
  return ref
      .watch(auctionRepositoryProvider)
      .watchLotBids(key.auctionId, key.lotId);
});

/// The caller's own bids across the whole auction, keyed by lot id so the
/// pool list can show "you bid ₹40,000" on a row without a listener per row.
final myAuctionBidsProvider =
    StreamProvider.family<Map<String, AuctionBid>, String>((ref, auctionId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const {});
  return ref
      .watch(auctionRepositoryProvider)
      .watchMyBids(auctionId, uid)
      .map((bids) => {for (final b in bids) b.lotId: b});
});

final auctionTradesProvider =
    StreamProvider.family<List<AuctionTrade>, String>((ref, auctionId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(auctionRepositoryProvider).watchMyTrades(auctionId, uid);
});

/// Offers waiting on this person specifically — the badge on the Trades tile.
/// A proposal the caller SENT is not waiting on them, so it does not count.
final pendingAuctionTradeCountProvider =
    Provider.family<int, String>((ref, auctionId) {
  final uid = ref.watch(currentUidProvider);
  final trades = ref.watch(auctionTradesProvider(auctionId)).valueOrNull;
  if (uid == null || trades == null) return 0;
  return trades.where((t) => t.isPending && t.toTeamId == uid).length;
});

/// Applications the organizer has not looked at — the badge on the People
/// tile. Zero for everybody who is not running the auction.
final pendingAuctionJoinCountProvider =
    Provider.family<int, String>((ref, auctionId) {
  final me = ref.watch(myAuctionPlaceProvider(auctionId)).valueOrNull;
  if (me == null || !me.isOrganizer || !me.isApproved) return 0;
  final people = ref.watch(auctionParticipantsProvider(auctionId)).valueOrNull;
  if (people == null) return 0;
  return people
      .where((p) => p.status == AuctionJoinStatus.pending)
      .length;
});
