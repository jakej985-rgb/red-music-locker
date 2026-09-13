import 'package:flutter/material.dart';

/// Red Music Locker centralized color design system.
/// Dark-first aesthetic with refined hierarchy, subtle surfaces, and brand crimson accents.
abstract final class AppColors {
  // --- Backgrounds & Surfaces ---
  static const Color background = Color(0xFF0B0B0F);
  static const Color surface = Color(0xFF141419);
  static const Color surfaceElevated = Color(0xFF1C1C23);
  static const Color surfaceHover = Color(0xFF24242E);
  static const Color surfaceSubtle = Color(0xFF181820);

  // --- Brand & Accents ---
  static const Color primary = Color(0xFFE50914);
  static const Color primaryLight = Color(0xFFFF3B30);
  static const Color primaryDark = Color(0xFFB80710);
  static const Color primaryMuted = Color(0x33E50914);

  // --- Text Hierarchies ---
  static const Color textPrimary = Color(0xFFF4F4F6);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF71717A);
  static const Color textDisabled = Color(0xFF52525B);

  // --- Borders & Dividers ---
  static const Color border = Color(0xFF27272A);
  static const Color borderSubtle = Color(0xFF1E1E24);
  static const Color divider = Color(0xFF22222A);

  // --- Semantic & Status Colors ---
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0x2610B981);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0x26F59E0B);

  static const Color error = Color(0xFFEF4444);
  static const Color errorBg = Color(0x26EF4444);

  static const Color info = Color(0xFF3EA6FF);
  static const Color infoBg = Color(0x263EA6FF);

  static const Color streaming = Color(0xFF8B5CF6);
  static const Color streamingBg = Color(0x268B5CF6);

  static const Color pending = Color(0xFF6B7280);
  static const Color pendingBg = Color(0x266B7280);
}
