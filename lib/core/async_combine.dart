import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Combines several [AsyncValue]s into one without losing failures.
///
/// ## Why this exists
///
/// The pattern this replaces was `ref.watch(x).valueOrNull ?? const []`. That
/// reads as a harmless default, but it maps three distinct states onto one:
/// "still loading", "the read was rejected", and "there genuinely is nothing".
/// A Firestore `permission-denied` therefore rendered as an empty list, and the
/// organizer saw a blank table rather than a reason. That is the mechanism that
/// let a P0 challenge bug sit unnoticed — a broken feature looked merely empty.
///
/// Precedence is **error before loading before data**: if any input has failed,
/// the combination has failed, even while a sibling is still in flight. A
/// half-computed answer built from the inputs that happened to succeed is worse
/// than an honest failure, because it looks authoritative.
AsyncValue<T> combineAsync2<A, B, T>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  T Function(A a, B b) build,
) {
  final failure = _firstError([a, b]);
  if (failure != null) return failure.cast<T>();
  if (a.isLoading || b.isLoading) return const AsyncValue.loading();
  return AsyncValue.data(build(a.requireValue, b.requireValue));
}

AsyncValue<T> combineAsync3<A, B, C, T>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  AsyncValue<C> c,
  T Function(A a, B b, C c) build,
) {
  final failure = _firstError([a, b, c]);
  if (failure != null) return failure.cast<T>();
  if (a.isLoading || b.isLoading || c.isLoading) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(build(a.requireValue, b.requireValue, c.requireValue));
}

/// Flattens one [AsyncValue] per club into a single list.
///
/// The home dashboard asks the same question of every club a person belongs to
/// — what is live, what is scheduled — and there is no cross-club query to ask
/// it with: a Firestore collection-group read has to be authorized against the
/// constraints the query carries, and "the clubs this user is in" is not a
/// constraint the rules can check. So the fan-out happens on the client, and
/// this puts the answers back together.
///
/// Same precedence as [combineAsync2]: one club's read failing fails the whole
/// combination. A dashboard that quietly drops a club is one that tells a
/// player nothing is being played at the club they are standing in.
AsyncValue<List<T>> combineAsyncAll<T>(List<AsyncValue<List<T>>> values) {
  final failure = _firstError(values);
  if (failure != null) return failure.cast<List<T>>();
  if (values.any((v) => v.isLoading)) return const AsyncValue.loading();
  return AsyncValue.data([for (final v in values) ...v.requireValue]);
}

/// The result of a fan-out where one branch failing must not erase the rest.
class PartialAsync<T> {
  const PartialAsync({
    required this.items,
    required this.failures,
    required this.isLoading,
  });

  final List<T> items;

  /// One entry per club whose read was rejected. Empty on a clean fan-out.
  final List<Object> failures;

  final bool isLoading;

  bool get hasFailures => failures.isNotEmpty;

  /// Every branch failed, so there is genuinely nothing to show and the
  /// screen should say so rather than render a convincing empty state.
  bool get isTotalFailure => failures.isNotEmpty && items.isEmpty && !isLoading;
}

/// Flattens one [AsyncValue] per club, keeping whatever loaded.
///
/// ## Why this exists alongside [combineAsyncAll]
///
/// [combineAsyncAll] fails the whole combination if any single input failed,
/// on the reasoning that silently dropping a club is worse than an honest
/// error. That reasoning is right about silence and wrong about scale: the
/// home dashboard fans out over EVERY club a person belongs to, so one
/// unreadable club — a club deleted out from under a stale membership, a
/// membership mirror that has drifted — took down the live-match section for
/// all of their clubs at once. The screen showed "Could not load live
/// matches" and no match anywhere was visible, which is the reported failure.
///
/// This keeps both halves of the promise instead of trading one for the
/// other: show every match that did load, AND report that something did not.
/// The caller is expected to surface [PartialAsync.failures] — dropping a
/// club quietly is still not acceptable.
PartialAsync<T> combineAsyncTolerant<T>(List<AsyncValue<List<T>>> values) {
  final items = <T>[];
  final failures = <Object>[];
  var loading = false;

  for (final v in values) {
    if (v.hasError) {
      failures.add(v.error!);
      continue;
    }
    // `valueOrNull` rather than a loading check first: a Riverpod stream that
    // has delivered once and is refreshing carries BOTH a value and the
    // loading flag, and dropping that value would make the list flicker
    // empty on every rebuild.
    final value = v.valueOrNull;
    if (value != null) {
      items.addAll(value);
    } else if (v.isLoading) {
      loading = true;
    }
  }

  return PartialAsync(items: items, failures: failures, isLoading: loading);
}

AsyncError<Object>? _firstError(List<AsyncValue<Object?>> values) {
  for (final v in values) {
    if (v.hasError) {
      return AsyncError<Object>(v.error!, v.stackTrace ?? StackTrace.empty);
    }
  }
  return null;
}

extension _CastError on AsyncError<Object> {
  AsyncValue<T> cast<T>() => AsyncValue<T>.error(error, stackTrace);
}
