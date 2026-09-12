import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_refs.dart';
import 'notification_model.dart';

/// The device half of push notifications.
///
/// ## What this does and does not do
///
/// It registers this device so the server can reach it, and it turns an
/// arriving message back into an [AppNotification] the app can route on. It
/// does **not** send anything — a client cannot, and should not be able to,
/// push to other people's phones. Sending lives in Cloud Functions
/// (`functions/index.js`), triggered by the Firestore writes that represent
/// the events worth interrupting somebody for.
///
/// ## Why tokens are stored per device, not per user
///
/// A player has a phone and a college lab machine, and a scorer may borrow a
/// club tablet on match day. A single `fcmToken` field on the user would mean
/// the last device to open the app is the only one that ever hears anything —
/// which, for "your match starts in an hour", is the difference between
/// turning up and not. Each token is its own document under the user, so a
/// stale one can be dropped without disturbing the others.
class NotificationService {
  NotificationService({FirebaseMessaging? messaging})
      : _injected = messaging;

  final FirebaseMessaging? _injected;

  /// Resolved on first use, never at construction.
  ///
  /// `FirebaseMessaging.instance` throws if Firebase has not been initialised,
  /// and this service is built by a provider that the app shell watches — so
  /// touching it in the constructor took down every widget test that renders a
  /// screen, and would equally take down the app on any path that built the
  /// shell before `Firebase.initializeApp` completed. Nothing here needs the
  /// plugin until somebody actually signs in.
  FirebaseMessaging get _messaging => _injected ?? FirebaseMessaging.instance;

  final _incoming = StreamController<AppNotification>.broadcast();
  StreamSubscription<RemoteMessage>? _onMessage;
  StreamSubscription<RemoteMessage>? _onOpened;
  StreamSubscription<String>? _onTokenRefresh;

  /// Notifications that arrived while the app was in the foreground, plus the
  /// one that opened the app if it was launched from a notification.
  ///
  /// A broadcast stream rather than a callback so more than one surface can
  /// listen — the router, to deep-link; a badge, to count.
  Stream<AppNotification> get incoming => _incoming.stream;

  /// Asks for permission and registers this device against every uid in
  /// [uids].
  ///
  /// Usually one: the signed-in account. It is several on a phone that also
  /// carries managed child profiles — a child with no device of their own has
  /// this phone as their only device, so their match reminders have to reach
  /// it, and `sendToUsers` in functions/index.js delivers to
  /// `users/{uid}/devices`. Registering the same token under each of them is
  /// what makes a household's notifications arrive at all.
  ///
  /// Safe to call on every sign-in and every app start: token registration is
  /// keyed by the token itself, so re-registering the same device rewrites one
  /// document per uid rather than accumulating rows.
  ///
  /// Deliberately swallows its own failures. A player who declines
  /// notifications, or a build without the platform plumbing wired up, must
  /// still get a working app — losing pushes is a degradation, not a reason to
  /// fail a sign-in.
  Future<void> register(List<String> uids) async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // Nothing more to do. Not an error: the person said no.
        return;
      }

      final token = await _messaging.getToken();
      if (token != null) {
        for (final uid in uids) {
          await _storeToken(uid, token);
        }
      }

      // A token can be rotated by the OS at any time. Without this the device
      // silently stops receiving anything, which is the worst failure mode
      // here because nothing appears to be wrong.
      await _onTokenRefresh?.cancel();
      _onTokenRefresh = _messaging.onTokenRefresh.listen(
        (fresh) async {
          for (final uid in uids) {
            await _storeToken(uid, fresh);
          }
        },
        onError: (Object e) =>
            debugPrint('[PlaySphere] token refresh failed: $e'),
      );

      await _listen();
    } catch (error) {
      debugPrint('[PlaySphere] notification registration failed: $error');
    }
  }

  Future<void> _listen() async {
    await _onMessage?.cancel();
    _onMessage = FirebaseMessaging.onMessage.listen(_emit);

    await _onOpened?.cancel();
    _onOpened = FirebaseMessaging.onMessageOpenedApp.listen(_emit);

    // The app was launched from a notification while terminated. Without this
    // the tap is swallowed and the person lands on the home screen wondering
    // what they just opened.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _emit(initial);
  }

  void _emit(RemoteMessage message) {
    if (_incoming.isClosed) return;
    _incoming.add(
      AppNotification.fromDataPayload(
        message.data,
        id: message.messageId ?? DateTime.now().toIso8601String(),
        createdAt: message.sentTime ?? DateTime.now(),
      ),
    );
  }

  Future<void> _storeToken(String uid, String token) async {
    await Refs.deviceToken(uid, token).set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Drops this device's registration on sign-out.
  ///
  /// Without it a shared phone keeps delivering one person's match reminders
  /// to the next person who signs in on it.
  Future<void> unregister(List<String> uids) async {
    // Nothing was ever registered — most obviously in a widget test, or for
    // someone who declined permission — so there is nothing to tear down and
    // no reason to reach for the plugin.
    if (_onMessage == null && _onTokenRefresh == null) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        for (final uid in uids) {
          await Refs.deviceToken(uid, token).delete();
        }
      }
      await _messaging.deleteToken();
    } catch (error) {
      debugPrint('[PlaySphere] notification unregister failed: $error');
    } finally {
      await _onTokenRefresh?.cancel();
      await _onMessage?.cancel();
      await _onOpened?.cancel();
      _onTokenRefresh = null;
      _onMessage = null;
      _onOpened = null;
    }
  }

  void dispose() {
    _onTokenRefresh?.cancel();
    _onMessage?.cancel();
    _onOpened?.cancel();
    _incoming.close();
  }
}
