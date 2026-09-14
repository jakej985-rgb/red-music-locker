# Red Music Locker — Design System Specification

## 1. Color Palette (`AppColors`)

Red Music Locker uses a dark-first, modern streaming service color palette. Harsh pure blacks (`#000000`) and uncalibrated saturated primaries are avoided in favor of layered, warm-tinted dark surfaces with calibrated brand accents.

### Surface Hierarchy
| Token | Hex Value | Semantic Usage |
| :--- | :--- | :--- |
| `AppColors.background` | `#0B0B0F` | Global canvas background behind navigation and content views |
| `AppColors.surface` | `#141419` | Default card backgrounds, search bars, inputs, list row backgrounds |
| `AppColors.surfaceElevated` | `#1C1C23` | Dialogs, elevated sheets, modals, popovers, hover card states |
| `AppColors.surfaceHover` | `#24242E` | Hover highlight for interactive items, list row hover states |
| `AppColors.surfaceSubtle` | `#181820` | Secondary grouping containers, table header bars, chip fills |

### Brand & Accents
| Token | Hex Value | Semantic Usage |
| :--- | :--- | :--- |
| `AppColors.primary` | `#E50914` | Brand crimson accent for primary CTA buttons, active tabs, progress |
| `AppColors.primaryLight` | `#FF3B30` | Hover states on primary buttons and high-visibility badges |
| `AppColors.primaryDark` | `#B80710` | Pressed states and high-contrast accents |
| `AppColors.primaryMuted` | `#33E50914` | 20% alpha background tints behind crimson icons and badges |

### Text & Typography Colors
| Token | Hex Value | Semantic Usage |
| :--- | :--- | :--- |
| `AppColors.textPrimary` | `#F4F4F6` | High-contrast body text, primary titles, input values |
| `AppColors.textSecondary` | `#A1A1AA` | Secondary descriptions, column headers, metadata tags |
| `AppColors.textMuted` | `#71717A` | Captions, placeholders, disabled states, timestamps |
| `AppColors.textDisabled` | `#52525B` | Non-interactive text, inactive button labels |

### Borders & Dividers
| Token | Hex Value | Semantic Usage |
| :--- | :--- | :--- |
| `AppColors.border` | `#27272A` | Card outlines, active input borders, dialog borders |
| `AppColors.borderSubtle` | `#1E1E24` | Subtle separators between list items, passive field borders |
| `AppColors.divider` | `#22222A` | Visual rule separators, split view dividers |

### Semantic Status Tokens
| State | Color Token | Hex | Background Tint (`Bg`) | Alpha Hex |
| :--- | :--- | :--- | :--- | :--- |
| **Success** | `AppColors.success` | `#10B981` | `AppColors.successBg` | `#2610B981` (15%) |
| **Warning** | `AppColors.warning` | `#F59E0B` | `AppColors.warningBg` | `#26F59E0B` (15%) |
| **Error** | `AppColors.error` | `#EF4444` | `AppColors.errorBg` | `#26EF4444` (15%) |
| **Info / YTM** | `AppColors.info` | `#3EA6FF` | `AppColors.infoBg` | `#263EA6FF` (15%) |
| **Streaming** | `AppColors.streaming` | `#8B5CF6` | `AppColors.streamingBg` | `#268B5CF6` (15%) |
| **Pending** | `AppColors.pending` | `#6B7280` | `AppColors.pendingBg` | `#266B7280` (15%) |

---

## 2. Typography Scale (`AppTypography`)

The typography system relies on clean sans-serif geometry with calibrated line heights, font weights, and letter-spacings.

| Style Token | Size | Weight | Tracking / Letter Spacing | Usage |
| :--- | :--- | :--- | :--- | :--- |
| `AppTypography.h1` | 24px | Bold (`w700`) | `-0.5px` | Hero view headings (`AppPageHeader`) |
| `AppTypography.h2` | 18px | SemiBold (`w600`) | `-0.2px` | Section titles, modal headers |
| `AppTypography.h3` | 15px | SemiBold (`w600`) | `0.0px` | Card headers, table subheaders |
| `AppTypography.body` | 13px | Regular (`w400`) | `0.0px` | Primary body text, descriptions |
| `AppTypography.bodyBold` | 13px | SemiBold (`w600`) | `0.0px` | Emphasized body text, list item titles |
| `AppTypography.caption` | 11px | Regular (`w400`) | `0.2px` | Metadata lines, secondary badges, timestamps |
| `AppTypography.label` | 10px | Bold (`w700`) | `1.0px` (Uppercase) | Section category kickers, badge text |
| `AppTypography.mono` | 12px | Regular (`w400`) | `0.0px` | IDs, file hashes, paths, technical logs |

---

## 3. Spacing Grid (`AppSpacing`)

The spacing system follows a strict 4px/8px grid scale to maintain consistent rhythm and alignment across all layouts.

| Token | Dimension | Intended Usage |
| :--- | :--- | :--- |
| `AppSpacing.xxs` | 2.0px | Micro-spacers between icon and compact badge text |
| `AppSpacing.xs` | 4.0px | Tight gaps, vertical margins between label and input |
| `AppSpacing.sm` | 8.0px | Gaps between related buttons, list row inner spacing |
| `AppSpacing.md` | 16.0px | Standard padding within cards, container margins |
| `AppSpacing.lg` | 24.0px | Page margin gutters on mobile, gaps between card blocks |
| `AppSpacing.xl` | 32.0px | Page margin gutters on desktop, hero header bottom margins |
| `AppSpacing.xxl` | 48.0px | Major section breaks, empty state vertical margins |

### Composite Inset Presets
- `AppSpacing.page` -> `EdgeInsets.all(AppSpacing.lg)` (24px) on desktop, `AppSpacing.md` (16px) on mobile.
- `AppSpacing.card` -> `EdgeInsets.all(AppSpacing.md)` (16px).
- `AppSpacing.button` -> `EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0)`.

---

## 4. Corner Radius (`AppRadius`)

Consistent rounding softens the interface while maintaining crisp, structured bounds.

| Token | Radius Value | Corner Preset | Typical Usage |
| :--- | :--- | :--- | :--- |
| `AppRadius.xs` | 4.0px | `AppRadius.rXs` | Micro-badges, album art in compact lists |
| `AppRadius.sm` | 8.0px | `AppRadius.rSm` | Buttons, text fields, search inputs, dropdowns |
| `AppRadius.md` | 12.0px | `AppRadius.rMd` | Standard cards (`AppStatCard`, `AppAccountCard`) |
| `AppRadius.lg` | 16.0px | `AppRadius.rLg` | Modal dialogs, bottom sheets |
| `AppRadius.xl` | 20.0px | `AppRadius.rXl` | Selected provider chips, floating toolbars |
| `AppRadius.pill` | 999.0px | `AppRadius.rPill` | Filter pills, status badges (`AppStatusBadge`) |

---

## 5. Theme Behavior

### Dark Theme Integration (`AppTheme.darkTheme`)
- The application enforces a calibrated dark theme by default.
- Built-in Flutter Material 3 widgets (`ElevatedButton`, `OutlinedButton`, `FilledButton`, `TextField`, `Card`, `Dialog`, `NavigationBar`, `NavigationRail`) automatically inherit `AppColors` tokens through `ThemeData`:
  - `scaffoldBackgroundColor`: `AppColors.background`
  - `cardColor`: `AppColors.surface`
  - `colorScheme`: Custom Dark `ColorScheme` with `primary: AppColors.primary`, `surface: AppColors.surface`, `error: AppColors.error`.
  - `dividerTheme`: `color: AppColors.divider`, `thickness: 1`.
  - `dialogTheme`: `backgroundColor: AppColors.surfaceElevated`, `shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog)`.

---

## 6. Component Usage Rules
1. **Never use raw Flutter colors directly**: Avoid `Colors.red`, `Colors.white`, `Colors.grey`, `Color(0xFF...)` for visual elements. Always reference `AppColors.*`.
2. **Never hard-code raw margin numbers**: Use `AppSpacing.sm`, `AppSpacing.md`, etc., to preserve grid alignment.
3. **Never apply ad-hoc border radii**: Use `AppRadius.button`, `AppRadius.card`, `AppRadius.dialog`, or `AppRadius.badge`.
4. **Use semantic badges for state**: Use `AppStatusBadge` instead of custom colored `Container`s for statuses like "Synced", "Error", "Pending", "Matched".
