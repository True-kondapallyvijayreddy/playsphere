import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';
import 'give_donation.dart';

/// A verified equipment shortfall a donor can act on directly, at
/// `giveNeeds/{needId}` — "12 pairs of cricket shoes for a village club in
/// Nalgonda", not a generic appeal.
///
/// ## Why "verified" is a real field and not just a label
///
/// The whole pitch of Give over a generic donation drive is specificity: a
/// donor sees an actual roster shortfall, not "we need equipment, trust us".
/// That only holds if a need can't be faked. [verified] is set by staff
/// (console/Cloud Function), never by the client that created the need —
/// see `firestore.rules` on `giveNeeds`. An org admin can raise a need at
/// any time; whether it is *shown* as a trustworthy ask is a separate,
/// staff-gated step.
class GiveNeed {
  const GiveNeed({
    required this.id,
    required this.beneficiaryType,
    this.orgId,
    this.orgName,
    this.playerUid,
    this.playerName,
    required this.title,
    this.description,
    this.city = '',
    this.playersCount,
    this.items = const [],
    this.fulfilled = const [],
    this.status = GiveNeedStatus.open,
    this.verified = false,
    this.createdByUid,
    this.createdAt,
  });

  final String id;
  final GiveBeneficiaryType beneficiaryType;

  /// Set when [beneficiaryType] is [GiveBeneficiaryType.team] or
  /// [GiveBeneficiaryType.club]. [orgName] is denormalized at creation so
  /// the needs board can render without a join per card.
  final String? orgId;
  final String? orgName;

  /// Set when [beneficiaryType] is [GiveBeneficiaryType.player]. Deliberately
  /// just a uid + display name, never the player's contact details or exact
  /// address — a donor connects through PlaySphere, not directly, same
  /// privacy boundary as the rest of the profile system.
  final String? playerUid;
  final String? playerName;

  final String title;
  final String? description;
  final String city;

  /// How many players this need covers, for a team/club need — "20 players,
  /// 12 need shoes" reads very differently from an unscoped "shoes needed".
  final int? playersCount;

  /// What is still short. Quantities here are the *remaining* shortfall —
  /// see [fulfilled] for what has already been matched, so a partially-met
  /// need shows correctly instead of asking a second donor to over-give.
  final List<GiveItemLine> items;

  /// What donations have already been assigned against this need, same
  /// shape as [items]. `items[i].quantity` is always the outstanding count,
  /// not the original ask — staff reduce it as donations are assigned
  /// rather than the UI subtracting live, so the board is correct even
  /// offline.
  final List<GiveItemLine> fulfilled;

  final GiveNeedStatus status;
  final bool verified;
  final String? createdByUid;
  final DateTime? createdAt;

  String get cityKey => city.trim().toLowerCase();

  factory GiveNeed.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GiveNeed(
      id: doc.id,
      beneficiaryType: GiveBeneficiaryType.fromWire(
        d['beneficiaryType'] as String?,
      ),
      orgId: Fs.strOrNull(d['orgId']),
      orgName: Fs.strOrNull(d['orgName']),
      playerUid: Fs.strOrNull(d['playerUid']),
      playerName: Fs.strOrNull(d['playerName']),
      title: Fs.str(d['title'], 'Equipment needed'),
      description: Fs.strOrNull(d['description']),
      city: Fs.str(d['city']),
      playersCount: Fs.intOrNull(d['playersCount']),
      items: GiveItemLine.listFromRaw(d['items']),
      fulfilled: GiveItemLine.listFromRaw(d['fulfilled']),
      status: GiveNeedStatus.fromWire(d['status'] as String?),
      verified: Fs.boolean(d['verified']),
      createdByUid: Fs.strOrNull(d['createdByUid']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  /// The only shape a client is ever allowed to create — always unverified
  /// and always [GiveNeedStatus.open]. See the class doc.
  Map<String, Object?> toCreate({required String createdByUid}) => Fs.prune({
        'beneficiaryType': beneficiaryType.wire,
        'orgId': orgId,
        'orgName': orgName,
        'playerUid': playerUid,
        'playerName': playerName,
        'title': title,
        'description': description,
        'city': city,
        'cityKey': cityKey,
        'playersCount': playersCount,
        'items': GiveItemLine.listToRaw(items),
        'fulfilled': const <Map<String, Object?>>[],
        'status': GiveNeedStatus.open.wire,
        'verified': false,
        'createdByUid': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
