/// The critical notification events CLAUDE.md §6 Module A names by name:
/// event reminder, match start, result, membership request approved,
/// challenge received.
///
/// [isCritical] marks the subset Module A specifically calls out as needing
/// the WhatsApp/SMS fallback (event reminder, match start, result) — a
/// missed match-start push means a player genuinely does not show up;
/// a missed "your join request was approved" push is annoying but the
/// membership is still sitting there waiting the next time they open the
/// app. That distinction is what
/// `NotificationFallbackPolicy.shouldFallback` keys off — see
/// fallback_policy.dart for why it matters that this is a property of the
/// event TYPE and not a runtime decision.
enum NotificationType {
  eventReminder('event_reminder', isCritical: true),
  matchStart('match_start', isCritical: true),
  result('result', isCritical: true),
  membershipApproved('membership_approved', isCritical: false),
  challengeReceived('challenge_received', isCritical: false);

  const NotificationType(this.wire, {required this.isCritical});

  final String wire;
  final bool isCritical;

  static NotificationType fromWire(String? w) => NotificationType.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => NotificationType.eventReminder,
      );
}

/// Where a notification takes the user when they tap it.
///
/// Carried as a route + params pair rather than a raw URL string so the
/// receiving side can hand [route] straight to go_router
/// (`context.push(deepLink.route)`) without a parsing step, while still
/// being trivially serializable into an FCM data payload — FCM data values
/// must be flat strings, which is also why [params] is `Map<String,
/// String>` rather than arbitrary JSON.
class DeepLink {
  const DeepLink(this.route, {this.params = const {}});

  /// A go_router path, e.g. `/orgs/:orgId/competitions/:competitionId`.
  final String route;
  final Map<String, String> params;

  /// Substitutes [params] into [route]'s `:name` segments, so the receiving
  /// screen can call this directly rather than re-implementing templating.
  String resolve() {
    var resolved = route;
    for (final entry in params.entries) {
      resolved = resolved.replaceAll(':${entry.key}', entry.value);
    }
    return resolved;
  }

  Map<String, String> toDataPayload() => {
        'deepLinkRoute': route,
        for (final entry in params.entries) 'deepLinkParam_${entry.key}': entry.value,
      };

  static DeepLink? fromDataPayload(Map<String, dynamic> data) {
    final route = data['deepLinkRoute'];
    if (route is! String || route.isEmpty) return null;
    final params = <String, String>{};
    for (final entry in data.entries) {
      if (entry.key.startsWith('deepLinkParam_') && entry.value is String) {
        params[entry.key.substring('deepLinkParam_'.length)] = entry.value as String;
      }
    }
    return DeepLink(route, params: params);
  }
}

/// A single notification, in the shape used both for an outgoing FCM data
/// payload and for a message already received on-device.
///
/// Kept as a plain, Firebase-free data class (no `RemoteMessage` inside it)
/// so every piece of code that reasons about a notification — the fallback
/// policy, the UI that renders a notification list, tests — depends on
/// this instead of on `firebase_messaging`, which only
/// `notification_service.dart` needs to import at all.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.deepLink,
    this.data = const {},
    this.targetUserId,
    this.clubTopicId,
    this.competitionTopicId,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DeepLink? deepLink;

  /// Any extra key/value payload beyond the fields above (e.g. a match id
  /// for a "match start" notification), carried through unchanged.
  final Map<String, String> data;

  final String? targetUserId;
  final String? clubTopicId;
  final String? competitionTopicId;

  bool get isCritical => type.isCritical;

  /// The flat string map an FCM `data` payload requires. Notification
  /// content (title/body) travels in this same map rather than in FCM's
  /// separate `notification` block, because a data-only message is the one
  /// guaranteed to reach [NotificationService]'s foreground/background
  /// handlers on every platform — a `notification` block gets shown by the
  /// OS directly on some platforms/states without the app ever seeing it,
  /// which would make deep-link routing and fallback-ack tracking unreliable.
  Map<String, String> toDataPayload() => {
        'id': id,
        'type': type.wire,
        'title': title,
        'body': body,
        if (targetUserId != null) 'targetUserId': targetUserId!,
        if (clubTopicId != null) 'clubTopicId': clubTopicId!,
        if (competitionTopicId != null) 'competitionTopicId': competitionTopicId!,
        ...?deepLink?.toDataPayload(),
        ...data,
      };

  /// Reconstructs a notification from an FCM data payload — the inverse of
  /// [toDataPayload]. `id`/`createdAt` are passed separately because on the
  /// receiving side they usually come from the transport envelope
  /// (`RemoteMessage.messageId`/`sentTime`) rather than the payload itself.
  factory AppNotification.fromDataPayload(
    Map<String, dynamic> data, {
    required String id,
    required DateTime createdAt,
  }) {
    return AppNotification(
      id: id,
      type: NotificationType.fromWire(data['type'] as String?),
      title: (data['title'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      createdAt: createdAt,
      deepLink: DeepLink.fromDataPayload(data),
      targetUserId: data['targetUserId'] as String?,
      clubTopicId: data['clubTopicId'] as String?,
      competitionTopicId: data['competitionTopicId'] as String?,
    );
  }
}
