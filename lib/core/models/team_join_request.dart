import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// Somebody asking to be let onto a team, at
/// `teams/{teamId}/joinRequests/{uid}`.
///
/// ## Why a request and not a code that just lets you in
///
/// A join code cannot be what admits somebody. `firestore.rules` opens every
/// team document to any signed-in reader — a roster has to be readable for a
/// team page to render at all — so a code stored on that document is
/// knowledge anybody can obtain, and a rule of the form "you may add yourself
/// if you send the right code" would authorize the whole platform. The code
/// finds the team; the captain admits the player.
///
/// ## Why the document id is the requester's uid
///
/// One person, one outstanding request per team. Tapping "Ask to join" twice
/// overwrites rather than queueing a second row for the captain to decline
/// twice, and "have I already asked?" is a `get` rather than a query.
///
/// ## Why the name is copied onto it
///
/// The captain is by definition looking at a request from somebody outside
/// their club — that is the entire point of an independent team — so they
/// have no membership document to read the name from, and `users/{uid}` is
/// refused for a private profile or an unconsented minor. Without the copy,
/// the approval screen would show a row of account ids. The requester writes
/// their own name here, which is exactly the trust level of any other display
/// name in the product.
class TeamJoinRequest {
  const TeamJoinRequest({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.message,
    this.createdAt,
  });

  /// Also the document id.
  final String uid;

  final String displayName;
  final String? photoUrl;

  /// "I keep wicket, played for St Xavier's last season." Optional, and the
  /// thing that makes a request from a stranger answerable at all.
  final String? message;

  final DateTime? createdAt;

  factory TeamJoinRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return TeamJoinRequest(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      message: Fs.strOrNull(d['message']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
