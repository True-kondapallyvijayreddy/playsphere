import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// The web half: a real `<iframe>`, sitting inside the Flutter tree.
///
/// ## Why this is hand-rolled and not a package
///
/// An embedded player on the web is one platform view and about twenty lines
/// of it. `ui_web.platformViewRegistry` is the documented way to put a DOM
/// element into a Flutter widget, and `package:web` is the maintained
/// binding — both are already on the dependency graph. A YouTube-player
/// package, by contrast, would have to be carried on Android and iOS where it
/// cannot be used (see the stub beside this file), for one rectangle.
///
/// ## Why the URL is not the view type
///
/// A view type is registered once per string and is never unregistered, so
/// keying it on the URL would leak one registration per stream link the
/// session ever saw. The registration is per-URL but memoised, which is the
/// same trade every implementation of this makes and the reason a match whose
/// organizer corrects a typo'd link renders the corrected one.
class InlineFrame {
  const InlineFrame._();

  static bool get isSupported => true;

  static final _registered = <String>{};

  static Widget? build(String url, {String? title}) {
    final viewType = 'ps-frame-${url.hashCode}';
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final frame = web.document.createElement('iframe')
            as web.HTMLIFrameElement;
        frame.src = url;
        frame.title = title ?? 'Embedded player';
        frame.style.border = 'none';
        frame.style.width = '100%';
        frame.style.height = '100%';
        // The exact set YouTube's own embed code ships with, minus
        // autoplay: a scoreboard page that starts making noise on its own is
        // the fastest way to be closed.
        frame.setAttribute(
          'allow',
          'accelerometer; clipboard-write; encrypted-media; gyroscope; '
              'picture-in-picture; web-share',
        );
        frame.setAttribute('allowfullscreen', 'true');
        // The frame runs somebody else's page. It gets what a video player
        // needs and nothing that would let it reach back into the app that
        // is hosting it.
        frame.setAttribute(
          'sandbox',
          'allow-scripts allow-same-origin allow-presentation allow-popups',
        );
        frame.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
        return frame;
      });
    }
    return HtmlElementView(viewType: viewType);
  }
}
