# Red Music Locker — UI Redesign & Design System

## Overview & Purpose
Red Music Locker is a unified cloud music locker, matching, and playlist replication dashboard for YouTube Music. This redesign modernizes the user interface from legacy, fragmented styling into a cohesive, dark-first, accessible, and responsive design system inspired by premium audio platforms (Spotify, Apple Music, Tidal).

The redesign establishes a centralized design system, standardizes all interactive and status components, eliminates hard-coded hex colors and arbitrary spacing, and delivers an adaptive layout optimized for mobile phones (360px–430px), tablets (768px–1024px), and large desktop displays (1440px+).

---

## Design Goals
1. **Premium Dark Aesthetic**: Refined dark surface hierarchy (`#0B0B0F` background, `#141419` surface, `#1C1C23` elevated cards) with brand crimson accents (`#E50914`), eliminating harsh pure blacks or generic neon reds.
2. **Unified Design System**: Centralized design tokens across colors (`AppColors`), typography (`AppTypography`), spacing (`AppSpacing`), radii (`AppRadius`), and component themes (`AppTheme`).
3. **Responsive & Mobile-First**:
   - Dynamic shell adaptivity: Bottom `NavigationBar` on mobile viewports (<600px), collapsible side `NavigationRail` on tablet (600px–1024px), and expanded `NavigationRail` on desktop (>1024px).
   - Dialog resilience: Full-width/full-height adaptive presentation on narrow viewports with scrollable content and pinned accessible action bars.
   - 0 RenderFlex overflows across 360px, 390px, 430px, 768px, 1024px, and 1440px viewports.
4. **Zero Functionality Compromise**: Strict preservation of all backend API contracts, OAuth/token flows, background queue engines, upload matching pipelines, family sync, and playlist replica synchronization.
5. **Enhanced Accessibility**: High contrast semantic tokens, consistent focus indicators, accessible tap targets (min 48x48dp on touch devices), rich tooltip coverage, and color-independent status messaging.

---

## Current Status
- **Core Design System**: Complete (`AppColors`, `AppTypography`, `AppSpacing`, `AppRadius`, `AppTheme`).
- **Shared Component Library**: Complete (17 reusable, audited shared components exported via `shared_widgets.dart`).
- **View Implementations**: Complete across all 8 core views (Dashboard, Library, Uploads, Playlists, Queue, History, Family, Settings) + Metadata Editor Dialog.
- **Validation**:
  - `flutter analyze`: 0 issues found.
  - `flutter test`: 60/60 tests passing (100%).
  - `flutter build web --release`: Successful release build.

---

## Architecture Overview

```
app/lib/
├── core/
│   └── theme/
│       ├── app_colors.dart         # Semantic & surface color palette
│       ├── app_typography.dart     # Font scale, weights, letter-spacing
│       ├── app_spacing.dart        # 4px/8px grid scale & insets
│       ├── app_radius.dart         # Corner radius scales (xs to pill)
│       └── app_theme.dart          # Dark ThemeData integration
├── shared/
│   └── widgets/
│       ├── app_page_header.dart        # Hero headers with kickers & actions
│       ├── app_section_header.dart     # Sub-section divider headers
│       ├── app_search_bar.dart         # Debounced search input
│       ├── app_filter_bar.dart         # Categorical filter & pill chips
│       ├── app_stat_card.dart          # Metric summary cards with trends
│       ├── app_status_badge.dart       # Semantic pill badges (success/warn/err/info)
│       ├── app_track_row.dart          # Density-aware track list items
│       ├── app_track_grid.dart         # Responsive album art card grid
│       ├── app_playlist_card.dart      # Playlist cards with replica badges
│       ├── app_account_card.dart       # YTM account & session status cards
│       ├── app_activity_item.dart      # Audit log & activity feed rows
│       ├── app_progress_card.dart      # Live sync/upload progress card
│       ├── app_selection_toolbar.dart   # Batch selection actions bar
│       ├── app_confirm_dialog.dart     # Consistent modal confirmation dialogs
│       ├── app_empty_state.dart        # Illustrated empty view placeholders
│       ├── app_loading_state.dart      # Standardized loading spinners
│       ├── app_error_state.dart        # Detailed error states with retry
│       └── shared_widgets.dart         # Barrel export file
├── views/
│   ├── components/
│   │   └── metadata_editor_dialog.dart # Modal track tagger with MusicBrainz/Deezer
│   ├── dashboard_view.dart             # Metrics, quick actions, recent activity
│   ├── library_view.dart               # Local locker browsing, tagging, uploads
│   ├── uploads_view.dart               # Cloud locker sync, track replacements
│   ├── playlists_view.dart             # Playlist browser & 1:1 replica manager
│   ├── queue_view.dart                 # Real-time background upload queue
│   ├── history_view.dart               # Synchronized audit trail & log filters
│   ├── family_view.dart                # Multi-account playlist & family sync
│   └── settings_view.dart              # Multi-user accounts, auth, root dirs
└── main.dart                           # Responsive AppShell & routing
```

---

## Documentation Index
- [Design System Guide](design-system.md): Tokens, scales, palettes, typography, and theming rules.
- [Component Specifications](components.md): Comprehensive catalog of all 17 shared components, props, and usage guidelines.
- [Responsive Design Strategy](responsive-design.md): Breakpoint definitions, adaptive navigation patterns, and dialog sizing rules.
- [Page Guidelines & Hierarchy](page-guidelines.md): Visual hierarchies, layout structures, and action zones for each page.
- [Migration & Refactoring Notes](migration-notes.md): Details of legacy code replaced, invariants maintained, and future enhancements.
- [Implementation Status](implementation-status.md): Exact phase completion breakdown and verification audit.
