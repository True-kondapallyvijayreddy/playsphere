import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../domain/memory_tagging.dart';
import '../../../core/models/memory.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';
import 'memory_grid.dart';

/// The memories attached to one match, with the control that creates them.
///
/// Lives on both the scoring pad and the spectator view. That is deliberate:
/// the person holding the scorebook and the parent on the boundary are usually
/// different people, and either may be the one with the good photo.
///
/// Tagging is what connects a match photo to a career. An untagged upload is
/// still a club memory but will never appear on anyone's profile.
///
/// The sheet therefore pre-selects EVERYONE who was at the match — both
/// line-ups and the officials — rather than starting empty. Starting empty
/// made the common case the laborious one: the photo is almost always of the
/// people who were there, and an uploader on a ground was not going to tap
/// twenty-two chips, so in practice memories were being saved with nobody
/// tagged and never reached a single profile. Untagging the two people who
/// happen not to be in frame is the rarer, cheaper action, so that is the one
/// that costs taps.
class MatchMemoriesSection extends ConsumerWidget {
  const MatchMemoriesSection({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = FixtureRef(fixture.orgId, fixture.compId, fixture.id);
    final memoriesAsync = ref.watch(fixtureMemoriesProvider(key));
    final myUid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    final memories = memoriesAsync.valueOrNull ?? const <Memory>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Memories', style: theme.textTheme.titleMedium),
                  Text(
                    memories.isEmpty
                        ? 'Add a photo and it stays on every player’s profile.'
                        : '${memories.length} from this match',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (myUid != null)
              FilledButton.tonalIcon(
                onPressed: () => _addMemory(context, ref, myUid),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AsyncErrorStrip(value: memoriesAsync, what: 'memories'),
        MemoryGrid(
          memories: memories,
          loading: memoriesAsync.isLoading,
          emptyMessage: 'Nothing yet from this match.',
          onDelete: myUid == null
              ? null
              : (memory) async {
                  try {
                    await ref.read(memoryRepositoryProvider).delete(memory);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
        ),
      ],
    );
  }

  Future<void> _addMemory(
    BuildContext context,
    WidgetRef ref,
    String myUid,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final composed =
        await ref.read(memoryComposerProvider).pickPhoto(source: source);
    if (composed == null || !context.mounted) return;

    final result = await showDialog<_MemoryDetails>(
      context: context,
      builder: (_) => _MemoryDetailsDialog(fixture: fixture),
    );
    if (result == null || !context.mounted) return;

    // Shown while the upload runs so a slow rural connection reads as progress
    // rather than a dead button.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Uploading…'),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      // Decides whether this memory is listable on a public career profile or
      // only to the club. Read from the club document rather than assumed,
      // because the rules re-derive the same value and reject a mismatch.
      final org = ref.read(organizationProvider(fixture.orgId)).valueOrNull;

      await ref.read(memoryRepositoryProvider).upload(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
            uploaderUid: myUid,
            orgIsPublic: org?.visibility == OrgVisibility.public,
            tournamentId: fixture.tournamentId,
            bytes: composed.bytes,
            contentType: composed.contentType,
            kind: composed.kind,
            caption: result.caption,
            taggedUids: result.taggedUids,
            width: composed.width == 0 ? null : composed.width,
            height: composed.height == 0 ? null : composed.height,
          );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Memory saved.')));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) showError(context, e);
    }
  }
}

class _MemoryDetails {
  const _MemoryDetails({this.caption, this.taggedUids = const []});
  final String? caption;
  final List<String> taggedUids;
}

/// Caption plus who is in the photo, drawn from the match line-ups and the
/// officials.
///
/// Everyone present is offered AND pre-selected. Only people with a real uid
/// can be tagged — a guest recorded by name alone has no profile for the
/// memory to land on — and nobody outside the match is offered at all, so a
/// tag can never put a stranger's face on someone's career profile.
class _MemoryDetailsDialog extends StatefulWidget {
  const _MemoryDetailsDialog({required this.fixture});
  final Fixture fixture;

  @override
  State<_MemoryDetailsDialog> createState() => _MemoryDetailsDialogState();
}

class _MemoryDetailsDialogState extends State<_MemoryDetailsDialog> {
  final _caption = TextEditingController();

  late final List<TaggablePerson> _people =
      MemoryTagging.participantsOf(widget.fixture);

  /// Starts as everyone at the match — see [MemoryTagging.defaultTagsFor].
  late final Set<String> _tagged =
      MemoryTagging.defaultTagsFor(widget.fixture);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = _people;

    return AlertDialog(
      title: const Text('Add a memory'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _caption,
                maxLength: 140,
                decoration: const InputDecoration(
                  labelText: 'Caption (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (players.isEmpty)
                Text(
                  'No line-ups or officials were recorded for this match, so '
                  'nobody can be tagged. The photo will still be saved to the '
                  'match.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Who is in it?',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    // An escape hatch for the photo of one player. Without it
                    // the pre-selected default would be worse than the empty
                    // one it replaced for that case.
                    TextButton(
                      onPressed: () => setState(() {
                        if (_tagged.isEmpty) {
                          _tagged.addAll(
                            _people.take(MemoryTagging.maxTags).map((p) => p.uid),
                          );
                        } else {
                          _tagged.clear();
                        }
                      }),
                      child: Text(_tagged.isEmpty ? 'Select all' : 'Clear'),
                    ),
                  ],
                ),
                Text(
                  'Everyone who was at this match is tagged, umpires '
                  'included. They each get this on their profile for good — '
                  'untap anyone who is not in the photo.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in players)
                      FilterChip(
                        label: Text(p.label),
                        selected: _tagged.contains(p.uid),
                        onSelected: (on) => setState(() {
                          if (on) {
                            if (_tagged.length < MemoryTagging.maxTags) _tagged.add(p.uid);
                          } else {
                            _tagged.remove(p.uid);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _MemoryDetails(
              caption:
                  _caption.text.trim().isEmpty ? null : _caption.text.trim(),
              taggedUids: _tagged.toList(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
