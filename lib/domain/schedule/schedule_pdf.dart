import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'pdf_writer.dart';

/// One printable line of a schedule.
///
/// Deliberately made of strings rather than a `Fixture`: the same document is
/// wanted for a single event, for a whole season, and one day for a club's
/// own matches across several seasons, and those three do not share a model.
/// Formatting a fixture into these fields is the caller's job and happens in
/// exactly one place — [ScheduleDocument.fromFixtureLike].
class ScheduleRow {
  const ScheduleRow({
    required this.round,
    required this.when,
    required this.teamA,
    required this.teamB,
    this.court = '',
    this.result = '',
    this.mine = false,
  });

  final String round;
  final String when;
  final String teamA;
  final String teamB;
  final String court;

  /// The score line for a finished match, empty for one still to come.
  final String result;

  /// Whether this match involves the reader's own club, team or account.
  /// Printed as a green wash, which is what makes a 96-match programme
  /// usable on paper taped to a noticeboard.
  final bool mine;
}

/// A block of rows under one heading — a group, a knockout stage, a day.
class ScheduleSection {
  const ScheduleSection({required this.title, required this.rows});

  final String title;
  final List<ScheduleRow> rows;
}

/// Lays a schedule out as an A4 PDF.
class SchedulePdf {
  const SchedulePdf._();

  static const double _margin = 40;
  static const double _rowHeight = 17;
  static const double _fontSize = 9;

  // Round | Time | Match | Court | Result, summing to the 515pt content width.
  static const List<double> _cols = [38, 96, 224, 84, 73];
  static const List<String> _headings = [
    'Round',
    'Date & time',
    'Match',
    'Court / venue',
    'Result',
  ];

  /// Builds the document. Returns the bytes and whether any name had to be
  /// transliterated, so the caller can say so rather than let a coach
  /// discover it at the printer.
  static ({Uint8List bytes, bool lossy, int pages}) build({
    required String title,
    required String subtitle,
    required List<ScheduleSection> sections,
    DateTime? generatedAt,
    bool hasMine = false,
    String? note,
  }) {
    final pdf = PdfWriter();
    final now = generatedAt ?? DateTime.now();
    final contentWidth = pdf.pageWidth - _margin * 2;
    const bottom = _margin + 24;

    var y = 0.0;
    var pageIndex = 0;

    void startPage() {
      pdf.newPage();
      pageIndex++;
      y = pdf.pageHeight - _margin;

      if (pageIndex == 1) {
        pdf.text(title, x: _margin, y: y - 16, size: 17, bold: true);
        y -= 34;
        if (subtitle.isNotEmpty) {
          pdf.text(subtitle,
              x: _margin, y: y, size: 10, color: PdfColor.muted);
          y -= 15;
        }
        pdf.text(
          'Generated ${DateFormat('d MMM yyyy, h:mm a').format(now)} '
          '· PlaySphere',
          x: _margin,
          y: y,
          size: 8,
          color: PdfColor.muted,
        );
        y -= 12;
        if (hasMine) {
          // The legend has to be on the page, not in the app that produced
          // it: a printed sheet on a noticeboard has no tooltip.
          pdf.rect(_margin, y - 2, 16, 8, color: PdfColor.greenWash);
          pdf.rect(_margin, y - 2, 2, 8, color: PdfColor.green);
          pdf.text('Your club\'s matches',
              x: _margin + 22, y: y, size: 8, color: PdfColor.green);
          y -= 12;
        }
        if (note != null && note.isNotEmpty) {
          pdf.text(pdf.fit(note, contentWidth, size: 8),
              x: _margin, y: y, size: 8, color: PdfColor.muted);
          y -= 12;
        }
        y -= 6;
      } else {
        pdf.text(pdf.fit(title, contentWidth - 80, size: 9, bold: true),
            x: _margin, y: y - 9, size: 9, bold: true);
        y -= 22;
      }
    }

    void columnHeadings() {
      var x = _margin;
      pdf.rect(_margin, y - 5, contentWidth, 15,
          color: const PdfColor(0.95, 0.96, 0.97));
      for (var i = 0; i < _headings.length; i++) {
        pdf.text(_headings[i],
            x: x + 4, y: y, size: 7.5, bold: true, color: PdfColor.muted);
        x += _cols[i];
      }
      y -= 18;
    }

    startPage();

    for (final section in sections) {
      if (section.rows.isEmpty) continue;

      // A heading stranded at the foot of a page with no rows under it is
      // worse than a slightly short page.
      if (y - (_rowHeight * 3) < bottom) {
        startPage();
      }

      pdf.text(section.title, x: _margin, y: y, size: 11, bold: true);
      y -= 6;
      pdf.hairline(_margin, y, contentWidth);
      y -= 14;
      columnHeadings();

      for (final row in section.rows) {
        if (y < bottom) {
          startPage();
          pdf.text('${section.title} (continued)',
              x: _margin, y: y, size: 11, bold: true);
          y -= 6;
          pdf.hairline(_margin, y, contentWidth);
          y -= 14;
          columnHeadings();
        }

        if (row.mine) {
          pdf.rect(_margin, y - 5, contentWidth, _rowHeight,
              color: PdfColor.greenWash);
          pdf.rect(_margin, y - 5, 2, _rowHeight, color: PdfColor.green);
        }

        final cells = [
          row.round,
          row.when,
          '${row.teamA}  v  ${row.teamB}',
          row.court,
          row.result,
        ];
        var x = _margin;
        for (var i = 0; i < cells.length; i++) {
          final isMatch = i == 2;
          pdf.text(
            pdf.fit(cells[i], _cols[i] - 8,
                size: _fontSize, bold: isMatch && row.mine),
            x: x + 4,
            y: y,
            size: _fontSize,
            bold: isMatch && row.mine,
            color: i == 0 || i == 3 ? PdfColor.muted : PdfColor.black,
          );
          x += _cols[i];
        }
        y -= _rowHeight;
        pdf.hairline(_margin, y + 9, contentWidth);
      }

      y -= 12;
    }

    // Footers last, once the page count is known — "Page 3 of 7" cannot be
    // written while page 3 is being laid out.
    _stampFooters(pdf, _margin);

    return (bytes: pdf.build(title: title), lossy: pdf.isLossy, pages: pdf.pageCount);
  }

  /// Re-opens each page's content stream to add its footer.
  ///
  /// [PdfWriter] appends to whichever page is current, so this walks them in
  /// order and draws one line per page rather than trying to reserve space
  /// during layout.
  static void _stampFooters(PdfWriter pdf, double margin) {
    final total = pdf.pageCount;
    for (var i = 0; i < total; i++) {
      pdf.selectPage(i);
      pdf.text(
        'Page ${i + 1} of $total',
        x: pdf.pageWidth - margin - 60,
        y: margin - 8,
        size: 8,
        color: PdfColor.muted,
      );
    }
  }
}
