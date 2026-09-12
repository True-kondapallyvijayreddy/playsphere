import 'package:flutter/material.dart';

/// Android and iOS: there is no frame to put anything in.
///
/// Flutter has no built-in web view, and the project deliberately carries no
/// web-view package — adding one costs an Android and an iOS native
/// integration, a second rendering pipeline on the most memory-constrained
/// screen in the product, and a dependency whose whole purpose is to run
/// somebody else's code inside ours. On a phone the platform already has a
/// perfectly good YouTube app, and sending the viewer to it is both faster
/// and what they would have done anyway.
///
/// So this returns null, and every caller is written to have a real answer
/// for null — see `LiveStreamPanel`, which shows the poster frame and a play
/// button that opens the stream properly.
class InlineFrame {
  const InlineFrame._();

  /// Whether an inline frame can be rendered on this platform at all.
  static bool get isSupported => false;

  /// Null everywhere but the web.
  static Widget? build(String url, {String? title}) => null;
}
