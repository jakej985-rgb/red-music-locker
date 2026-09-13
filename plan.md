# Red Music Locker — Complete Remaining UI/UX Implementation Plan

## 1. Mission

Complete the remaining Red Music Locker UI/UX modernization work identified in the repository audit.

The goal is to transform the existing application into a polished, fast, responsive, dark-first music locker while preserving all existing functionality.

The application should feel like:

- A premium personal music library
- A reliable YT Music synchronization tool
- A clean music-management application
- A powerful multi-account/family music locker

It should NOT become:

- A generic admin dashboard
- A Spotify clone
- An overly animated application
- A backend rewrite
- A complete architectural rewrite

The existing application already contains significant working functionality.

The job is to improve the presentation, organization, responsiveness, and usability of that functionality.

---

# 2. Current Repository State

The current repository already contains working functionality for:

- Authentication
- YouTube Music connection
- Account selection
- Multiple accounts
- Family Mode
- Music library
- Uploads
- Track matching
- Upload queue
- Playlist synchronization
- Playlist replication
- Sync history
- Metadata editing
- Folder browsing
- Settings

Large existing views include:

- playlists_view.dart
- family_view.dart
- settings_view.dart
- metadata_editor_dialog.dart
- uploads_view.dart
- queue_view.dart

These should be progressively refactored, NOT blindly rewritten.

---

# 3. Non-Negotiable Protection Rules

## DO NOT CHANGE

Do not modify unless absolutely required:

- Backend API contracts
- API endpoints
- OAuth implementation
- Authentication behavior
- Token handling
- Account linking logic
- YT Music upload logic
- Track matching logic
- Duplicate detection
- Playlist synchronization logic
- Playlist replica logic
- Family synchronization logic
- Database schema
- Database migrations
- Docker configuration
- Deployment configuration
- Existing environment configuration
- Existing authentication/security behavior

## DO NOT REMOVE

Do not remove:

- Existing features
- Existing routes
- Existing buttons unless replaced with equivalent functionality
- Existing account controls
- Existing playlist functionality
- Existing upload controls
- Existing metadata functionality
- Existing queue controls

## UI-only rule

Whenever possible:

    Existing State
          ↓
    Existing Service
          ↓
    Existing API
          ↓
    NEW UI

Do not create duplicate business logic inside the new UI.

---

# 4. Phase 0 — Baseline Before Changes

Run:

    flutter pub get
    flutter analyze
    flutter test

Record results.

Create:

    docs/ui-redesign/

Create:

    baseline.md

Document:

- Analyzer status
- Test status
- Existing routes
- Existing views
- Existing providers/controllers
- Existing services
- Existing shared widgets
- Existing theme
- Known failures

If analyzer/tests already fail before UI work:

- Document the failures
- Do not claim they were caused by the redesign
- Fix only if required for the current UI work

---

# 5. Phase 1 — Build the Design System

Create a centralized UI foundation.

Recommended:

    lib/core/theme/

Files:

    app_theme.dart
    app_colors.dart
    app_spacing.dart
    app_radius.dart
    app_typography.dart

If the repository uses a different architecture, place these in the closest equivalent existing location.

Do not create duplicate theme systems.

---

# 6. Color System

Use the existing Red Music Locker branding as the source of truth.

Target visual hierarchy:

    Background
        ↓
    Surface
        ↓
    Elevated Surface
        ↓
    Modal

Recommended direction:

    Background:
    #0B0B0F

    Surface:
    #141419

    Elevated:
    #1C1C23

    Primary:
    Existing Red Music Locker red

    Primary emphasis:
    Existing bright red

    Text:
    White

    Secondary:
    Gray

Do not hard-code colors throughout new widgets.

Use:

    Theme.of(context).colorScheme

or centralized theme constants.

---

# 7. Spacing System

Create:

    xs
    sm
    md
    lg
    xl
    xxl

Suggested:

    4
    8
    12
    16
    24
    32

Use consistently.

---

# 8. Radius System

Create:

    small
    medium
    large
    pill

Suggested:

    8
    12
    16
    999

Do not make every element extremely rounded.

---

# 9. Typography System

Create consistent styles for:

- Page titles
- Section titles
- Card titles
- Body
- Secondary text
- Captions
- Status labels

Do not introduce unnecessary decorative fonts.

---

# 10. Phase 2 — Shared UI Components

Create reusable components before continuing page redesign.

Recommended:

    AppPageHeader
    AppSectionHeader
    AppSearchBar
    AppFilterBar
    AppStatCard
    AppStatusBadge
    AppTrackRow
    AppTrackGrid
    AppPlaylistCard
    AppAccountCard
    AppActivityItem
    AppProgressCard
    AppSelectionToolbar
    AppEmptyState
    AppLoadingState
    AppErrorState
    AppConfirmDialog
    AppBottomStatusBar

Use existing components where they already solve the problem.

Do not duplicate:

- Account selector
- Metadata editor
- Upload destination
- Authentication dialogs

Instead, progressively bring them into the shared design language.

---

# 11. AppStatusBadge

Create one status system.

Supported states should include only statuses actually used by the application.

Potential statuses:

    Uploaded
    Local Only
    Matched
    Needs Review
    Failed
    Duplicate
    Syncing
    Pending
    Streaming Only

Each status must have:

- Icon
- Label
- Semantic meaning
- Consistent appearance

Do not rely solely on color.

---

# 12. AppTrackRow

Create the standard track row.

Desktop:

    Selection
    Artwork
    Track
    Artist
    Album
    Status
    Actions

Mobile:

    Artwork
    Track
    Artist
    Status
    More

The same component should be reusable by:

- Library
- Uploads
- Playlist detail
- Queue where appropriate
- History where appropriate

---

# 13. AppPlaylistCard

Create reusable playlist card.

Show:

- Artwork/collage
- Playlist name
- Track count
- Locker count
- Missing count
- Sync state

Do not duplicate playlist-card styling in multiple pages.

---

# 14. AppAccountCard

Create reusable account card.

Show:

- Account identity
- Connection status
- Upload information where available
- Playlist information where available
- Action

Use this in Family Mode.

---

# 15. AppEmptyState

Create a standard empty state containing:

- Icon
- Title
- Explanation
- Optional action

Examples:

    Your music locker is empty.

    Add a music folder to get started.

    [Add Music Folder]

---

# 16. AppErrorState

Create standard error presentation.

Show:

    Something went wrong.

    Explanation

    [Retry]

Optional:

    Technical Details ▼

Never display raw stack traces as the primary UI.

---

# 17. Phase 3 — App Shell

Update the existing shell without changing routing behavior.

Desktop:

    NavigationRail / NavigationDrawer

Mobile:

    NavigationBar

Desktop primary:

    Home
    Library
    Uploads
    Playlists
    Queue
    History

Secondary:

    Family
    Settings

Mobile:

    Home
    Library
    Uploads
    Playlists
    More

More:

    Queue
    History
    Family
    Settings

---

# 18. Account Selector

Consolidate account selection into one reusable UI.

Example:

    Jake ▼

Opening it:

    SELECT ACCOUNT

    ● Jake
      Personal

    ○ Michaela
      Personal

    ○ Other Account

    ○ Family

    + Add Account

Use the existing account state.

Do not change account switching behavior.

---

# 19. Global Sync Status

Add a persistent compact status indicator.

Example:

    ● YTM Connected
    ↑ 17 queued
    ✓ Synced 4m ago

Use existing state.

Do not create duplicate polling.

If queue/sync state is unavailable, show only the information that actually exists.

---

# 20. Queue Navigation Badge

Show pending queue count next to Queue.

Example:

    Queue 17

Only update based on existing reactive queue state.

Do not introduce aggressive polling.

---

# 21. Phase 4 — Dashboard

Redesign Dashboard into a Locker Status page.

## Header

    MUSIC LOCKER

    Current account

    Short status summary

## Statistics

Show real existing data:

    Local Tracks
    Uploaded
    Missing
    Synced %

Do not fabricate values.

## Primary action

    SYNC NOW

Secondary:

    Scan Library
    Upload Missing
    Manage Playlists

## Recent Activity

Show existing activity data.

## Attention Required

Only show when actual problems exist.

Examples:

    Tracks needing review
    Failed uploads
    Playlist reconciliation problems

Action:

    Review

---

# 22. Dashboard UX Rule

The dashboard should answer three questions immediately:

1. Is my locker healthy?
2. What is currently happening?
3. Do I need to do anything?

Avoid turning the dashboard into a duplicate of Library or Queue.

---

# 23. Phase 5 — Music Library

Redesign the Library around music management.

Header:

    MUSIC LIBRARY

    Track count

Search:

    Search music...

Filters:

    All
    Uploaded
    Missing
    Needs Review
    Failed

View:

    Grid
    List

---

# 24. Library Grid

Use:

    AppTrackGrid

Each item:

    Artwork
    Title
    Artist
    Album
    Status

Use lazy loading.

Do not load unnecessary full-resolution artwork.

---

# 25. Library List

Use:

    AppTrackRow

Support:

- Selection
- Bulk actions
- Status
- Secondary actions

When selected:

    157 selected

    Upload
    Edit Metadata
    Remove
    More

---

# 26. Library Sorting

If supported by existing data, provide:

    Title
    Artist
    Album
    Date Added
    Upload Status

Do not add sorting that requires backend work unless necessary.

---

# 27. Track Details

Use existing metadata functionality.

A track detail view should expose:

    Artwork
    Title
    Artist
    Album
    Metadata
    Local Path
    Upload State
    YTM State
    Playlist Membership

Do not duplicate metadata-editing logic.

---

# 28. Phase 6 — YTM Uploads

Redesign Uploads.

Header:

    YOUTUBE MUSIC

    Uploaded track count

    Last sync time

Account:

    ● Connected
    Jake's YouTube Music

Filters:

    All
    Recently Uploaded
    Needs Metadata
    Duplicates
    Failed

Use AppTrackRow.

Preserve all existing upload actions.

---

# 29. Upload Status

Make status immediately understandable.

Examples:

    Uploaded
    Uploading
    Pending
    Failed
    Duplicate
    Needs Review

Use existing application state.

---

# 30. Phase 7 — Playlists

This is a high-priority redesign.

Do NOT rewrite playlist functionality.

Instead:

1. Extract reusable components.
2. Reduce the size of playlists_view.dart.
3. Separate playlist overview from playlist detail.
4. Preserve existing replica logic.

---

# 31. Playlist Overview

Display playlist cards.

Example:

    Workout

    84 tracks
    79 in locker
    5 missing

    ● Synced

Use:

    AppPlaylistCard

---

# 32. Playlist Detail

Create a clear hierarchy.

Header:

    WORKOUT

    84 tracks

    79 uploaded
    5 missing

Actions:

    Sync Now
    Manage Replica
    More

Filters:

    All
    Locker
    Missing
    Streaming Only

Only show categories supported by the existing application.

---

# 33. Playlist Sync Summary

Show:

    84 total

    79 available
    5 missing

    Last reconciliation:
    timestamp

Do not calculate percentages from incomplete data.

---

# 34. Playlist Replica UI

Preserve the existing:

    Locker Only (1:1 Ordered)

functionality.

Make the UI clearer around:

- Source playlist
- Replica playlist
- Locker-only behavior
- Current sync state
- Last synchronization
- Missing tracks

Do not alter the synchronization algorithm.

---

# 35. Phase 8 — Queue

Redesign Queue as an operations center.

Header:

    UPLOAD QUEUE

Statistics:

    Active
    Waiting
    Completed
    Failed

---

# 36. Queue Active Jobs

Show:

    Artwork
    Track
    Artist
    Operation
    Progress
    Status

Example:

    Uploading

    ████████████░░ 82%

Use:

    AppProgressCard

---

# 37. Queue Failed Jobs

Show:

    Track
    Error summary
    Retry

Do not expose unnecessary technical information.

Allow:

    Details

where useful.

Preserve existing retry/cancel functionality.

---

# 38. Phase 9 — Sync History

Convert History into a proper activity timeline.

Filters:

    All
    Uploads
    Playlists
    Scans
    Errors

Example:

    TODAY

    13:42
    ✓ Upload completed
    Artist — Song

    13:38
    ✓ Playlist reconciled
    Workout — 84 tracks

    13:20
    ⚠ Match requires review

Use:

    AppActivityItem

---

# 39. History Details

Each history event should support details where useful:

    Timestamp
    Operation
    Account
    Item
    Result
    Error
    Relevant metadata

Do not delete historical information.

---

# 40. Phase 10 — Family Mode

Make Family Mode account-centered.

Header:

    FAMILY MUSIC LOCKER

    Connected account count

Use:

    AppAccountCard

for each account.

Show:

    Account
    Connection
    Upload information
    Playlist information
    Manage

---

# 41. Family Account Management

Preserve all existing:

- Account connection
- Account switching
- Family sync
- Permissions
- Playlist behavior

Only improve presentation.

---

# 42. Family Upload Destination

Make upload destination extremely clear.

Example:

    UPLOAD DESTINATION

    Where should this music go?

    ● Jake
    ○ Michaela
    ○ Account 3

Or:

    TARGET ACCOUNTS

    ☑ Jake
    ☑ Michaela
    ☐ Account 3

Then:

    Uploading to 2 accounts

Preserve existing backend behavior.

---

# 43. Multi-Account Confirmation

Before a multi-account upload:

    UPLOAD DESTINATION

    Track:
    Artist — Song

    Targets:

    ✓ Jake
    ✓ Michaela

    2 accounts

    [Cancel]
    [Upload]

This is a UI safety improvement.

---

# 44. Phase 11 — Settings

Break the huge settings page into sections.

Sections:

    ACCOUNT

    YouTube Music
    Accounts
    Family Mode

    LIBRARY

    Music folders
    Scanning
    Metadata
    Artwork

    UPLOADS

    Upload behavior
    Verification
    Retry
    Concurrency

    PLAYLISTS

    Playlist watching
    Replica behavior
    Synchronization

    SYSTEM

    API
    Database
    Logs
    Diagnostics

---

# 45. Settings Components

Create:

    SettingsSection
    SettingsTile
    SettingsToggle
    SettingsDropdown
    SettingsValueTile
    SettingsDangerTile

Use existing setting values and callbacks.

Do not change setting semantics.

---

# 46. Phase 12 — Metadata Editor

The metadata editor is extremely large and should be progressively decomposed.

Organize into:

    BASIC INFORMATION

    TRACK INFORMATION

    ARTWORK

    YOUTUBE MUSIC

Use existing fields and save behavior.

---

# 47. Metadata Editor Mobile

Desktop:

    Dialog

Mobile:

    Full-screen page or full-height modal

Avoid a tiny dialog containing dozens of fields.

Do not change metadata model behavior.

---

# 48. Phase 13 — Folder Browser

Improve visual consistency.

Maintain:

- folder navigation
- selection
- permissions
- path handling

Improve:

- breadcrumbs
- folder rows
- selection state
- primary action
- empty state
- error state

Do not change filesystem behavior.

---

# 49. Phase 14 — Authentication

Do not rewrite authentication.

Only modernize:

- login dialog
- account connection UI
- loading state
- errors
- success state

Authentication logic remains untouched.

---

# 50. Phase 15 — Global Search

Implement only after the primary UI is complete.

Search:

    Tracks
    Artists
    Albums
    Playlists

Start client-side if the required data is already available.

Do not add backend search infrastructure unnecessarily.

---

# 51. Phase 16 — Responsive Design

This is mandatory.

Test:

    360px
    390px
    430px
    768px
    1024px
    1440px
    1920px

Check every major page.

---

# 52. Responsive Rules

At mobile:

- NavigationBar
- Single-column cards
- Compact track rows
- Horizontal filter scrolling
- Full-width controls
- Full-screen metadata dialogs
- No horizontal overflow

At tablet:

- Reduced card columns
- Flexible navigation
- Reduced information density

Desktop:

- NavigationRail
- Multi-column layout
- Dense library list
- Wide dialogs
- Multi-column statistics

---

# 53. Mobile Priority

On mobile, prioritize:

    Artwork
    Title
    Artist
    Status
    Primary action

Hide lower-priority metadata behind:

    ⋮

Do not require swipe gestures for important operations.

---

# 54. Phase 17 — Accessibility

Check:

- Semantic labels
- Keyboard navigation
- Focus states
- Contrast
- Touch targets
- Tooltips
- Screen-reader labels
- Color-independent status

Every important action must have a textual/semantic meaning.

---

# 55. Phase 18 — Performance

Do not sacrifice speed for visual effects.

Avoid:

- unnecessary animations
- excessive blur
- animated backgrounds
- shader-heavy effects
- rebuilding entire libraries
- loading every artwork at once

Use:

- lazy lists
- lazy grids
- cached artwork
- const widgets
- selective provider watching
- existing caching
- pagination where supported

---

# 56. Artwork Performance

For lists:

    Small thumbnails

For cards:

    Medium artwork

For details:

    Large artwork

Never load huge original artwork where a thumbnail is sufficient.

---

# 57. Refactoring Strategy

Do NOT perform a giant architectural rewrite.

Refactor each page as it is redesigned.

Recommended sequence:

    Shared components
          ↓
    Dashboard
          ↓
    Library
          ↓
    Uploads
          ↓
    Playlists
          ↓
    Queue
          ↓
    History
          ↓
    Family
          ↓
    Settings
          ↓
    Dialogs

After each major page:

    flutter analyze
    flutter test

---

# 58. Large File Reduction

Priority files:

    playlists_view.dart
    family_view.dart
    settings_view.dart
    metadata_editor_dialog.dart
    uploads_view.dart
    queue_view.dart

Do not set arbitrary line-count goals.

Instead, extract sections when they:

- have independent state
- are reused
- are visually complex
- are independently testable
- make the parent page easier to understand

---

# 59. Provider/State Rules

Keep the existing state-management approach.

New widgets should consume existing state.

Do not move business logic into:

    build()

Avoid:

    API request
    business decision
    state mutation
    UI rendering

all inside one widget.

---

# 60. No Duplicate Business Logic

If an existing service already handles:

    Upload

Use it.

If an existing provider already handles:

    Queue state

Use it.

If an existing service handles:

    Playlist replication

Use it.

If an existing provider handles:

    Account selection

Use it.

The UI is a consumer of the application's existing logic.

---

# 61. Testing

Add widget tests for:

    AppStatusBadge
    AppTrackRow
    AppPlaylistCard
    AppAccountCard
    AppStatCard
    AppSearchBar
    AppSelectionToolbar
    AppEmptyState
    AppErrorState

Test:

- normal state
- empty state
- loading state
- error state
- selected state
- mobile layout where practical

---

# 62. Functional Regression Tests

After UI changes verify:

## Authentication

- [ ] Login
- [ ] Logout
- [ ] OAuth
- [ ] Account connection

## Accounts

- [ ] Switch account
- [ ] Multiple accounts
- [ ] Family Mode

## Library

- [ ] Scan
- [ ] Display tracks
- [ ] Search
- [ ] Filter
- [ ] Select
- [ ] Edit metadata

## Upload

- [ ] Upload
- [ ] Queue
- [ ] Progress
- [ ] Retry
- [ ] Verification
- [ ] Duplicate handling

## Playlists

- [ ] Import
- [ ] Watch
- [ ] Sync
- [ ] Replica
- [ ] Locker-only behavior
- [ ] Missing tracks

## Family

- [ ] Select account
- [ ] Multi-account destination
- [ ] Family sync

## History

- [ ] Events recorded
- [ ] Events displayed

---

# 63. UI Regression Checklist

Every page must be checked for:

- [ ] No overflow
- [ ] No clipped text
- [ ] No dead buttons
- [ ] No broken navigation
- [ ] No duplicated controls
- [ ] No inconsistent colors
- [ ] No inconsistent spacing
- [ ] No tiny touch targets
- [ ] No unnecessary animation
- [ ] No blank loading screens
- [ ] Useful empty states
- [ ] Useful error states

---

# 64. Visual QA

Review screenshots for:

    Dashboard
    Library
    Uploads
    Playlists
    Playlist Detail
    Queue
    History
    Family
    Settings
    Metadata Editor

At:

    360
    390
    430
    768
    1024
    1440
    1920

Fix visual issues before proceeding to final QA.

---

# 65. Documentation

Create:

    docs/ui-redesign/

Files:

    README.md
    design-system.md
    components.md
    responsive-design.md
    page-guidelines.md
    migration-notes.md

Document the new design system and reusable components.

---

# 66. Git Strategy

Use separate commits.

Recommended:

    ui: establish design system

    ui: add shared components

    ui: modernize application shell

    ui: redesign dashboard

    ui: redesign library

    ui: redesign uploads

    ui: redesign playlists

    ui: redesign queue

    ui: redesign history

    ui: redesign family mode

    ui: redesign settings

    ui: modernize dialogs

    ui: improve responsive layouts

    ui: improve accessibility

    ui: optimize artwork rendering

    test: add ui regression coverage

Do not create one massive UI commit.

---

# 67. Stop Conditions

The agent must STOP and report instead of continuing if it discovers:

- Backend API changes are required
- Database schema changes are required
- OAuth changes are required
- Existing sync logic is broken
- Existing playlist replication logic is broken
- Existing multi-account behavior conflicts with the UI
- Existing tests fail because of pre-existing problems
- A requested visual feature requires major architectural changes

Do not silently work around these problems.

---

# 68. Final Acceptance Criteria

The work is complete only when:

## Design system

- [ ] Centralized theme
- [ ] Centralized colors
- [ ] Centralized spacing
- [ ] Centralized radius
- [ ] Centralized typography

## Components

- [ ] Shared page header
- [ ] Shared search
- [ ] Shared filters
- [ ] Shared stat cards
- [ ] Shared status badges
- [ ] Shared track rows
- [ ] Shared playlist cards
- [ ] Shared account cards
- [ ] Shared activity items
- [ ] Shared progress cards
- [ ] Shared selection toolbar
- [ ] Shared empty/loading/error states

## Shell

- [ ] Desktop navigation
- [ ] Mobile navigation
- [ ] Account selector
- [ ] Global sync status
- [ ] Queue badge

## Dashboard

- [ ] Locker status
- [ ] Statistics
- [ ] Sync
- [ ] Activity
- [ ] Attention required

## Library

- [ ] Search
- [ ] Filters
- [ ] Grid
- [ ] List
- [ ] Selection
- [ ] Bulk actions
- [ ] Track details

## Uploads

- [ ] Account status
- [ ] Upload state
- [ ] Filters
- [ ] Bulk actions

## Playlists

- [ ] Playlist cards
- [ ] Playlist details
- [ ] Sync status
- [ ] Missing tracks
- [ ] Locker-only tracks
- [ ] Replica controls

## Queue

- [ ] Active
- [ ] Waiting
- [ ] Completed
- [ ] Failed
- [ ] Progress
- [ ] Retry

## History

- [ ] Timeline
- [ ] Filters
- [ ] Details

## Family

- [ ] Account cards
- [ ] Account selection
- [ ] Upload destination
- [ ] Multi-account selection

## Settings

- [ ] Organized sections
- [ ] Existing settings preserved

## Dialogs

- [ ] Metadata editor
- [ ] Account selector
- [ ] Upload destination
- [ ] Authentication
- [ ] Confirmation dialogs

## Responsive

- [ ] 360px
- [ ] 390px
- [ ] 430px
- [ ] Tablet
- [ ] Desktop
- [ ] Wide desktop

## Accessibility

- [ ] Semantic controls
- [ ] Keyboard support
- [ ] Focus states
- [ ] Contrast
- [ ] Touch targets
- [ ] Color-independent statuses

## Performance

- [ ] Lazy lists
- [ ] Lazy grids
- [ ] Artwork optimization
- [ ] No unnecessary rebuilds
- [ ] Minimal animations

## Regression

- [ ] OAuth works
- [ ] Accounts work
- [ ] Uploads work
- [ ] Matching works
- [ ] Queue works
- [ ] Playlist sync works
- [ ] Playlist replicas work
- [ ] Family mode works
- [ ] Multi-account uploads work
- [ ] History works

## Quality

- [ ] flutter analyze passes
- [ ] flutter test passes
- [ ] No new warnings
- [ ] No broken routes
- [ ] No dead UI actions
- [ ] No unintended backend changes
- [ ] No database changes
- [ ] No authentication changes

---

# 69. Final Product Standard

Red Music Locker should communicate immediately:

    MY MUSIC IS SAFE
    MY ACCOUNTS ARE CONNECTED
    MY LIBRARY IS ORGANIZED
    MY UPLOADS ARE PROGRESSING
    MY PLAYLISTS ARE SYNCHRONIZED
    I KNOW WHEN SOMETHING NEEDS MY ATTENTION

The UI should prioritize:

    STATUS
       ↓
    LIBRARY
       ↓
    UPLOAD
       ↓
    SYNC
       ↓
    ATTENTION

Speed and clarity are more important than flashy visuals.

The redesign should feel polished without becoming visually noisy.

---

# 70. Final Agent Report

At completion, the agent must provide:

1. Files created
2. Files modified
3. Components created
4. Pages redesigned
5. Responsive work completed
6. Accessibility work completed
7. Tests added
8. flutter analyze result
9. flutter test result
10. Confirmation that backend/API behavior was not changed
11. Confirmation that OAuth behavior was not changed
12. Confirmation that upload behavior was not changed
13. Confirmation that playlist replication was not changed
14. Confirmation that multi-account behavior was not changed
15. Any remaining known issues

Do not claim completion if any major acceptance criterion remains incomplete.
