import 'package:flutter/material.dart';

import 'ui_kit.dart';

/// One step of a multi-step flow.
class WizardStep {
  const WizardStep({
    required this.title,
    required this.builder,
    this.subtitle,
    this.canAdvance,
  });

  /// The bold line under "Step 2 of 6" — "Select Sports", "Format".
  final String title;

  /// The grey line under the title, where a step needs explaining.
  final String? subtitle;

  final WidgetBuilder builder;

  /// Whether the Next button is enabled. Null means always.
  ///
  /// A predicate rather than a bool so it is re-evaluated on every rebuild —
  /// a step's validity changes as the person types in it, and a value
  /// captured when the step list was built would freeze at whatever was true
  /// before they started.
  final bool Function()? canAdvance;
}

/// The shell every creation flow in the product wears.
///
/// Four flows share it — season, tournament, single match, and the challenge
/// exchange — which is the whole reason it exists. They were specified as
/// four separate designs with the same chrome drawn four times, and four
/// copies of a stepper is four places for the back button to behave
/// differently.
///
/// ## What this does not own
///
/// State. The shell renders steps and moves between them; every flow keeps
/// its own form state in its own widget, because the flows have nothing in
/// common to hold. This is deliberately not a generic form engine.
class WizardScaffold extends StatefulWidget {
  const WizardScaffold({
    super.key,
    required this.title,
    required this.steps,
    required this.onSubmit,
    this.submitLabel = 'Create',
    this.submitting = false,
    this.onCancel,
  });

  /// The flow's name, shown small above the step title — "Create Tournament".
  final String title;

  final List<WizardStep> steps;

  /// Runs on the final step's button. The shell does not pop afterwards —
  /// where a finished flow goes is the flow's own decision.
  final Future<void> Function() onSubmit;

  /// The last step's button label — "Create Tournament", "Publish Season".
  final String submitLabel;

  /// Disables the footer and shows a spinner while a submit is in flight, so
  /// a slow network cannot produce two tournaments from one impatient
  /// double-tap.
  final bool submitting;

  /// What the back arrow does on the first step. Defaults to popping.
  final VoidCallback? onCancel;

  @override
  State<WizardScaffold> createState() => _WizardScaffoldState();
}

class _WizardScaffoldState extends State<WizardScaffold> {
  int _index = 0;

  bool get _isLast => _index == widget.steps.length - 1;

  void _back() {
    if (_index == 0) {
      (widget.onCancel ?? () => Navigator.of(context).maybePop()).call();
      return;
    }
    setState(() => _index--);
  }

  Future<void> _next() async {
    if (_isLast) {
      await widget.onSubmit();
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    // Clamped rather than indexed directly: a flow whose step list shortens
    // between builds — a season that drops its venue step when the organizer
    // unticks every sport — would otherwise index past the end.
    final index = _index.clamp(0, widget.steps.length - 1);
    final step = widget.steps[index];
    final canAdvance = step.canAdvance?.call() ?? true;

    return PopScope(
      // The shell handles back itself so the hardware button walks the steps
      // instead of abandoning a half-filled form on the first press.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Ps.canvas,
        appBar: AppBar(
          backgroundColor: Ps.surface,
          foregroundColor: Ps.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Ps.ink),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: index == 0 ? 'Cancel' : 'Previous step',
            onPressed: widget.submitting ? null : _back,
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Step ${index + 1} of ${widget.steps.length}',
                style: const TextStyle(fontSize: 11.5, color: Ps.muted),
              ),
              const SizedBox(height: 2),
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StepDots(
                count: widget.steps.length,
                index: index,
                onTap: widget.submitting
                    // Backwards only. Jumping forward past a step would skip
                    // whatever that step was collecting, and the flows behind
                    // this shell have required fields.
                    ? null
                    : (i) => i < index ? setState(() => _index = i) : null,
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (step.subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    step.subtitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [step.builder(context)],
                ),
              ),
              _Footer(
                label: _isLast ? widget.submitLabel : 'Next',
                // The final action is green in the sample designs and stays
                // green here: it is the one press in the flow that creates
                // something other people will see.
                color: _isLast ? const Color(0xFF16A34A) : Ps.primary,
                enabled: canAdvance && !widget.submitting,
                busy: widget.submitting,
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The numbered progress row. The current step is a filled circle carrying
/// its number; the rest are hairline circles.
class _StepDots extends StatelessWidget {
  const _StepDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final void Function(int)? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final isCurrent = i == index;
          final isDone = i < index;
          return Semantics(
            label: 'Step ${i + 1} of $count',
            selected: isCurrent,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              customBorder: const CircleBorder(),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent || isDone ? Ps.primary : Ps.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCurrent || isDone ? Ps.primary : Ps.border,
                  ),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isCurrent || isDone ? Colors.white : Ps.muted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.label,
    required this.color,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Ps.surface,
        border: Border(top: BorderSide(color: Ps.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
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
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A labelled field, as every step of every flow draws one.
class WizardField extends StatelessWidget {
  const WizardField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
  });

  final String label;
  final Widget child;

  /// Renders the red asterisk the sample designs put on mandatory fields.
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Ps.ink,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Ps.live),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// A switch row, as the Settings steps are built from.
class WizardToggle extends StatelessWidget {
  const WizardToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.help,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Ps.ink,
                  ),
                ),
                if (help != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    help!,
                    style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Ps.primary,
          ),
        ],
      ),
    );
  }
}

/// One line of a review summary — "Sport ......... Cricket".
class WizardReviewRow extends StatelessWidget {
  const WizardReviewRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Ps.muted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Ps.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
