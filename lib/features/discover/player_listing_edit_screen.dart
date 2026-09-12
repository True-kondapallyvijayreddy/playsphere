import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/geo.dart';
import '../../core/models/player_listing.dart';
import '../../core/providers.dart';
import '../../data/career_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/location_fields.dart';

/// "Let people find me" — the opt-in half of discovery.
///
/// ## Why this is a screen and not a switch
///
/// Being findable is a decision with contents. What sport, what you are
/// looking for, how precisely you are willing to be placed and what you want
/// to say are all part of it, and a single toggle would have to guess all
/// four from a profile that was never written to be published. So this asks,
/// and publishes only what it was told.
///
/// ## Why it is adults only
///
/// `firestore.rules` reads the author's date of birth and refuses the write
/// for a minor. That is deliberate and not a placeholder: a searchable,
/// location-bearing directory of children is not something this product will
/// ship, and the route that already exists for a junior who genuinely needs
/// to be discoverable is the per-scout guardian consent record, which is
/// granted to one named person at a time rather than to everybody.
///
/// A junior who has just moved is not left with nothing — the club half of
/// discovery is open to everyone and needs no listing at all. This screen
/// says exactly that rather than failing at save time.
class PlayerListingEditScreen extends ConsumerStatefulWidget {
  const PlayerListingEditScreen({super.key});

  @override
  ConsumerState<PlayerListingEditScreen> createState() =>
      _PlayerListingEditScreenState();
}

class _PlayerListingEditScreenState
    extends ConsumerState<PlayerListingEditScreen> {
  final _note = TextEditingController();
  final _sportIds = <String>{};
  final _intents = <PlayerIntent>{};
  GeoLocation _geo = GeoLocation.empty;
  bool _seeded = false;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Seeds the form once: from the existing listing if there is one, and
  /// otherwise from the profile and career record, so somebody publishing for
  /// the first time is presented with a filled-in draft rather than a blank
  /// form. Everything seeded stays editable — the sport somebody wants to be
  /// found for in a new city is often not the sport their record is in.
  void _seed(AppUser me, PlayerListing? existing, List<String> careerSports) {
    if (_seeded) return;
    _seeded = true;
    if (existing != null) {
      _sportIds.addAll(existing.sportIds);
      _intents.addAll(existing.intents);
      _note.text = existing.note ?? '';
      // The stored listing carries district and state only; the point comes
      // back with it so somebody editing does not have to re-fetch GPS.
      _geo = existing.geo;
    } else {
      _sportIds.addAll(careerSports);
      _intents.add(PlayerIntent.club);
      _geo = me.geo;
    }
  }

  Future<void> _save(AppUser me, List<String> careerSports, int matches) async {
    if (_sportIds.isEmpty) {
      showError(
        context,
        const ValidationException('Pick at least one sport.'),
      );
      return;
    }
    if (_geo.district == null || _geo.district!.trim().isEmpty) {
      showError(
        context,
        const ValidationException(
          'Add a district or city — it is what "near me" searches match on.',
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(discoveryRepositoryProvider).saveListing(
            PlayerListing.refreshedFor(
              me,
              sportIds: _sportIds.toList(),
              intents: _intents.toList(),
              geo: _geo,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
              matchesPlayed: matches,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are listed. People nearby can find you now.')),
      );
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Take yourself off the directory?'),
        content: const Text(
          'Your listing is deleted. Your profile, clubs and results are '
          'untouched — this only stops you appearing in searches.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove me'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(discoveryRepositoryProvider).removeListing(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are no longer listed.')),
      );
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The ACCOUNT, not the profile in use. A guardian browsing as their child
    // must not be able to publish the child — and the rules would refuse it
    // anyway, so asking the wrong question here would only produce a confusing
    // permission error at save time.
    final meAsync = ref.watch(authUserProvider);
    final existing = ref.watch(myPlayerListingProvider).valueOrNull;

    return AppScaffold(
      title: 'Let people find you',
      body: AsyncView(
        value: meAsync,
        builder: (me) {
          if (me == null) return const SizedBox.shrink();

          if (me.isMinor) {
            return const EmptyState(
              icon: Icons.shield_outlined,
              title: 'The directory is for adults',
              message:
                  'Under 18, your profile stays closed to strangers and you '
                  'are not listed in search. That protection is not something '
                  'the app lets you switch off.\n\nYou can still find and join '
                  'clubs — the Clubs tab needs no listing.',
            );
          }

          // Seeds the sport chips and supplies the one number a card shows.
          // Read with `valueOrNull` rather than awaited: somebody listing
          // themselves for the first time has no career to wait for, and a
          // spinner over an empty record helps nobody.
          final career = ref.watch(careerProvider(me.uid)).valueOrNull ??
              const <CareerLine>[];
          final careerSports = [for (final line in career) line.sportId];
          final matches =
              career.fold(0, (total, line) => total + line.matchesPlayed);
          _seed(me, existing, careerSports);

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'What people will see',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your name, photo, player code, age group, district and '
                      'the sports below — nothing else. Your phone number, '
                      'email and exact address are never published here.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    const SizedBox(height: 24),

                    Text('Sports', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in SportCatalog.all)
                          FilterChip(
                            label: Text(s.name),
                            selected: _sportIds.contains(s.id),
                            onSelected: (on) => setState(() {
                              if (on) {
                                _sportIds.add(s.id);
                              } else {
                                _sportIds.remove(s.id);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'What are you looking for?',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final i in PlayerIntent.values)
                          FilterChip(
                            label: Text(i.label),
                            selected: _intents.contains(i),
                            onSelected: (on) => setState(() {
                              if (on) {
                                _intents.add(i);
                              } else {
                                _intents.remove(i);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Where you are',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    LocationFields(
                      value: _geo,
                      // The directory publishes the coarse half only, so it
                      // does not offer a field it will refuse to store.
                      showVillage: false,
                      pointHelper: 'Lets people search by real distance. Your '
                          'card only ever shows the district.',
                      onChanged: (g) => setState(() => _geo = g),
                    ),
                    const SizedBox(height: 24),

                    TextField(
                      controller: _note,
                      maxLines: 3,
                      maxLength: PlayerListing.maxNoteLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'A line about yourself (optional)',
                        hintText: 'Left-arm spinner, just moved from '
                            'Hyderabad, free on weekends.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _save(me, careerSports, matches),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(
                        _busy
                            ? 'Saving…'
                            : existing == null
                                ? 'List me'
                                : 'Save changes',
                      ),
                    ),
                    if (existing != null) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy ? null : () => _remove(me.uid),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Take me off the directory'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
