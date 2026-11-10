# Palette's Journal - Critical Learnings Only

## 2025-05-18 - Destructive Confirmation Dialog Accessibility & Focus Safety
**Learning:** In Flutter web/desktop dialogs (`AlertDialog`), screen readers require `semanticLabel` set on the dialog root to announce the modal's purpose, and keyboard users risk triggering destructive actions if focus is unset or placed on the confirm button by default.
**Action:** When creating reusable confirmation dialogs like `AppConfirmDialog`, set `semanticLabel: title` on `AlertDialog` and `autofocus: true` on the cancel button whenever `isDestructive` is true.
