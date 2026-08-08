import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/notifications/notification_model.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/notification_repository.dart';
import 'package:playsphere/features/notifications/notifications_screen.dart';

/// Covers Bug #21: "Notifications" was action-items only, gated on
/// organizer capabilities a plain member never has — so for anyone who was
/// not running their club, the screen was permanently empty regardless of
/// how much was happening there. `myNotificationFeedProvider` is what fills
/// it for that person.
void main() {
  AppNotification fixture({bool read = false}) => AppNotification(
        id: 'n1',
        type: NotificationType.result,
        title: 'Blue House won by 12 runs',
        body: 'Nizampet High School · Semi-final',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        deepLink: const DeepLink('/org/org_school/event/comp1/watch/fx1'),
        read: read,
      );

  Widget harness({required List<AppNotification> feed}) {
    final marked = <String>[];
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/org/:orgId/event/:compId/watch/:fixtureId',
          builder: (_, state) => Scaffold(
            body: Center(child: Text('AT ${state.uri.path}')),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('uid_me'),
        myMembershipsProvider.overrideWith((ref) => Stream.value(const [])),
        myScoringAssignmentsProvider.overrideWith((ref) => Stream.value(const [])),
        myNotificationFeedProvider.overrideWith((ref) => Stream.value(feed)),
        notificationRepositoryProvider.overrideWithValue(
          _RecordingNotificationRepository(marked),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('a member with no organizer role still sees club activity',
      (tester) async {
    await tester.pumpWidget(harness(feed: [fixture()]));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nothing here yet'), findsNothing);
    expect(find.text('Blue House won by 12 runs'), findsOneWidget);
    expect(find.text('Club activity'), findsOneWidget);
  });

  testWidgets('with nothing waiting and no activity, says so once',
      (tester) async {
    await tester.pumpWidget(harness(feed: const []));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('tapping an unread item marks it read and opens its scorecard',
      (tester) async {
    await tester.pumpWidget(harness(feed: [fixture()]));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Blue House won by 12 runs'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('AT /org/org_school/event/comp1/watch/fx1'),
      findsOneWidget,
    );
  });
}

class _RecordingNotificationRepository implements NotificationRepository {
  _RecordingNotificationRepository(this.marked);

  final List<String> marked;

  @override
  Future<void> markRead(String uid, String id) async {
    marked.add(id);
  }

  @override
  Future<void> markAllRead(String uid, List<String> unreadIds) async {
    marked.addAll(unreadIds);
  }

  @override
  Stream<List<AppNotification>> watchFeed(String uid, {int limit = 50}) =>
      Stream.value(const []);
}
