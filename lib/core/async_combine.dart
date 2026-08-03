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
