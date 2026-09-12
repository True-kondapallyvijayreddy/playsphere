/// Standing at a ground and proving it, before a listing exists.
///
/// ## Why listing a ground got harder
///
/// It used to be a form. Type a name, a city and a phone number, press save,
/// and the listing was live, bookable and carrying a number for strangers to
/// ring. That is a two-minute job from a sofa, and it is the whole setup for
/// the scam this flow exists to stop: list a turf you have nothing to do
/// with, wait for a club to book Sunday evening, ring them, ask for a UPI
/// advance to "hold the slot", disappear. PlaySphere never touches that money
/// — see `FeeSettlement` — so there is nothing to reverse afterwards.
///
/// The only defence that acts before the phone call is to make publishing
/// cost something. This flow makes it cost a trip: a live location fix that
/// is not the phone's cached one, photographs taken by the camera at that
/// fix rather than chosen from a gallery, and a document with the claimant's
/// name on it. None of that proves title. It does turn a two-minute fraud
/// into an afternoon at a real location, which is a different business
/// proposition.
///
/// ## Why the details form is not in here
///
/// This screen collects only the evidence, then hands a [GroundProofBundle]
/// to the existing editor, which already knows how to ask for a name, a rate
/// and opening hours and is also the screen owners use to edit a listing
/// later. Copying those fields into a wizard would mean two forms drifting
/// apart, and the one that drifted would be the one nobody looks at.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/ground_verification.dart';
import '../../data/ground_repository.dart';
import '../../data/site_fix_service.dart';
import '../../domain/geo/site_presence.dart';
import '../../shared/app_scaffold.dart';

/// Everything the capture flow gathered, on its way to the details form.
class GroundProofBundle {
  const GroundProofBundle({
    required this.proofs,
    required this.claimType,
    required this.holderName,
    required this.documentKind,
    required this.documentBytes,
    required this.documentContentType,
    required this.pin,
  });

  final List<CapturedProof> proofs;
  final GroundClaimType claimType;
  final String holderName;
  final GroundDocumentKind documentKind;
  final Uint8List documentBytes;
  final String documentContentType;

  /// The fix to save as the ground's location — the most precise of the
  /// captures, not an average of them. See `SitePresence.bestFix`.
  final SiteFix pin;
}

/// Collects the proof, or explains why it cannot be collected here.
class ListGroundProofScreen extends ConsumerStatefulWidget {
  const ListGroundProofScreen({super.key});

  @override
  ConsumerState<ListGroundProofScreen> createState() =>
      _ListGroundProofScreenState();
}

class _ListGroundProofScreenState extends ConsumerState<ListGroundProofScreen> {
  static const _service = SiteFixService();

  int _step = 0;

  /// The reading taken when they said they were at the ground. Kept so the
  /// arrival step can show it and so a set with only a document in it still
  /// has somewhere to anchor.
  SiteFix? _arrivalFix;
  bool _locating = false;

  final _captures = <GroundProofKind, CapturedProof>{};
  GroundProofKind? _capturing;

  GroundClaimType _claimType = GroundClaimType.owner;
  final _holderName = TextEditingController();
  GroundDocumentKind _documentKind = GroundDocumentKind.electricityBill;
  Uint8List? _documentBytes;
  String _documentContentType = 'image/jpeg';
  bool _pickingDocument = false;

  @override
  void dispose() {
    _holderName.dispose();
    super.dispose();
  }

  // --- Step 1: arrive ------------------------------------------------------

  Future<void> _confirmArrival() async {
    setState(() => _locating = true);
    try {
      final fix = await _service.currentChecked();
      if (!mounted) return;
      setState(() {
        _arrivalFix = fix;
        _step = 1;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // --- Step 2: photograph --------------------------------------------------

  /// Takes one photograph and stamps it with a reading taken at the same
  /// moment.
  ///
  /// The order matters and is the reverse of the obvious one: the fix is read
  /// *after* the shutter, not before the camera opens. A fix taken before
  /// would be minutes old by the time a slow camera and a slower preview are
  /// done with it, and would be evidence of where the person was when they
  /// tapped a button rather than where they were when they took the picture.
  Future<void> _capture(GroundProofKind kind) async {
    setState(() => _capturing = kind);
    try {
      final shot = await ImagePicker().pickImage(
        // Camera only. A gallery pick is the single cheapest way to defeat
        // this whole flow — any photograph of any ground, from anywhere, at
        // any time — and offering the option at all invites it.
        source: ImageSource.camera,
        // Downscaled on the device. Rural 4G is the constraint that decides
        // whether an owner finishes this flow, and four full-size camera
        // photos is 25MB.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (shot == null) return;

      final fix = await _service.currentChecked();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;

      final candidate = CapturedProof(
        kind: kind,
        bytes: bytes,
        contentType: shot.mimeType ?? 'image/jpeg',
        fix: fix,
      );

      // Check the new photo against the ones already taken before accepting
      // it, so somebody who has driven somewhere else is told at the photo
      // that broke it rather than at submission with four to re-take.
      final withNew = {..._captures, kind: candidate};
      final verdict = SitePresence.checkSet(
        [
          if (_arrivalFix != null) _arrivalFix!,
          ...withNew.values.map((c) => c.fix),
        ],
        now: DateTime.now(),
      );
      if (!verdict.isOk) {
        showError(context, verdict.problem!.message);
        return;
      }

      setState(() => _captures[kind] = candidate);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _capturing = null);
    }
  }

  bool get _hasRequiredPhotos => GroundProofKind.values
      .where((k) => k.isRequired && k != GroundProofKind.ownershipDocument)
      .every(_captures.containsKey);

  // --- Step 3: ownership ---------------------------------------------------

  /// The one file in this flow that may come from the gallery.
  ///
  /// An electricity bill is evidence about a person, not about being
  /// somewhere, so the camera restriction buys nothing here — and plenty of
  /// people have a PDF or a screenshot of their bill rather than the paper.
  /// Forcing a camera would only make them photograph a phone screen.
  Future<void> _pickDocument(ImageSource source) async {
    setState(() => _pickingDocument = true);
    try {
      final shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 88,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _documentBytes = bytes;
        _documentContentType = shot.mimeType ?? 'image/jpeg';
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _pickingDocument = false);
    }
  }

  bool get _ownershipComplete =>
      _documentBytes != null && _holderName.text.trim().length >= 3;

  // --- Finish --------------------------------------------------------------

  void _finish() {
    final proofs = _captures.values.toList();
    final fixes = [
      if (_arrivalFix != null) _arrivalFix!,
      ...proofs.map((p) => p.fix),
    ];
    final verdict = SitePresence.checkSet(fixes, now: DateTime.now());
    if (!verdict.isOk) {
      showError(context, verdict.problem!.message);
      return;
    }

    Navigator.of(context).pop(
      GroundProofBundle(
        proofs: proofs,
        claimType: _claimType,
        holderName: _holderName.text.trim(),
        documentKind: _documentKind,
        documentBytes: _documentBytes!,
        documentContentType: _documentContentType,
        pin: SitePresence.bestFix(fixes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Stated rather than half-supported. `ImageSource.camera` on the web
    // degrades to a file chooser on most desktop browsers, which turns the
    // one restriction this flow depends on into a suggestion. A gate that
    // silently stops being a gate on one platform is worse than a gate that
    // says it does not work there.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('List a ground')),
        body: ContentBounds(
          maxWidth: 520,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(
              icon: Icons.phone_iphone,
              title: 'List your ground from the app',
              message:
                  'Listing a ground means photographing it while you are '
                  'standing there, so PlaySphere can show players it is real. '
                  'A browser cannot do that. Open PlaySphere on your phone, '
                  'go to My grounds, and list it from the ground itself.\n\n'
                  'You can still edit a ground you have already listed from '
                  'here.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back'),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('List a ground'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            minHeight: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 560,
          child: switch (_step) {
            0 => _ArriveStep(
                busy: _locating,
                onConfirm: _confirmArrival,
              ),
            1 => _PhotoStep(
                captures: _captures,
                capturing: _capturing,
                onCapture: _capture,
                onBack: () => setState(() => _step = 0),
                onContinue:
                    _hasRequiredPhotos ? () => setState(() => _step = 2) : null,
              ),
            _ => _OwnershipStep(
                claimType: _claimType,
                onClaimType: (v) => setState(() => _claimType = v),
                holderName: _holderName,
                documentKind: _documentKind,
                onDocumentKind: (v) => setState(() => _documentKind = v),
                documentBytes: _documentBytes,
                picking: _pickingDocument,
                onPick: _pickDocument,
                onChanged: () => setState(() {}),
                onBack: () => setState(() => _step = 1),
                onContinue: _ownershipComplete ? _finish : null,
              ),
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1
// ---------------------------------------------------------------------------

class _ArriveStep extends StatelessWidget {
  const _ArriveStep({required this.busy, required this.onConfirm});

  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.pin_drop_outlined,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          'Are you at the ground now?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'PlaySphere asks every ground owner to list from the ground itself. '
          'You will take two or three photos here, and your phone records '
          'that they were taken at this spot.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why we ask',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'People have been listing grounds they do not run, taking '
                  'advance payments over the phone and vanishing. A listing '
                  'made from the ground is one a player can trust — and it '
                  'gets your ground shown above the ones that were not.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : onConfirm,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          label: Text(busy ? 'Finding your location…' : 'Yes, I am here'),
        ),
        const SizedBox(height: 12),
        Text(
          'Step outside if you can — a phone indoors often cannot tell where '
          'it is precisely enough.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2
// ---------------------------------------------------------------------------

class _PhotoStep extends StatelessWidget {
  const _PhotoStep({
    required this.captures,
    required this.capturing,
    required this.onCapture,
    required this.onBack,
    required this.onContinue,
  });

  final Map<GroundProofKind, CapturedProof> captures;
  final GroundProofKind? capturing;
  final void Function(GroundProofKind) onCapture;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kinds = GroundProofKind.values
        .where((k) => k != GroundProofKind.ownershipDocument)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text('Photograph the ground',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Taken with the camera, here, now. These are what a player sees '
          'when they are deciding whether to book.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        for (final kind in kinds) ...[
          _CaptureTile(
            kind: kind,
            capture: captures[kind],
            busy: capturing == kind,
            onTap: capturing == null ? () => onCapture(kind) : null,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(onPressed: onBack, child: const Text('Back')),
            const Spacer(),
            FilledButton(
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
          ],
        ),
        if (onContinue == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The playing area and the entrance are both needed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.kind,
    required this.capture,
    required this.busy,
    required this.onTap,
  });

  final GroundProofKind kind;
  final CapturedProof? capture;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = capture != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: done
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(capture!.bytes, fit: BoxFit.cover),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          busy ? Icons.hourglass_top : Icons.photo_camera_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            kind.label,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!kind.isRequired)
                          Text(
                            'Optional',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      done
                          // The accuracy is shown back deliberately. It tells
                          // an owner whose fixes are poor that the problem is
                          // their sky view, not the app, which is the
                          // difference between them stepping outside and them
                          // giving up.
                          ? 'Taken here · ±${capture!.fix.accuracyMetres.round()}m'
                          : kind.instruction,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: done
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                done ? Icons.check_circle : Icons.chevron_right,
                color: done
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3
// ---------------------------------------------------------------------------

class _OwnershipStep extends StatelessWidget {
  const _OwnershipStep({
    required this.claimType,
    required this.onClaimType,
    required this.holderName,
    required this.documentKind,
    required this.onDocumentKind,
    required this.documentBytes,
    required this.picking,
    required this.onPick,
    required this.onChanged,
    required this.onBack,
    required this.onContinue,
  });

  final GroundClaimType claimType;
  final ValueChanged<GroundClaimType> onClaimType;
  final TextEditingController holderName;
  final GroundDocumentKind documentKind;
  final ValueChanged<GroundDocumentKind> onDocumentKind;
  final Uint8List? documentBytes;
  final bool picking;
  final void Function(ImageSource) onPick;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text('How do you run this ground?',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Answer honestly — most people listing a ground are not the '
          'registered owner, and that is fine.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final type in GroundClaimType.values)
          RadioListTile<GroundClaimType>(
            value: type,
            groupValue: claimType,
            onChanged: (v) => v == null ? null : onClaimType(v),
            title: Text(type.label),
            subtitle: Text(type.blurb, style: theme.textTheme.bodySmall),
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 16),
        TextField(
          controller: holderName,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Name on the document',
            helperText:
                'As it is printed — it does not have to match your PlaySphere '
                'name.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<GroundDocumentKind>(
          value: documentKind,
          decoration: const InputDecoration(
            labelText: 'What are you sending?',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final kind in GroundDocumentKind.values)
              DropdownMenuItem(value: kind, child: Text(kind.label)),
          ],
          onChanged: (v) => v == null ? null : onDocumentKind(v),
        ),
        const SizedBox(height: 16),
        if (documentBytes != null)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Image.memory(documentBytes!, fit: BoxFit.contain),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle),
                  title: const Text('Document attached'),
                  trailing: TextButton(
                    onPressed:
                        picking ? null : () => onPick(ImageSource.gallery),
                    child: const Text('Replace'),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: picking ? null : () => onPick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Photograph it'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: picking ? null : () => onPick(ImageSource.gallery),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Choose a file'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This document is private. Players never see it — only '
                    'you and the PlaySphere reviewer checking your listing.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(onPressed: onBack, child: const Text('Back')),
            const Spacer(),
            FilledButton(
              onPressed: onContinue,
              child: const Text('Next: ground details'),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
