import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/image_composer.dart';
import 'app_scaffold.dart';
import 'ui_kit.dart';

/// What the source sheet came back with.
enum _Choice { camera, gallery, remove }

/// Runs the whole "let me put a picture here" flow in one call: ask where the
/// image comes from, pick it, shrink it, hand the bytes to [onUpload], and say
/// what happened.
///
/// Every branding upload in the app goes through this — a club crest, a team
/// crest, an event banner, a season banner, a member's photo, a ground's
/// picture. They differ only in the sentence at the top of the sheet and the
/// repository call at the end, and the six screens that host them should not
/// each be reimplementing a picker, a busy state and an error path.
///
/// Returns true when something was actually written, so a caller can show its
/// own confirmation or refresh a local cache. Returns false when the person
/// backed out, which is the common case and is not an error.
///
/// The busy state is a modal barrier rather than an inline spinner, on
/// purpose. An upload on a rural connection takes seconds, and the tap targets
/// underneath — "change photo" again, or navigating away mid-write — are
/// exactly the ones that should not be available while it runs.
Future<bool> pickAndUploadImage({
  required BuildContext context,
  required String title,

  /// What the picture is for, which decides how hard it is downscaled.
  required ImageShape shape,

  /// Given the picked, already-shrunk bytes. Should throw on failure —
  /// the error is caught here and shown with [showError].
  required Future<void> Function(PickedImage image) onUpload,

  /// Offered as a third option when there is already an image to clear.
  /// Omit it and the sheet shows only the two sources.
  Future<void> Function()? onRemove,

  /// Shown in the snackbar on success, e.g. `'Club crest updated.'`.
  String successMessage = 'Picture updated.',

  /// Shown in the snackbar after a removal.
  String removedMessage = 'Picture removed.',

  /// One line under the title saying where the picture will appear.
  ///
  /// Used where that is not obvious and matters — a junior's profile photo,
  /// which shows on their career page and on any team sheet their club can
  /// see. The codebase already gates a minor's profile behind guardian
  /// consent in `firestore.rules`, so this is disclosure rather than a new
  /// control: the person choosing the picture should know where it lands
  /// before they choose it, not after.
  String? note,
  ImageComposer? composer,
}) async {
  final choice = await _askSource(
    context: context,
    title: title,
    note: note,
    offerRemove: onRemove != null,
  );

  if (choice == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);

  if (choice == _Choice.remove) {
    try {
      await onRemove!();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(removedMessage)));
      return true;
    } catch (e) {
      if (context.mounted) showError(context, e);
      return false;
    }
  }

  final PickedImage? picked;
  try {
    picked = await (composer ?? ImageComposer()).pick(
      source:
          choice == _Choice.camera ? ImageSource.camera : ImageSource.gallery,
      shape: shape,
    );
  } catch (e) {
    // A denied camera permission arrives here as a PlatformException, and a
    // person who has just said "no" to the permission dialog does not need a
    // second dialog about it — but they do need to know why nothing happened.
    if (context.mounted) showError(context, e);
    return false;
  }

  // Cancelled the picker. Not a failure, and nothing to say about it.
  if (picked == null) return false;
  if (!context.mounted) return false;

  final barrier = _showUploadBarrier(context);
  try {
    await onUpload(picked);
    barrier.remove();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } catch (e) {
    barrier.remove();
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// Picks and shrinks an image without uploading anything, for the one case
/// [pickAndUploadImage] cannot serve: a create form.
///
/// A season's crest and banner are chosen before the season document exists,
/// so there is no id to upload them under and no document to link them to.
/// The form holds what this returns, shows it in a live preview, and uploads
/// it the moment the create call comes back with an id — see
/// `SeasonBranding.uploadTo`. Uploading to a staging path first would leave an
/// orphaned object in the bucket every time somebody backed out of the form.
///
/// Returns null when the person cancelled either the source sheet or the
/// picker, which is the common case and not an error.
Future<PickedImage?> pickLocalImage({
  required BuildContext context,
  required String title,
  required ImageShape shape,
  String? note,
  ImageComposer? composer,
}) async {
  final choice = await _askSource(context: context, title: title, note: note);
  if (choice == null || !context.mounted) return null;

  try {
    return await (composer ?? ImageComposer()).pick(
      source:
          choice == _Choice.camera ? ImageSource.camera : ImageSource.gallery,
      shape: shape,
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

/// The "where does this picture come from" sheet, shared by both flows above
/// so a staged pick and an immediate upload ask the same question the same
/// way.
Future<_Choice?> _askSource({
  required BuildContext context,
  required String title,
  String? note,
  bool offerRemove = false,
}) =>
    showModalBottomSheet<_Choice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                ],
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, _Choice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, _Choice.gallery),
          ),
          if (offerRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Ps.live),
              title: const Text(
                'Remove current picture',
                style: TextStyle(color: Ps.live),
              ),
              onTap: () => Navigator.pop(sheetContext, _Choice.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

OverlayEntry _showUploadBarrier(BuildContext context) {
  final entry = OverlayEntry(
    builder: (_) => const ColoredBox(
      color: Color(0x66000000),
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                SizedBox(height: 14),
                Text('Uploading…'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return entry;
}

/// Wraps a crest, an avatar or a banner in the affordance that says it can be
/// changed: a small camera badge in the corner, and the whole thing tappable.
///
/// Renders [child] untouched when [onTap] is null, so a screen can hand the
/// same widget to everybody and let this decide whether the person looking at
/// it is allowed to change it. That keeps the "can I edit this" check in one
/// place per screen instead of duplicated around every visual.
class EditableImage extends StatelessWidget {
  const EditableImage({
    super.key,
    required this.child,
    required this.onTap,
    this.badgeSize = 22,
    this.tooltip,
    this.shape = BoxShape.circle,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double badgeSize;
  final String? tooltip;

  /// Where the badge sits. A circle avatar wants it tucked inside the corner;
  /// a rectangular crest or banner wants it flush.
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    if (tap == null) return child;

    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: shape == BoxShape.circle ? -1 : -4,
          bottom: shape == BoxShape.circle ? -1 : -4,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: Ps.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Ps.surface, width: 2),
            ),
            child: Icon(
              Icons.photo_camera,
              size: badgeSize * 0.5,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(Ps.radius),
        child:
            tooltip == null ? stack : Tooltip(message: tooltip!, child: stack),
      ),
    );
  }
}
