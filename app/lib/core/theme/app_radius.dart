import 'package:flutter/widgets.dart';

/// Red Music Locker corner radius constants.
abstract final class AppRadius {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double pill = 999.0;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));

  // --- Specific Component Presets ---
  static const BorderRadius card = rMd;
  static const BorderRadius button = rSm;
  static const BorderRadius input = rSm;
  static const BorderRadius badge = rPill;
  static const BorderRadius dialog = rLg;
}
