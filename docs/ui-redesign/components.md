# Red Music Locker — Shared Components Catalog

The redesign introduces 17 centralized, reusable components located in `app/lib/shared/widgets/` and exported via `shared_widgets.dart`. All components strictly conform to the `AppColors`, `AppTypography`, `AppSpacing`, and `AppRadius` design tokens.

---

## Component Index

| # | Component | Primary Purpose | Primary Locations |
| :--- | :--- | :--- | :--- |
| 1 | `AppPageHeader` | Standardized page hero section with title, kicker, subtitle, and action buttons | All 8 Views (Dashboard, Library, Uploads, Playlists, Queue, History, Family, Settings) |
| 2 | `AppSectionHeader` | Content section divider with title, icon, and optional trailing controls | DashboardView, PlaylistsView, SettingsView |
| 3 | `AppSearchBar` | Standard search field with icon, clear button, and debouncing | LibraryView, UploadsView, PlaylistsView, HistoryView |
| 4 | `AppFilterBar` | Horizontal scrollable filter pills for categorical filtering | LibraryView, UploadsView, HistoryView |
| 5 | `AppStatCard` | KPI metric summary card with icon, count, label, and trend indicators | DashboardView, UploadsView, PlaylistsView |
| 6 | `AppStatusBadge` | Semantic status pill indicator (success, warning, error, info, neutral) | Track lists, queue items, sync states, replica badges |
| 7 | `AppTrackRow` | Dense or standard list tile for music tracks with art, artist, and actions | LibraryView, UploadsView, PlaylistsView, QueueView |
| 8 | `AppTrackGrid` | Multi-column responsive album art grid for visual browsing | LibraryView, PlaylistsView |
| 9 | `AppPlaylistCard` | Cover grid, track count, owner, and replica sync state card | PlaylistsView, FamilyView |
| 10 | `AppAccountCard` | Multi-user session & Google/YTM account connection card | SettingsView, FamilyView |
| 11 | `AppActivityItem` | Activity log item with timestamp, action icon, and status badge | DashboardView, HistoryView |
| 12 | `AppProgressCard` | Live upload/sync progress indicator with animated bar & cancel | QueueView, DashboardView |
| 13 | `AppSelectionToolbar` | Floating or docked batch selection toolbar with bulk actions | LibraryView, UploadsView, PlaylistsView |
| 14 | `AppConfirmDialog` | Standardized confirmation dialog for destructive or critical actions | Deleting playlists, unlinking accounts, removing tracks |
| 15 | `AppEmptyState` | Responsive empty placeholder with icon, message, and call to action | All views when data collections are empty |
| 16 | `AppLoadingState` | Consistent centered spinner with optional loading message | Initial page load and async fetching across all views |
| 17 | `AppErrorState` | Expandable error box with technical details and retry callback | Network failure, API errors across all views |

---

## Detailed Component Specifications

### 1. `AppPageHeader`
- **File**: `app_page_header.dart`
- **Props**:
  - `title`: `String` (required)
  - `kicker`: `String?` (uppercase small category label)
  - `subtitle`: `String?` (explanatory context)
  - `actions`: `List<Widget>?` (trailing action buttons)
- **Usage Rule**: Must be placed as the first child of the main page scroll/column. On mobile (<600px), title and actions wrap cleanly without clipping.

### 2. `AppSectionHeader`
- **File**: `app_section_header.dart`
- **Props**: `title`, `icon`, `subtitle`, `action`
- **Usage Rule**: Use to segment discrete areas within a view (e.g. "Recently Played", "Quick Actions", "Replica Playlists").

### 3. `AppSearchBar`
- **File**: `app_search_bar.dart`
- **Props**: `hintText`, `onChanged`, `onSubmitted`, `controller`
- **Usage Rule**: Always set a meaningful placeholder (e.g., `"Filter tracks by title, artist, or album..."`). Includes built-in clear button when text is present.

### 4. `AppFilterBar`
- **File**: `app_filter_bar.dart`
- **Props**: `categories`, `selectedCategory`, `onSelected`
- **Usage Rule**: Uses `AppRadius.badge` pill shape. Highlights active category with `AppColors.primary` and inactive with `AppColors.surface`.

### 5. `AppStatCard`
- **File**: `app_stat_card.dart`
- **Props**: `title`, `value`, `icon`, `trend`, `color`, `onTap`
- **Usage Rule**: Renders within a responsive grid/wrap. Displays numeric counts prominently with muted label beneath.

### 6. `AppStatusBadge`
- **File**: `app_status_badge.dart`
- **Props**: `label`, `status` (`AppStatusType.success`, `.warning`, `.error`, `.info`, `.neutral`)
- **Usage Rule**: Combines color and text to satisfy color-blind accessibility. Never communicate status through color alone.

### 7. `AppTrackRow`
- **File**: `app_track_row.dart`
- **Props**: `track`, `index`, `isSelected`, `onTap`, `onSelect`, `actions`, `isDense`
- **Usage Rule**: Supports album art with fallback placeholder, title truncation, hover highlight (`AppColors.surfaceHover`), and popup menu actions.

### 8. `AppTrackGrid`
- **File**: `app_track_grid.dart`
- **Props**: `tracks`, `onTrackTap`, `onTrackEdit`
- **Usage Rule**: Use in Library and Playlists when the user toggles from list to grid view mode. Automatically adjusts column count based on available viewport width.

### 9. `AppPlaylistCard`
- **File**: `app_playlist_card.dart`
- **Props**: `playlist`, `isReplica`, `replicaStatus`, `onTap`, `onReplicate`
- **Usage Rule**: Shows 2x2 cover montage or default playlist graphic, track count badge, and a replica sync status badge when replicated.

### 10. `AppAccountCard`
- **File**: `app_account_card.dart`
- **Props**: `username`, `email`, `role`, `ytmStatus`, `onEdit`, `onRelink`, `onDelete`
- **Usage Rule**: Displays user avatar or initials, session role, YTM connection health status, and quick action buttons for relinking and profile updates.

### 11. `AppActivityItem`
- **File**: `app_activity_item.dart`
- **Props**: `title`, `subtitle`, `timestamp`, `icon`, `status`
- **Usage Rule**: Use in activity audit feeds. Provides compact layout with relative timestamp formatting (e.g., "5m ago").

### 12. `AppProgressCard`
- **File**: `app_progress_card.dart`
- **Props**: `title`, `progress` (0.0 to 1.0), `statusText`, `onCancel`
- **Usage Rule**: Renders progress bar with `AppColors.primary`, percentage text, and an optional cancellation button.

### 13. `AppSelectionToolbar`
- **File**: `app_selection_toolbar.dart`
- **Props**: `selectedCount`, `actions`, `onClearSelection`
- **Usage Rule**: Appears when 1 or more items are selected. Floats at the bottom or top with elevated backdrop (`AppColors.surfaceElevated`) and batch actions.

### 14. `AppConfirmDialog`
- **File**: `app_confirm_dialog.dart`
- **Props**: `title`, `message`, `confirmLabel`, `cancelLabel`, `isDestructive`, `onConfirm`
- **Usage Rule**: Used for all confirmation interactions. If `isDestructive` is true, the confirm button uses `AppColors.error`.

### 15. `AppEmptyState`
- **File**: `app_empty_state.dart`
- **Props**: `icon`, `title`, `description`, `actionLabel`, `onAction`, `customAction`
- **Usage Rule**: Wrapped in a `SingleChildScrollView` to prevent keyboard or small-screen overflow.

### 16. `AppLoadingState`
- **File**: `app_loading_state.dart`
- **Props**: `message`
- **Usage Rule**: Use while data fetching is unresolved. Centers a branded crimson `CircularProgressIndicator`.

### 17. `AppErrorState`
- **File**: `app_error_state.dart`
- **Props**: `message`, `details`, `onRetry`
- **Usage Rule**: Displays friendly error message with collapsible technical error stack and a "Try Again" retry button.
