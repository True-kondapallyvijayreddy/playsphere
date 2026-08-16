import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The heading above a run of cards: what this block is, and why it is here.
///
/// Lives in shared rather than on the home screen because the same three
/// sections — live, waiting on you, what is coming up — are rendered on more
/// than one screen now that pending actions moved to Notifications.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;

  /// Optional, and increasingly absent. A heading reading `Your clubs` with
  /// `Open for entries, scheduled, or being played` under it is naming the
  /// same list twice; the second naming was there to justify the block to a
  /// first-time visitor and is read by nobody thereafter. Sections that carry
  /// a genuinely non-obvious qualifier keep it.
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// An empty state, with a way out of it.
class QuietCard extends StatelessWidget {
  const QuietCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;

  /// Optional. Worth writing when it tells the reader something the title
  /// cannot — why the list is empty, or what fills it. Not worth writing when
  /// it narrates the button underneath it, which is what most of these were
  /// doing: "Create one — pick a sport, set the age category, and open
  /// entries" above a button reading `Create an event`.
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.hintColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: theme.textTheme.bodySmall),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// "Today, 4:30 pm" rather than a date nobody reads.
String friendlyDate(DateTime when) {
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = day.difference(today).inDays;

  final time = DateFormat.jm().format(when);
  return switch (delta) {
    0 => 'Today, $time',
    1 => 'Tomorrow, $time',
    -1 => 'Yesterday, $time',
    _ => DateFormat('d MMM').format(when),
  };
}

/// "2h ago" rather than a clock time — what an activity feed needs and a
/// scheduled fixture does not, because a feed item is read a while after it
/// happened and its age is the fact worth leading with.
String relativeTime(DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inSeconds < 60) return 'Just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return DateFormat('d MMM').format(when);
}
