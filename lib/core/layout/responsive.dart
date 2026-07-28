import 'package:flutter/material.dart';

/// One layout vocabulary shared by every screen, so Android, iOS and the web
/// build stay the same product rather than three that drifted apart.
///
/// Breakpoints follow Material 3 window size classes. They are expressed in
/// logical pixels and deliberately ignore the platform: a Chromebook at 900pt
/// and an iPad at 900pt get the identical layout, which is exactly the parity
/// a school needs when the coach is on a phone and the office is on a laptop.
enum WindowSize {
  /// Phones in portrait. Single column, bottom navigation, full-screen detail.
  compact,

  /// Large phones in landscape, small tablets. Single column with a rail.
  medium,

  /// Tablets in landscape, laptops, desktops. Two-pane, persistent sidebar.
  expanded;

  static const double mediumMin = 600;
  static const double expandedMin = 1024;

  static WindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width >= expandedMin) return WindowSize.expanded;
    if (width >= mediumMin) return WindowSize.medium;
    return WindowSize.compact;
  }

  bool get isCompact => this == WindowSize.compact;
  bool get isExpanded => this == WindowSize.expanded;

  /// True where a persistent side navigation is shown instead of a drawer.
  bool get hasPersistentNav => this != WindowSize.compact;

  /// True where a list and its detail can sit side by side.
  bool get supportsTwoPane => this == WindowSize.expanded;
}

extension ResponsiveContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(this);
  bool get isCompact => windowSize.isCompact;
  bool get isExpanded => windowSize.isExpanded;

  /// Picks one of three values by window size, falling back to the next
  /// smaller definition. Keeps per-widget breakpoint logic to one line.
  T responsive<T>({required T compact, T? medium, T? expanded}) {
    switch (windowSize) {
      case WindowSize.compact:
        return compact;
      case WindowSize.medium:
        return medium ?? compact;
      case WindowSize.expanded:
        return expanded ?? medium ?? compact;
    }
  }
}

/// Caps line length on wide screens. Text spanning a 27-inch monitor is
/// unreadable, so content centres inside a maximum width while still
/// stretching edge to edge on a phone.
class ContentBounds extends StatelessWidget {
  const ContentBounds({
    super.key,
    required this.child,
    this.maxWidth = 1180,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ??
              EdgeInsets.symmetric(
                horizontal: context.responsive(compact: 16, medium: 24, expanded: 32),
                vertical: 16,
              ),
          child: child,
        ),
      ),
    );
  }
}

/// A grid whose column count follows the window size rather than a fixed
/// number, so KPI tiles reflow from 1-up on a phone to 4-up on a laptop
/// without any screen needing its own LayoutBuilder.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 240,
    this.spacing = 12,
    this.childAspectRatio = 1.6,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: childAspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

/// Side-by-side list/detail on a laptop, stacked navigation on a phone.
///
/// The caller supplies both panes; on compact windows only [list] renders and
/// tapping through is expected to push a route instead. This keeps deep links
/// working identically on every platform.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.list,
    required this.detail,
    this.listFlex = 2,
    this.detailFlex = 3,
  });

  final Widget list;
  final Widget detail;
  final int listFlex;
  final int detailFlex;

  @override
  Widget build(BuildContext context) {
    if (!context.windowSize.supportsTwoPane) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: listFlex, child: list),
        const VerticalDivider(width: 1),
        Expanded(flex: detailFlex, child: detail),
      ],
    );
  }
}
