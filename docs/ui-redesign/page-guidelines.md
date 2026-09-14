# Red Music Locker — Page Guidelines & Visual Hierarchy

This document outlines the visual structure, layout hierarchy, and functional zones for each of the 8 primary views in the application.

---

## 1. Dashboard (`DashboardView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with kicker `"OVERVIEW & STATUS"`, title `"DASHBOARD"`, and quick actions ("Trigger Scan", "Process Queue").
  2. **Metrics Grid**: Responsive grid of `AppStatCard` items:
     - Local Library Count
     - Cloud Uploaded Tracks
     - Active Playlists
     - Pending Upload Queue
  3. **Real-time Status Banner**: Dynamic banner indicating current background sync state or active upload task.
  4. **Quick Navigation Cards**: Two-column split cards directing to "Uploads Manager" and "Playlist Replicas".
  5. **Recent Activity Feed**: Segmented `AppSectionHeader` followed by recent `AppActivityItem` rows.

---

## 2. Music Library (`LibraryView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with title `"MUSIC LIBRARY"`, track count subtitle, view toggle (List vs. Grid), and "Scan Folder" CTA.
  2. **Filter & Search Bar**: Integrated `AppSearchBar` coupled with `AppFilterBar` for filtering by genre, format (FLAC, MP3), or upload status.
  3. **Batch Selection Bar**: Floating `AppSelectionToolbar` visible when tracks are checked, offering "Upload Selected" and "Edit Metadata".
  4. **Content Canvas**:
     - *List Mode*: Scrollable list of `AppTrackRow` items with artwork thumbnails, title/artist, duration, format badge, and inline metadata edit button.
     - *Grid Mode*: Multi-column `AppTrackGrid` displaying high-res album cards.
  5. **Empty State**: `AppEmptyState` with scan button when no audio files are found in configured music root.

---

## 3. Uploads Manager (`UploadsView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with kicker `"CLOUD UPLOADS REPOSITORY"`, title `"YOUTUBE MUSIC"`, total synced count, and refresh button.
  2. **Search & Pagination Controls**: Filter input, sort dropdown (Title, Artist, Date Added), and page-size selector.
  3. **Uploads Table / List**:
     - Each entry displays cloud track title, artist, album, and a contextual status badge.
     - Action menu provides: "Retag & Replace on YTM", "Download Audio", "Find Online Match", "Delete from Locker".
  4. **Paginator Bar**: Previous/Next navigation and current page indicator.

---

## 4. Playlists & Replicas (`PlaylistsView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with title `"YTM PLAYLISTS"`, subtitle explaining 1:1 replication, and buttons for "Replicas Overview" and "Import Playlist".
  2. **Filter & Search Bar**: Quick search for playlist names.
  3. **Playlists Grid / Split View**:
     - Standard playlists displayed using `AppPlaylistCard`.
     - 1:1 Replicas clearly distinguished with `AppColors.info` border and "REPLICA" status badge.
  4. **Playlist Detail Modal / Panel**:
     - Shows track list comparison between the original playlist and the replica.
     - Identifies matched, missing, or cloud-uploaded tracks.
     - "Sync Replica" button to trigger automated reconciliation.

---

## 5. Upload Queue (`QueueView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with title `"Queue"`, active worker status, and controls ("Pause Queue", "Clear Completed").
  2. **Active Upload Progress**: Prominent `AppProgressCard` showing current uploading file, upload percentage, throughput speed, and cancel button.
  3. **Pending Queue Items**: Reorderable list of upcoming tracks waiting for upload or tag processing.
  4. **Completed / Failed Items**: Collapsible section showing recently finished uploads and error diagnostics with retry buttons.

---

## 6. History & Activity (`HistoryView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with title `"Upload History & Activity"`, log summary, and "Export Audit Log" action.
  2. **Filter Bar**: `AppFilterBar` allowing filtering by action type ("All", "Uploads", "Matches", "Replaced", "Errors").
  3. **Activity Timeline**: Chronological stream of `AppActivityItem` widgets displaying timestamps, affected track names, operator/user, and outcome status.

---

## 7. Family Mode (`FamilyView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with title `"Family Mode"`, multi-account synchronization description, and "Add Member" button.
  2. **Connected Family Accounts**: Horizontal or grid cards (`AppAccountCard`) showing each family member's linked Google/YTM account and token status.
  3. **Cross-Account Sync Rules**: Configuration cards for shared playlists, mirror playlists, and auto-sync intervals.
  4. **Sync Actions**: "Sync All Accounts Now" primary action button.

---

## 8. Settings & Configuration (`SettingsView`)
- **Visual Hierarchy**:
  1. **Page Header**: `AppPageHeader` with title `"Settings & Configuration"`, kicker `"SYSTEM PREFERENCES"`.
  2. **User Profile & Session Card**: `AppAccountCard` detailing current logged-in user, role (Admin/User), and session token status.
  3. **Admin User Management Card** *(Admin only)*: Table of user accounts with ability to create, edit username, reset password, or toggle role.
  4. **YTM Connection Card**: Google OAuth connection health, account email, "Relink Connection" button, and "Disconnect" button.
  5. **Music Library Roots**: Configured local directory paths, "Browse/Change" picker, and auto-scan frequency settings.
  6. **Matching & Tagging Preferences**: Minimum match confidence threshold, preferred metadata source (YouTube Music, Deezer, MusicBrainz).
