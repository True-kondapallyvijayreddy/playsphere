import 'package:flutter/material.dart';

/// Guards the last back press in the app.
///
/// At the root of the stack there is nothing to pop, so Android's back
/// gesture closes PlaySphere. That is the correct behaviour — an app that
/// cannot be left is worse than one that leaves too easily — but it should be
/// a decision rather than an accident, and it should never be reached from a
/// screen the person only meant to back out of. Everywhere else in the app
/// now pushes rather than replacing, so by the time this fires the person
/// really is at home with nowhere further back to go.
///
/// Two presses inside [window], the second confirming the first. Deliberately
/// not a dialog: a dialog on the way out is one more thing to dismiss, and on
/// a cheap phone it is a frame the person is already swiping through.
class ConfirmExit extends StatefulWidget {
  const ConfirmExit({
    super.key,
    required this.child,
    this.message = 'Press back again to leave PlaySphere',
    this.window = const Duration(seconds: 2),
  });

  final Widget child;
  final String message;
  final Duration window;

  @override
  State<ConfirmExit> createState() => _ConfirmExitState();
}

class _ConfirmExitState extends State<ConfirmExit> {
  DateTime? _armedAt;

  bool get _armed {
    final at = _armedAt;
    return at != null && DateTime.now().difference(at) < widget.window;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Read at the moment of the gesture, which is what makes the two-press
      // pattern work without ever calling SystemNavigator.pop ourselves:
      // while disarmed the framework hands the press here instead of popping;
      // once armed it pops normally, and popping the root route is what
      // "leave the app" means on each platform. Doing it by hand would
      // background the app on Android and do nothing coherent on the web,
      // and this screen runs on both.
      canPop: _armed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _armedAt = DateTime.now());
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(widget.message),
              duration: widget.window,
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      child: widget.child,
    );
  }
}
