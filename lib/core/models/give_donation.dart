import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// One equipment line inside a donation or a need — "3 pairs of shoes",
/// "1 cricket kit". The same shape serves both directions ([GiveDonation]
/// and `GiveNeed`) so a donation and a shortfall can be compared item for
/// item without a translation layer.
class GiveItemLine {
  const GiveItemLine({
    required this.category,
    required this.quantity,
    this.note,
  });

  final EquipmentCategory category;

  /// Always > 0. A line with nothing in it is not a line — it is omitted.
  final int quantity;

  /// Free text — "size 8, lightly used", "3 need re-lacing". Never parsed,
  /// only ever shown to a human at inspection time.
  final String? note;

  factory GiveItemLine.fromMap(Map<String, dynamic> m) => GiveItemLine(
        category: EquipmentCategory.fromWire(m['category'] as String?),
        quantity: Fs.integer(m['quantity'], 1),
        note: Fs.strOrNull(m['note']),
      );

  Map<String, Object?> toMap() => Fs.prune({
        'category': category.wire,
        'quantity': quantity,
        'note': note,
      });

  static List<GiveItemLine> listFromRaw(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => GiveItemLine.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  static List<Map<String, Object?>> listToRaw(List<GiveItemLine> lines) =>
      lines.map((l) => l.toMap()).toList(growable: false);
}

/// One recorded step of a donation's journey — see [DonationStatus] for the
/// pipeline it walks. Kept as an append-only list on the document itself
/// rather than a subcollection: a donation's whole history is a handful of
/// entries, always read together, and never queried on its own — exactly the
/// case where a subcollection would cost an extra round trip for nothing.
class GiveStatusEvent {
  const GiveStatusEvent({required this.status, required this.at});

  final DonationStatus status;
  final DateTime? at;

  factory GiveStatusEvent.fromMap(Map<String, dynamic> m) => GiveStatusEvent(
        status: DonationStatus.fromWire(m['status'] as String?),
        at: Fs.dateOrNull(m['at']),
      );

  /// Firestore refuses `FieldValue.serverTimestamp()` inside an array
  /// element (it silently rejects the whole write), unlike a top-level
  /// field — so unlike [GiveDonation.createdAt], this one is stamped with
  /// the client clock. That is an acceptable few seconds of skew for a
  /// progress tracker nobody queries by time; it is never used for
  /// ordering across donations.
  Map<String, Object?> toMap() => {
        'status': status.wire,
        'at': Fs.ts(at ?? DateTime.now()),
      };

  static List<GiveStatusEvent> listFromRaw(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => GiveStatusEvent.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }
}

/// A donor's contribution, at `giveDonations/{donationId}`.
///
/// ## The client only ever writes [DonationStatus.submitted]
///
/// Every stage after that — collected, inspected, cleaned, repaired,
/// safety-checked, graded, packed, assigned, distributed, or rejected — is
/// set by collection-center staff through the console or a future staff
/// app, never by the donor's own client. That is not a UX shortcut, it is
/// the safety property the whole pipeline exists for: if a donor's device
/// could mark its own donation "safety checked", the phrase would stop
/// meaning anything. See `firestore.rules` on `giveDonations`.
///
/// ## Separate from the commercial `products` catalog on purpose
///
/// A donated pair of shoes and a listing bought from Decathlon must never
/// share a collection — donors, recipients and accountants all need to be
/// able to ask "show me only the give network" and get a real answer.
class GiveDonation {
  const GiveDonation({
    required this.id,
    required this.donorUid,
    this.donorName,
    this.donorPhone,
    this.type = GiveDonationType.equipment,
    this.items = const [],
    this.city = '',
    this.collectionCenterId,
    this.amountPaise = 0,
    this.status = DonationStatus.submitted,
    this.history = const [],
    this.assignedNeedId,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String donorUid;
  final String? donorName;
  final String? donorPhone;

  final GiveDonationType type;

  /// The equipment being given. Empty for a [GiveDonationType.money] pledge.
  final List<GiveItemLine> items;

  /// Free-text city, matched against [GiveCollectionCenter.cityKey] the same
  /// way `Ground.cityKey` matches `city` — see that model for why this is a
  /// flat string and not the full [GeoLocation] hierarchy: a donor typing
  /// into a form types a city, not a mandal.
  final String city;

  final String? collectionCenterId;

  /// Indicative only, same caveat as `ShopProduct.pricePaise` — the money
  /// side of Give is a pledge, not a charge. PlaySphere's payment gateway is
  /// explicitly deferred product-wide, so this never represents money that
  /// has actually moved; a
  /// [GiveDonationType.money] row is a lead for the team to follow up on by
  /// phone, not a transaction.
  final int amountPaise;

  final DonationStatus status;
  final List<GiveStatusEvent> history;

  /// Set once staff match this donation against a `GiveNeed`. Null means
  /// still sitting in the general pool.
  final String? assignedNeedId;

  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get cityKey => city.trim().toLowerCase();

  factory GiveDonation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GiveDonation(
      id: doc.id,
      donorUid: Fs.str(d['donorUid']),
      donorName: Fs.strOrNull(d['donorName']),
      donorPhone: Fs.strOrNull(d['donorPhone']),
      type: GiveDonationType.fromWire(d['type'] as String?),
      items: GiveItemLine.listFromRaw(d['items']),
      city: Fs.str(d['city']),
      collectionCenterId: Fs.strOrNull(d['collectionCenterId']),
      amountPaise: Fs.integer(d['amountPaise']),
      status: DonationStatus.fromWire(d['status'] as String?),
      history: GiveStatusEvent.listFromRaw(d['history']),
      assignedNeedId: Fs.strOrNull(d['assignedNeedId']),
      notes: Fs.strOrNull(d['notes']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      updatedAt: Fs.dateOrNull(d['updatedAt']),
    );
  }

  /// The only shape a client is ever allowed to write — see the class doc.
  /// Always [DonationStatus.submitted], always a one-entry [history].
  Map<String, Object?> toCreate() => Fs.prune({
        'donorUid': donorUid,
        'donorName': donorName,
        'donorPhone': donorPhone,
        'type': type.wire,
        'items': GiveItemLine.listToRaw(items),
        'city': city,
        'cityKey': cityKey,
        'collectionCenterId': collectionCenterId,
        'amountPaise': type == GiveDonationType.money ? amountPaise : 0,
        'status': DonationStatus.submitted.wire,
        'history': [
          const GiveStatusEvent(status: DonationStatus.submitted, at: null)
              .toMap(),
        ],
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
