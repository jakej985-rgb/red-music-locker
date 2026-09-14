# Red Music Locker — Migration & Refactoring Notes

This document captures the architectural decisions, refactored components, preserved contracts, and forward-looking cleanup items resulting from the UI redesign.

---

## 1. Major UI Changes

### A. Centralized Design System
- **Old State**: Ad-hoc color hex codes (`0xFF1E1E28`, `0xFF14141B`, `0xFF8A2387`, `0xFF0288D1`, `Colors.white`, `Colors.grey`, `Colors.redAccent`) scattered throughout view files; arbitrary padding values (e.g. 5, 7, 13, 23); disparate border radiuses.
- **New State**: Centralized token architecture in `app/lib/core/theme/`:
  - `AppColors`: Layered dark surface hierarchy (`background`, `surface`, `surfaceElevated`, `surfaceHover`), semantic colors (`success`, `warning`, `error`, `info`, `streaming`, `pending`).
  - `AppTypography`: Clear hierarchy (`h1`, `h2`, `h3`, `body`, `bodyBold`, `caption`, `label`, `mono`).
  - `AppSpacing`: Strict 4px/8px grid (`xxs` through `xxl`).
  - `AppRadius`: Consistent geometric corners (`rXs` through `rPill`).

### B. View Layout Modernization
- All 8 primary views (`DashboardView`, `LibraryView`, `UploadsView`, `PlaylistsView`, `QueueView`, `HistoryView`, `FamilyView`, `SettingsView`) updated to use `AppPageHeader` hero cards, consistent card elevations, and unified action bars.
- `PlaylistsView` completely purged of legacy hex colors, mapping surface backgrounds, elevated card containers, replica indicators, and action buttons to semantic tokens.
- `SettingsView` updated with responsive layout builders for mobile screens, ensuring account cards, folder paths, and action buttons stack gracefully.

### C. `MetadataEditorDialog` Overhaul
- Segmented into 4 explicit visual sections:
  1. `BASIC INFORMATION` (Title, Artist, Album)
  2. `TRACK INFORMATION` (Track Number, Disc Number, Year, Genre, Explicit flag)
  3. `ARTWORK` (Thumbnail preview, Attached/Auto-fetch status badges, File/URL/Fetch actions)
  4. `YOUTUBE MUSIC` (Provider chips, query search, online match candidates)
- Fully responsive across desktop (620px constrained modal) and mobile (<600px full-width/full-height modal with pinned scrollable actions and ellipsis truncation).

---

## 2. Extracted Shared Components

17 standardized components were established under `app/lib/shared/widgets/` and exported via `shared_widgets.dart`:
1. `AppPageHeader`
2. `AppSectionHeader`
3. `AppSearchBar`
4. `AppFilterBar`
5. `AppStatCard`
6. `AppStatusBadge`
7. `AppTrackRow`
8. `AppTrackGrid`
9. `AppPlaylistCard`
10. `AppAccountCard`
11. `AppActivityItem`
12. `AppProgressCard`
13. `AppSelectionToolbar`
14. `AppConfirmDialog`
15. `AppEmptyState`
16. `AppLoadingState`
17. `AppErrorState`

All components include dedicated widget unit and rendering tests under `app/test/shared_widgets_test.dart`.

---

## 3. Preserved Functionality & Invariants

Zero modifications were made to the underlying operational and communication logic:
- **Backend API Contract**: Unchanged. All endpoint URLs, JSON serialization schemas, and HTTP method expectations remain intact.
- **Authentication & OAuth**: Unchanged. Google OAuth tokens, cookies (`oauth.json`), session tokens, and header authorizations are preserved.
- **Upload Engine**: Unchanged. Chunked uploads, MIME validation, and retagging pipelines operate identically.
- **Matching Pipeline**: Unchanged. MusicBrainz, Deezer, and YouTube Music query parameters, scoring thresholds, and tag application rules remain untouched.
- **Queue Engine**: Unchanged. Background task concurrency, status polling, and retry mechanisms are unaffected.
- **Playlists & Replicas**: Unchanged. 1:1 playlist replication logic, track matching against cloud locker uploads, and sync routines operate exactly as designed.
- **Family Sync**: Unchanged. Multi-account credential handling and sync schedules remain identical.
- **Database & Schemas**: Unchanged. SQLite database tables, column definitions, and migrations have not been altered.

---

## 4. Known Limitations
- **External Web Font Loading**: When running offline or behind strict firewalls, Google Fonts may fall back to system sans-serif fonts.
- **Large Audio File Browser Uploads**: In Flutter Web release mode, uploading very large FLAC files (>100MB) depends on browser memory limits; backend native daemon mode remains recommended for large batch migrations.

---

## 5. Future Cleanup & Maintenance
- **Provider-Specific Theme Customization**: In future releases, users could be offered high-contrast or light theme toggles using the existing `ThemeData` architecture.
- **Audio Waveform Preview**: Potential enhancement to embed waveform audio visualizers in `AppTrackRow` during playback.
- **Keyboard Shortcut Expansion**: Add global keybindings for quick search (`/`), batch selection (`Ctrl+A`), and metadata save (`Ctrl+S`).
