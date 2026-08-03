import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/club_file.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// Documents a club shares with its members.
///
/// The fixtures list a school sends round, a tournament's rules, a consent
/// form for a trial. The flow puts files inside a club next to announcements
/// and polls — without it these live in a WhatsApp group and are gone by the
/// time anyone needs them again.
class ClubFilesScreen extends ConsumerWidget {
  const ClubFilesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(clubFilesProvider(orgId));
    final files = filesAsync.valueOrNull ?? const <ClubFile>[];
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Files',
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _upload(context, ref),
              icon: const Icon(Icons.upload_file),
              label: const Text('Add a file'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ContentBounds(
            maxWidth: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsyncErrorStrip(value: filesAsync, what: 'the club files'),
                if (files.isEmpty && !filesAsync.isLoading)
                  const EmptyState(
                    icon: Icons.folder_outlined,
                    title: 'No files yet',
                    message: 'Fixtures lists, rules, consent forms — anything '
                        'the club needs to hand round.',
                  )
                else
                  for (final f in files)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(_iconFor(f.contentType)),
                        title: Text(f.name),
                        subtitle: Text(
                          [
                            f.uploaderName,
                            if (f.readableSize.isNotEmpty) f.readableSize,
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Share',
                              icon: const Icon(Icons.ios_share),
                              onPressed: () => SharePlus.instance.share(
                                ShareParams(
                                  text: '${f.name}: ${f.url}',
                                  subject: f.name,
                                ),
                              ),
                            ),
                            if (canManage)
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(context, ref, f),
                              ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String? contentType) {
    final type = contentType ?? '';
    if (type.startsWith('image/')) return Icons.image_outlined;
    if (type.contains('pdf')) return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    // `image_picker` rather than a file picker: it is already a dependency,
    // and the overwhelming majority of what a grassroots club circulates is a
    // photograph of a sheet of paper. A dedicated file picker would be a new
    // dependency for the minority case, and can be added when a club asks.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: picked.name);
        return AlertDialog(
          title: const Text('Name this file'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              helperText: 'What the club will see in the list',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await ref.read(clubFileRepositoryProvider).upload(
            orgId: orgId,
            name: name,
            bytes: bytes,
            contentType: picked.mimeType ?? 'image/jpeg',
            uploaderUid: me.uid,
            uploaderName: me.displayName,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ClubFile file,
  ) async {
    try {
      await ref.read(clubFileRepositoryProvider).delete(file);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
