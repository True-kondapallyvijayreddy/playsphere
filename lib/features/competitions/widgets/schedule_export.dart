import 'package:flutter/material.dart';

import '../../../core/models/fixture.dart';
import '../../../domain/schedule/schedule_pdf.dart';
import '../../../domain/schedule/schedule_view_model.dart';
import '../../../shared/file_download.dart';

/// Building and handing over the schedule PDF.
///
/// Lives apart from [ScheduleBoard] because the button that starts it does
/// not: the board's own "PDF" button sits beside the "Matches" heading, which
/// on an event with four groups is below four standings tables and a screen
/// and a half of scrolling — the exact thing the schedule redesign existed to
/// fix, reintroduced for the button itself. The app bar carries the same
/// action at the top of the page, and both call this.
class ScheduleExport {
  const ScheduleExport._();

  /// Renders [fixtures] to a PDF and hands it to the platform — a share sheet
  /// on a phone, a download in a browser.
  ///
  /// Reports back through [context]'s messenger rather than returning: every
  /// caller is a button, and every button wants the same snackbar.
  static Future<void> download(
    BuildContext context, {
    required List<Fixture> fixtures,
    required String title,
    String subtitle = '',
    String? note,
    Set<String> mineEntrantIds = const {},
    bool byDay = false,
    String Function(Fixture)? sectionOf,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (fixtures.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('There are no matches to put in a schedule yet.'),
          ),
        );
      return;
    }

    try {
      final doc = SchedulePdf.build(
        title: title,
        subtitle: subtitle,
        note: note,
        hasMine: mineEntrantIds.isNotEmpty,
        sections: ScheduleFormat.toSections(
          fixtures,
          mineEntrantIds: mineEntrantIds,
          byDay: byDay,
          sectionOf: sectionOf,
        ),
      );

      await saveFileBytes(
        bytes: doc.bytes,
        filename: fileName(title),
        mimeType: 'application/pdf',
        shareText: '$title — match schedule',
      );

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              doc.lossy
                  // Said plainly rather than hidden, because somebody is
                  // about to print it: base-14 Helvetica cannot draw Telugu
                  // or Devanagari at all.
                  ? 'Schedule saved — but some names could not be printed in '
                      'Telugu or Hindi and appear as "?". Times and courts are '
                      'unaffected.'
                  : 'Schedule saved as ${fileName(title)}.',
            ),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not create the schedule PDF. $e')),
        );
    }
  }

  /// "U-19 Badminton (Doubles)" becomes "U-19-Badminton-Doubles-schedule.pdf".
  static String fileName(String title) {
    final slug = title
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'schedule' : slug}-schedule.pdf';
  }
}

/// The app-bar affordance: a labelled button, not a bare glyph.
///
/// "Everything else in this app bar is an unlabelled icon" is not a reason to
/// make this one too — the first report about the feature was that the
/// download could not be found anywhere, and a download icon among five other
/// glyphs is findable only by someone already looking for it.
class ScheduleDownloadButton extends StatefulWidget {
  const ScheduleDownloadButton({
    super.key,
    required this.fixtures,
    required this.title,
    this.subtitle = '',
    this.note,
    this.mineEntrantIds = const {},
    this.byDay = false,
    this.sectionOf,
    this.compact = false,
    this.label = 'PDF',
  });

  final List<Fixture> fixtures;
  final String title;
  final String subtitle;
  final String? note;
  final Set<String> mineEntrantIds;
  final bool byDay;
  final String Function(Fixture)? sectionOf;

  /// An icon button for a crowded app bar, rather than a labelled one.
  final bool compact;
  final String label;

  @override
  State<ScheduleDownloadButton> createState() => _ScheduleDownloadButtonState();
}

class _ScheduleDownloadButtonState extends State<ScheduleDownloadButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await ScheduleExport.download(
        context,
        fixtures: widget.fixtures,
        title: widget.title,
        subtitle: widget.subtitle,
        note: widget.note,
        mineEntrantIds: widget.mineEntrantIds,
        byDay: widget.byDay,
        sectionOf: widget.sectionOf,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fixtures.isEmpty) return const SizedBox.shrink();

    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: DefaultTextStyle.of(context).style.color,
      ),
    );

    if (widget.compact) {
      return IconButton(
        tooltip: 'Download the schedule as a PDF',
        onPressed: _busy ? null : _run,
        icon: _busy ? spinner : const Icon(Icons.download_outlined),
      );
    }

    return TextButton.icon(
      onPressed: _busy ? null : _run,
      icon: _busy ? spinner : const Icon(Icons.picture_as_pdf_outlined, size: 18),
      label: Text(widget.label),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}
