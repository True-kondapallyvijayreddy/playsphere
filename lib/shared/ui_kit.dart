import 'package:flutter/material.dart';

/// The visual language of the redesigned screens.
///
/// This is deliberately *not* a rewrite of [AppTheme]. The app has 271 Dart
/// files reading `colorScheme.*` roles, and repainting those roles would
/// restyle every screen at once — including the twenty-odd that have no
/// mockup and no one to check them against. So the new look is opt-in: a
/// screen adopts it by building from the widgets below, and everything else
/// keeps rendering exactly as it did.
///
/// The palette is the mockup's neutral system with the product's own turf
/// green kept as the action colour. The mockup used indigo; indigo is not
/// this product's brand, and the layout is what made those screens read well,
/// not the hue.
class Ps {
  const Ps._();

  // --- Neutrals ---------------------------------------------------------
  //
  // A cool grey ramp rather than Material's warm one. The sport tiles below
  // are highly saturated, and on a warm grey they pick up a muddy cast where
  // on a slate they stay clean.

  /// What the page sits on. Not white: the cards are white, and a white card
  /// on a white page needs a shadow to separate, which is the heavy look the
  /// mockup avoids.
  static const Color canvas = Color(0xFFF8FAFC);

  /// Cards, sheets, the app bar.
  static const Color surface = Color(0xFFFFFFFF);

  /// The hairline that does the separating work a shadow would otherwise do.
  static const Color border = Color(0xFFE2E8F0);

  /// Primary text.
  static const Color ink = Color(0xFF0F172A);

  /// Secondary text — the "1,245 Tournaments" line, field labels, captions.
  static const Color muted = Color(0xFF64748B);

  /// Third-level text, used sparingly: table column headings.
  static const Color faint = Color(0xFF94A3B8);

  // --- Brand ------------------------------------------------------------

  /// Kept from [AppTheme.primaryTurfGreen]. Duplicated as a literal rather
  /// than imported so this file stays readable as a palette; the two must
  /// move together if the brand green ever changes.
  static const Color primary = Color(0xFF16A34A);

  /// The live/urgent accent, matching [LiveDot]'s dot.
  static const Color live = Color(0xFFDC2626);

  // --- Shape ------------------------------------------------------------

  /// Cards and sheets. The mockup runs a consistent 16 on every container
  /// large enough to hold a heading.
  static const double radius = 16;

  /// Buttons, fields, chips, and the small sport tiles — anything whose
  /// height is roughly one line of text. A 16 radius on a 40pt-tall control
  /// reads as a pill, which is a different component.
  static const double radiusSm = 12;

  /// The page gutter. Every redesigned screen uses this so headings line up
  /// across screens when you navigate between them.
  static const EdgeInsets gutter = EdgeInsets.symmetric(horizontal: 16);
}

/// How each sport is drawn wherever it appears: a saturated rounded square
/// with a white glyph.
///
/// Keyed by the ids in `SportCatalog.all`. The catalogue already carries an
/// emoji per sport, and emoji were the obvious first choice — but they render
/// from the system font, so the same grid is flat-and-grey on one Android
/// build and glossy 3D on another, and they cannot take the tinted background
/// the mockup builds the whole grid around. A Material glyph is consistent on
/// every device the product ships to.
class SportVisual {
  const SportVisual(this.color, this.icon);

  final Color color;
  final IconData icon;

  /// Falls back rather than throwing: a sport can be added to the catalogue
  /// in one commit and given a colour in the next, and a missing entry must
  /// not be able to take the sports grid down.
  static SportVisual of(String sportId) => _byId[sportId] ?? _fallback;

  static const SportVisual _fallback =
      SportVisual(Color(0xFF64748B), Icons.sports);

  static const Map<String, SportVisual> _byId = {
    'cricket': SportVisual(Color(0xFFEF4444), Icons.sports_cricket),
    'football': SportVisual(Color(0xFF10B981), Icons.sports_soccer),
    'badminton': SportVisual(Color(0xFF6366F1), Icons.sports_tennis),
    'volleyball': SportVisual(Color(0xFF3B82F6), Icons.sports_volleyball),
    'basketball': SportVisual(Color(0xFFF97316), Icons.sports_basketball),
    'table_tennis': SportVisual(Color(0xFFF43F5E), Icons.sports_tennis),
    'tennis': SportVisual(Color(0xFF22C55E), Icons.sports_tennis),
    'kabaddi': SportVisual(Color(0xFF8B5CF6), Icons.sports_kabaddi),
    'chess': SportVisual(Color(0xFF1E293B), Icons.grid_view),
    'hockey': SportVisual(Color(0xFF0EA5E9), Icons.sports_hockey),
    'kho_kho': SportVisual(Color(0xFFD946EF), Icons.directions_run),
    'throwball': SportVisual(Color(0xFF14B8A6), Icons.sports_handball),
    'carrom': SportVisual(Color(0xFFA16207), Icons.album),
    'athletics_sprint': SportVisual(Color(0xFFF59E0B), Icons.directions_run),
    'athletics_field': SportVisual(Color(0xFFEA580C), Icons.sports_score),
  };
}

/// The saturated rounded square itself, at whatever size the caller needs —
/// 56 in the home grid, 44 in a list row, 32 in the club's sports strip.
class SportBadge extends StatelessWidget {
  const SportBadge({super.key, required this.sportId, this.size = 44});

  final String sportId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = SportVisual.of(sportId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.color,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      // The glyph holds a fixed ratio to the tile so a 32pt badge and a 56pt
      // badge read as the same component at two sizes rather than as two
      // components.
      child: Icon(visual.icon, color: Colors.white, size: size * 0.5),
    );
  }
}

/// The flat, hairline-bordered container the redesigned screens are built
/// from.
///
/// Does not use [Card]. The app's [CardTheme] carries a green border and a
/// tinted shadow that a screen following the mockup has to fight, and
/// fighting a theme from inside a widget is how two styles end up
/// half-applied on the same screen.
class PsCard extends StatelessWidget {
  const PsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(Ps.radius);
    return Material(
      color: color ?? Ps.surface,
      // A hairline instead of elevation. On the 2GB devices this product
      // targets, a list of elevated cards is a list of saved layers; a border
      // is a single draw call and separates just as well on a grey canvas.
      //
      // `shape` alone, never alongside `borderRadius` — Material asserts the
      // two are not both set, and the pair is easy to write because most of
      // its other properties do coexist.
      shape: RoundedRectangleBorder(
        borderRadius: shape,
        side: const BorderSide(color: Ps.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A block heading with an optional "View All" on the right.
///
/// Distinct from the existing [SectionHeader], which leads with an icon and
/// carries a subtitle line. The mockup's headings are a single bold line, and
/// keeping both means the screens that have not been redesigned do not shift
/// underneath this change.
class PsSectionHeader extends StatelessWidget {
  const PsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel = 'View All',
    this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
          ),
          if (onAction != null)
            // A plain tappable label, not a TextButton: the button's own
            // padding pushes "View All" a visible distance in from the page
            // gutter, so it stops lining up with the cards beneath it.
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Ps.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One figure and its label, as used in the club header and the player
/// profile — "28 / Matches", "1,824 / Runs".
class PsStat extends StatelessWidget {
  const PsStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Announced as one phrase — "28 Matches" — rather than as two unrelated
    // labels. A screen reader walking a four-stat row otherwise reads
    // "28, 1824, 61, 68%" and then four headings, which is not recoverable
    // into which number went with which.
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Ps.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// An evenly divided row of [PsStat]s.
///
/// Takes four in the mockup but is not fixed at four — a player who has only
/// ever played chess has no wickets column, and padding the row with a dash
/// to keep the count at four is worse than showing three.
class PsStatRow extends StatelessWidget {
  const PsStatRow({super.key, required this.stats});

  final List<PsStat> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          Expanded(child: stats[i]),
          if (i != stats.length - 1)
            const SizedBox(
              height: 32,
              child: VerticalDivider(width: 1, color: Ps.border, thickness: 1),
            ),
        ],
      ],
    );
  }
}

/// The rounded search field at the top of the home and directory screens.
class PsSearchField extends StatelessWidget {
  const PsSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  /// Set when the field is a button that opens a search screen rather than a
  /// field that filters in place — the home screen's is the former.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      style: const TextStyle(fontSize: 14, color: Ps.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Ps.faint),
        prefixIcon: const Icon(Icons.search, size: 20, color: Ps.faint),
        filled: true,
        fillColor: Ps.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        // Every border state is declared. The app-wide
        // [AppTheme._inputTheme] paints a green outline on enabled and a
        // 2pt green one on focus, and leaving any state unset here lets that
        // green reappear on exactly one interaction.
        border: _outline(Ps.border),
        enabledBorder: _outline(Ps.border),
        focusedBorder: _outline(Ps.primary),
        disabledBorder: _outline(Ps.border),
      ),
    );
  }

  static OutlineInputBorder _outline(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        borderSide: BorderSide(color: color),
      );
}

/// The horizontal run of filter pills — "All / Team Sports / Racket Sports".
class PsFilterChips extends StatelessWidget {
  const PsFilterChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: Ps.gutter,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          return InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? Ps.primary : Ps.surface,
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(
                  color: isSelected ? Ps.primary : Ps.border,
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Ps.muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The small red "LIVE" flag on a match that is being played now.
class PsLivePill extends StatelessWidget {
  const PsLivePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Ps.live,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The filled action button — "Follow Club", "Next", "Create Tournament".
class PsPrimaryButton extends StatelessWidget {
  const PsPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = Ps.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Ps.border,
          disabledForegroundColor: Ps.faint,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The outlined counterpart — "Invite Members".
class PsSecondaryButton extends StatelessWidget {
  const PsSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Ps.ink,
          side: const BorderSide(color: Ps.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// The blue tick beside a verified club or player name.
class PsVerifiedTick extends StatelessWidget {
  const PsVerifiedTick({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.verified, size: size, color: const Color(0xFF2563EB));
  }
}

/// Formats a count the way the directory rows read it — "8,456", not "8456".
///
/// Uses a plain grouping rather than `NumberFormat.compact()`. Compact would
/// render 8,456 teams as "8.5K", and a club deciding whether a sport is worth
/// entering is reading these numbers against each other, where a rounded one
/// is worse than a long one.
String psGrouped(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// A scoring engine's counter key as a person reads it — `strikeRate` becomes
/// `Strike rate`.
///
/// One definition because the counters are the same numbers wherever they
/// appear: the career profile, the per-sport page, the stat breakdown, the
/// match centre and the tournament charts all name them, and a player
/// comparing their tournament board against their own profile must not find
/// the same figure called two things. It lived as five private copies that had
/// already drifted — two of them indexed `[0]` without checking the key was
/// non-empty, which throws rather than degrading — so this is also the fix for
/// that.
///
/// Deliberately mechanical rather than a lookup table. The engines declare
/// fifteen sports' vocabularies and gain more; a table would silently fall
/// back to a raw camelCase key for every counter nobody remembered to add,
/// which is worse than a plain transformation that is right for all of them.
String psHumanizeCounter(String key) {
  final spaced = key.replaceAllMapped(
    RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
    (_) => ' ',
  );
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}
