import 'dart:convert';
import 'dart:typed_data';

/// A very small PDF 1.4 writer — enough for a printable table and nothing
/// more.
///
/// ## Why this exists rather than `package:pdf`
///
/// A schedule PDF is a page of ruled text. `package:pdf` + `printing` is
/// ~2 MB of Dart, pulls a platform plugin on every target, and on the web
/// wants `pdf.js` loaded from a CDN before its own preview will draw. That is
/// a large amount of surface to add to an app whose whole premise is a ₹8k
/// Android phone on 4G, for a feature that draws left-aligned Helvetica in
/// boxes. `data/image_composer.dart` makes the same trade for images and says
/// so; this is the same trade for one document.
///
/// ## What it deliberately does not do
///
/// Only the PDF base-14 fonts, which means WinAnsi (Latin-1) text. Telugu and
/// Hindi team names cannot be drawn by Helvetica at all — embedding a
/// Devanagari/Telugu TrueType subset is a font-shaping problem, not a PDF
/// problem, and shipping a half-broken one would print squares. Characters
/// outside WinAnsi are transliterated where there is an obvious ASCII
/// equivalent and dropped to '?' otherwise, so the row still lines up and the
/// time and court — the two things somebody prints a schedule *for* — are
/// always correct. [PdfWriter.isLossy] reports whether that happened so the
/// caller can warn instead of silently handing over a page of question marks.
class PdfWriter {
  PdfWriter({this.pageWidth = 595.28, this.pageHeight = 841.89});

  /// A4 portrait, in PDF points (1/72").
  final double pageWidth;
  final double pageHeight;

  final List<StringBuffer> _pages = [];
  StringBuffer? _current;

  /// Whether any text drawn so far lost characters to the WinAnsi fallback.
  bool get isLossy => _lossy;
  bool _lossy = false;

  /// Starts a new page. Must be called before any drawing.
  void newPage() {
    _current = StringBuffer();
    _pages.add(_current!);
  }

  int get pageCount => _pages.length;

  /// Makes an already-created page current again, so a second pass can draw
  /// on it. Footers need this: "Page 3 of 7" is unknowable while page 3 is
  /// being laid out.
  void selectPage(int index) {
    RangeError.checkValidIndex(index, _pages, 'index', _pages.length);
    _current = _pages[index];
  }

  /// Draws [text] with its baseline at ([x], [y]), measured from the
  /// BOTTOM-left of the page, PDF's own origin.
  void text(
    String text, {
    required double x,
    required double y,
    double size = 10,
    bool bold = false,
    PdfColor color = PdfColor.black,
  }) {
    if (text.isEmpty) return;
    final buf = _require();
    buf.write('BT ${color.fill} /${bold ? 'F2' : 'F1'} ');
    buf.write('${_n(size)} Tf ${_n(x)} ${_n(y)} Td (${_escape(text)}) Tj ET\n');
  }

  /// A filled rectangle — used for row shading and rules, never for art.
  void rect(
    double x,
    double y,
    double w,
    double h, {
    PdfColor color = PdfColor.black,
  }) {
    final buf = _require();
    buf.write('${color.fill} ${_n(x)} ${_n(y)} ${_n(w)} ${_n(h)} re f\n');
  }

  /// A horizontal hairline. Thin rectangles rather than stroked paths so the
  /// content stream needs no graphics-state operators at all.
  void hairline(double x, double y, double w, {PdfColor color = PdfColor.rule}) =>
      rect(x, y, w, 0.5, color: color);

  /// Truncates [s] to fit [maxWidth] at [size], appending an ellipsis.
  ///
  /// Widths come from [_helveticaWidths]; a table whose columns are laid out
  /// by guesswork overlaps its neighbours on exactly the long names that
  /// matter ("Kendriya Vidyalaya Picket B").
  String fit(String s, double maxWidth, {double size = 10, bool bold = false}) {
    if (measure(s, size: size, bold: bold) <= maxWidth) return s;
    const ellipsis = '…';
    final dotW = measure(ellipsis, size: size, bold: bold);
    var out = s;
    while (out.isNotEmpty &&
        measure(out, size: size, bold: bold) + dotW > maxWidth) {
      out = out.substring(0, out.length - 1);
    }
    return '${out.trimRight()}$ellipsis';
  }

  /// Width of [s] in points. Helvetica and Helvetica-Bold share this table
  /// closely enough for column fitting; bold is scaled by the ratio the two
  /// AFMs differ by on average rather than carrying a second 224-entry table.
  double measure(String s, {double size = 10, bool bold = false}) {
    var units = 0;
    for (final r in _winAnsi(s).codeUnits) {
      units += _helveticaWidths[r] ?? 556;
    }
    return units / 1000 * size * (bold ? 1.055 : 1.0);
  }

  StringBuffer _require() {
    final c = _current;
    if (c == null) {
      throw StateError('newPage() must be called before drawing.');
    }
    return c;
  }

  /// Serialises everything drawn so far into PDF bytes.
  Uint8List build({String title = 'Schedule'}) {
    if (_pages.isEmpty) newPage();

    // Object 1 catalog, 2 pages, 3 F1, 4 F2, then (content, page) per page.
    final objects = <String>[];
    const firstPageObj = 5;
    final pageIds = [
      for (var i = 0; i < _pages.length; i++) firstPageObj + i * 2 + 1,
    ];

    objects.add('<< /Type /Catalog /Pages 2 0 R >>');
    objects.add(
      '<< /Type /Pages /Count ${_pages.length} '
      '/Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] >>',
    );
    objects.add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    );
    objects.add(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>',
    );

    for (var i = 0; i < _pages.length; i++) {
      final stream = _pages[i].toString();
      objects.add(
        '<< /Length ${latin1.encode(stream).length} >>\nstream\n'
        '$stream\nendstream',
      );
      objects.add(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_n(pageWidth)} ${_n(pageHeight)}] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents ${firstPageObj + i * 2} 0 R >>',
      );
    }

    // `Info` last so its object number does not shift the page numbering
    // above, which is computed from a fixed base.
    objects.add('<< /Title (${_escape(title)}) /Producer (PlaySphere) >>');
    final infoId = objects.length;

    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(latin1.encode(out.toString()).length);
      out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }

    final xrefOffset = latin1.encode(out.toString()).length;
    out.write('xref\n0 ${objects.length + 1}\n');
    out.write('0000000000 65535 f \n');
    for (final o in offsets) {
      out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R '
      '/Info $infoId 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
    );

    return Uint8List.fromList(latin1.encode(out.toString()));
  }

  /// Trims trailing zeroes — a content stream of "72.00000000000001" is both
  /// larger and harder to read in a diff than "72".
  static String _n(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  String _escape(String s) => _winAnsi(s)
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');

  /// Folds a Dart string down to what a base-14 font can actually draw.
  String _winAnsi(String s) {
    final b = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= 0x20 && rune <= 0x7E) {
        b.writeCharCode(rune);
        continue;
      }
      final sub = _substitutions[rune];
      if (sub != null) {
        b.write(sub);
        continue;
      }
      // Latin-1 supplement survives WinAnsi unchanged; anything else does not.
      if (rune >= 0xA0 && rune <= 0xFF) {
        b.writeCharCode(rune);
        continue;
      }
      _lossy = true;
      b.write('?');
    }
    return b.toString();
  }

  /// The handful of non-Latin-1 characters this app actually emits.
  static const _substitutions = <int, String>{
    0x2018: "'",
    0x2019: "'",
    0x201C: '"',
    0x201D: '"',
    0x2013: '-',
    0x2014: '-',
    0x2026: '...',
    0x00A0: ' ',
    0x20B9: 'Rs.',
    0x2022: '-',
  };
}

/// A DeviceRGB fill colour, pre-rendered as its PDF operator.
class PdfColor {
  const PdfColor(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;

  String get fill => '${PdfWriter._n(r)} ${PdfWriter._n(g)} '
      '${PdfWriter._n(b)} rg';

  static const black = PdfColor(0.06, 0.09, 0.16);
  static const muted = PdfColor(0.39, 0.45, 0.55);
  static const rule = PdfColor(0.85, 0.88, 0.91);
  static const green = PdfColor(0.05, 0.55, 0.25);
  static const greenWash = PdfColor(0.90, 0.97, 0.92);
  static const white = PdfColor(1, 1, 1);
}


/// Helvetica advance widths, in 1/1000 em, for the WinAnsi range this writer
/// can emit. Straight from the Adobe AFM.
const Map<int, int> _helveticaWidths = {
  32: 278, 33: 278, 34: 355, 35: 556, 36: 556, 37: 889, 38: 667, 39: 191,
  40: 333, 41: 333, 42: 389, 43: 584, 44: 278, 45: 333, 46: 278, 47: 278,
  48: 556, 49: 556, 50: 556, 51: 556, 52: 556, 53: 556, 54: 556, 55: 556,
  56: 556, 57: 556, 58: 278, 59: 278, 60: 584, 61: 584, 62: 584, 63: 556,
  64: 1015, 65: 667, 66: 667, 67: 722, 68: 722, 69: 667, 70: 611, 71: 778,
  72: 722, 73: 278, 74: 500, 75: 667, 76: 556, 77: 833, 78: 722, 79: 778,
  80: 667, 81: 778, 82: 722, 83: 667, 84: 611, 85: 722, 86: 667, 87: 944,
  88: 667, 89: 667, 90: 611, 91: 278, 92: 278, 93: 278, 94: 469, 95: 556,
  96: 333, 97: 556, 98: 556, 99: 500, 100: 556, 101: 556, 102: 278, 103: 556,
  104: 556, 105: 222, 106: 222, 107: 500, 108: 222, 109: 833, 110: 556,
  111: 556, 112: 556, 113: 556, 114: 333, 115: 500, 116: 278, 117: 556,
  118: 500, 119: 722, 120: 500, 121: 500, 122: 500, 123: 334, 124: 260,
  125: 334, 126: 584,
};
