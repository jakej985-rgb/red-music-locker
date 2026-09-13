import 'package:flutter/widgets.dart';

/// Red Music Locker standardized spacing system.
abstract final class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  // --- Common Insets ---
  static const EdgeInsets pNone = EdgeInsets.zero;
  static const EdgeInsets pXs = EdgeInsets.all(xs);
  static const EdgeInsets pSm = EdgeInsets.all(sm);
  static const EdgeInsets pMd = EdgeInsets.all(md);
  static const EdgeInsets pLg = EdgeInsets.all(lg);
  static const EdgeInsets pXl = EdgeInsets.all(xl);
  static const EdgeInsets pXxl = EdgeInsets.all(xxl);

  // --- Symmetric ---
  static const EdgeInsets hXs = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets hSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets hMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets hLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets hXl = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets hXxl = EdgeInsets.symmetric(horizontal: xxl);

  static const EdgeInsets vXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets vSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets vMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets vLg = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets vXl = EdgeInsets.symmetric(vertical: xl);

  // --- Page Margins ---
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: xl, vertical: lg);
  static const EdgeInsets pageMobile = EdgeInsets.symmetric(horizontal: lg, vertical: md);

  // --- Card Padding ---
  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets cardDense = EdgeInsets.all(md);
}
