import 'package:flutter/material.dart';

import '../../../core/models/memory.dart';
import '../../../shared/identity.dart';

/// A square-tiled grid of memories, with a tap-to-open full-screen viewer.
///
/// Square tiles rather than the photos' true aspect ratios: a grid of mixed
/// portrait and landscape match photos reflows on every image load and looks
/// broken on a phone. The full ratio is preserved in the viewer, which is where
/// anyone actually looks at the picture.
class MemoryGrid extends StatelessWidget {
  const MemoryGrid({
    super.key,
    required this.memories,
    this.loading = false,
    this.emptyMessage = 'No memories yet.',
    this.onDelete,
  });

  final List<Memory> memories;
  final bool loading;
  final String emptyMessage;

  /// When provided, the viewer offers a delete action. Omitted for profiles
  /// the caller does not own.
  final Future<void> Function(Memory memory)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading && memories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (memories.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('No memories yet'),
          subtitle: Text(emptyMessage),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tile count follows available width rather than a device breakpoint, so
        // the same grid works in a phone column and a laptop two-pane.
        final columns = (constraints.maxWidth / 160).floor().clamp(3, 6);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: memories.length,
          itemBuilder: (context, i) {
            final memory = memories[i];
            return _Tile(
              memory: memory,
              onTap: () => _openViewer(context, i),
            );
          },
        );
      },
    );
  }

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MemoryViewer(
          memories: memories,
          initialIndex: initialIndex,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.memory, required this.onTap});

  final Memory memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: memory.caption?.isNotEmpty == true
          ? 'Memory: ${memory.caption}'
          : memory.isVideo
              ? 'Match video'
              : 'Match photo',
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: memory.isVideo
                  ? Center(
                      child: Icon(Icons.play_circle_outline,
                          size: 32, color: scheme.onSurfaceVariant),
                    )
                  : PsNetworkImage(
                      url: memory.url,
                      fit: BoxFit.cover,
                      // A memory that fails to load must not render as a blank
                      // square indistinguishable from a slow one.
                      fallback: Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 24, color: scheme.onSurfaceVariant),
                      ),
                    ),
            ),
            if (memory.isVideo)
              const Positioned(
                right: 4,
                bottom: 4,
                child: Icon(Icons.videocam, size: 14, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen, swipeable viewer.
class _MemoryViewer extends StatefulWidget {
  const _MemoryViewer({
    required this.memories,
    required this.initialIndex,
    this.onDelete,
  });

  final List<Memory> memories;
  final int initialIndex;
  final Future<void> Function(Memory memory)? onDelete;

  @override
  State<_MemoryViewer> createState() => _MemoryViewerState();
}

class _MemoryViewerState extends State<_MemoryViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final memory = widget.memories[_index];
    final onDelete = widget.onDelete;
    if (onDelete == null) return;

    // A deletion dialog rather than an immediate delete: a memory is the one
    // thing in this app that cannot be recomputed from the event log.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this memory?'),
        content: const Text(
          'It will disappear from every profile and match it appears on. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    await onDelete(memory);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memories[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} of ${widget.memories.length}'),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: widget.memories.length,
              itemBuilder: (context, i) {
                final m = widget.memories[i];
                if (m.isVideo) {
                  // Playback needs a video plugin, which is deliberately not a
                  // dependency yet. Saying so is better than an unexplained
                  // black rectangle.
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Video playback is coming soon. The clip is saved.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }
                return InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: PsNetworkImage(
                      url: m.url,
                      fit: BoxFit.contain,
                      fallback: const Center(
                        child: Text(
                          'This photo could not be loaded.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (memory.caption?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                memory.caption!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
