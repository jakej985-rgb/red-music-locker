# Red Music Locker — UI/UX Modernization Implementation Plan

## 1. Objective

Modernize the Red Music Locker Flutter application into a polished, fast, dark-first music-management application while preserving all existing functionality.

The redesign should make the application feel like:

- A premium music library
- A reliable synchronization dashboard
- A powerful personal music locker
- A multi-account YT Music management tool

The application should NOT become a generic admin dashboard or a Spotify clone.

The primary user workflow remains:

    Local Music
        ↓
    Red Music Locker
        ↓
    Match / Verify
        ↓
    YouTube Music Upload
        ↓
    Playlist Replication
        ↓
    Continuous Synchronization

The UI should make this workflow obvious.

---

# 2. Critical Safety Rules

Before making any changes:

## DO NOT

- Rewrite backend APIs
- Rewrite YT Music authentication
- Rewrite OAuth flows
- Rewrite upload matching logic
- Rewrite playlist synchronization logic
- Rewrite family/multi-account backend behavior
- Change database schemas unless absolutely required
- Remove existing functionality because it is not currently represented well visually
- Replace working state management with a different framework
- Remove existing API models
- Change API endpoints
- Change authentication tokens or credential handling
- Change Docker configuration
- Change deployment configuration
- Remove existing tests
- Delete existing pages simply because they are being redesigned

## MUST

- Preserve existing functionality
- Preserve existing routes
- Preserve existing API contracts
- Preserve existing state-management architecture unless a specific UI problem requires refactoring
- Make UI changes incrementally
- Run formatting/analyzer/tests after each major phase
- Keep commits logically separated
- Verify desktop and mobile layouts
- Verify existing sync functionality after UI changes

---

# 3. First Step — Repository Baseline

Before changing code:

1. Inspect the complete repository.
2. Identify:
   - Flutter entry point
   - routing
   - providers/controllers
   - API clients
   - models
   - services
   - views
   - reusable widgets
   - theme
   - authentication
   - account handling
   - playlist synchronization
   - upload queue
   - history
3. Run:

    flutter pub get
    flutter analyze
    flutter test

4. Record the current result.

Create:

    docs/ui-redesign/baseline.md

Document:

- analyzer result
- test result
- existing routes
- existing pages
- existing providers
- existing major widgets
- known warnings/errors

Do not fix unrelated issues during this step.

---

# 4. Create UI Architecture

Create a shared UI architecture instead of continuing to put large amounts of UI-specific logic inside individual pages.

Recommended structure:

    lib/
      core/
        theme/
        navigation/
        responsive/
        widgets/

      features/
        dashboard/
        library/
        uploads/
        playlists/
        queue/
        history/
        family/
        settings/

      shared/
        widgets/
        models/
        utils/

Use the existing architecture where possible.

Do not blindly move every existing file.

Refactor only where it improves maintainability.

---

# 5. Design System

Create a centralized Red Music Locker design system.

Recommended:

    lib/core/theme/

Files:

    app_theme.dart
    app_colors.dart
    app_spacing.dart
    app_radius.dart
    app_typography.dart

## Color direction

Base:

    Background:
    #0B0B0F

    Surface:
    #141419

    Elevated Surface:
    #1C1C23

    Primary:
    Red

    Primary emphasis:
    Bright red

    Primary text:
    White

    Secondary text:
    Gray

Use the existing brand colors if already defined.

Do not duplicate literal colors throughout widgets.

Instead:

    Theme.of(context).colorScheme

or centralized design constants.

---

# 6. Spacing System

Create standardized spacing values.

Example:

    xs = 4
    sm = 8
    md = 12
    lg = 16
    xl = 24
    xxl = 32

Use consistent:

- card padding
- page margins
- section spacing
- list spacing
- dialog spacing

Avoid every screen inventing its own padding.

---

# 7. Border Radius

Create consistent radii.

Example:

    small = 8
    medium = 12
    large = 16
    pill = 999

Use:

- 12–16px cards
- pill buttons/badges
- smaller radius for controls

Avoid excessive rounded UI.

---

# 8. Typography

Create a hierarchy:

## Display

Dashboard greeting / major page heading.

## Heading

Section titles.

## Body

Track metadata and descriptions.

## Label

Status badges and secondary information.

## Caption

Timestamps and technical information.

Prioritize readability over decorative typography.

---

# 9. Shared Components

Create reusable components before redesigning every page.

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

These components must be generic enough to work across pages.

---

# 10. Status Badge System

Create standard statuses.

Examples:

    Uploaded
    Local Only
    Matched
    Needs Review
    Failed
    Duplicate
    Syncing
    Pending
    Streaming Only

Each status should have:

- icon
- text
- semantic meaning
- consistent visual treatment

Do not rely solely on color.

Every status must remain understandable if the user cannot distinguish colors.

---

# 11. Responsive Navigation

The existing desktop navigation should remain.

Desktop:

    NavigationRail / NavigationDrawer

Mobile:

    BottomNavigationBar / NavigationBar

Desktop primary navigation:

    Home
    Library
    Uploads
    Playlists
    Queue
    History

Secondary:

    Family
    Settings

Mobile primary navigation:

    Home
    Library
    Uploads
    Playlists
    More

More contains:

    Queue
    History
    Family
    Settings

Do not cram the desktop navigation onto mobile.

---

# 12. Global Account Selector

Make the active YT Music account visible throughout the application.

Desktop:

    [ Account Avatar ] Jake ▼

Mobile:

    Jake ▼

Selector should show:

    Jake
    Michaela
    Other accounts
    Family

If supported by the existing backend, show:

    Personal
    Family
    Connection status

Do not change account-management behavior.

This is only a UI improvement.

---

# 13. Global Sync Status

Add a persistent compact status indicator.

Example:

    ● YTM Connected
    ↑ 17 uploading
    ✓ Synced 4m ago

This can live:

- in the desktop app shell
- at the bottom of the navigation
- or as a compact mobile header/status area

It should use existing state.

Do not create a second sync engine.

---

# 14. Dashboard Redesign

File:

    dashboard_view.dart

Convert the dashboard into a "Locker Status" command center.

## Header

Show:

    Good morning/afternoon/evening

    MUSIC LOCKER

    Short explanation of current state.

## Primary statistics

Show:

    Local Tracks
    Uploaded
    Missing
    Sync %

Example:

    1,284
    Local Tracks

    1,127
    Uploaded

    157
    Missing

    93%
    Synced

Use existing data.

Do not invent statistics.

## Primary action

Large:

    SYNC NOW

Secondary actions:

    Scan Library
    Upload Missing
    Manage Playlists

## Recent activity

Display:

    Recent uploads
    Playlist reconciliation
    Library scans
    Match issues

## Attention section

Only display when action is required.

Examples:

    7 tracks need review
    3 uploads failed
    2 playlists need reconciliation

Button:

    Review

The dashboard should answer:

1. Is everything okay?
2. What is happening?
3. Does the user need to do anything?

---

# 15. Music Library Redesign

File:

    library_view.dart

Make this the primary music-management experience.

## Header

    MUSIC LIBRARY

    1,284 tracks

## Search

Persistent search:

    Search music...

Search should search using existing backend/state functionality.

Do not create a duplicate search engine.

## Filters

Provide:

    All
    Uploaded
    Missing
    Needs Review
    Failed

## View switcher

    Grid
    List

Persist the user's preferred view if practical.

## Grid

Album artwork.

Display:

    artwork
    track title
    artist
    album
    status

## List

Columns:

    Selection
    Artwork
    Track
    Artist
    Album
    Status
    Actions

## Selection

When tracks are selected:

    157 selected

    Upload
    Edit Metadata
    Remove
    More

Replace the normal toolbar with the selection toolbar.

## Track interaction

Clicking a track opens:

    Track Details

Potential contents:

    Artwork
    Title
    Artist
    Album
    Metadata
    Local path
    Upload state
    YTM state
    Playlist membership

Reuse existing metadata editor functionality.

---

# 16. YTM Uploads Redesign

File:

    uploads_view.dart

Purpose:

Show what exists in YT Music and the upload state.

## Header

    YOUTUBE MUSIC

    1,127 uploaded tracks

    Last synchronized: 4 minutes ago

## Connection status

Display active account.

Example:

    ● Connected
    Jake's YouTube Music

## Filters

    All
    Recently Uploaded
    Needs Metadata
    Duplicates
    Failed

## Track list

Display:

    Artwork
    Track
    Artist
    Album
    Upload date
    Status
    Actions

## Upload state

Use shared status badges.

## Bulk selection

Support existing bulk operations.

Do not alter upload behavior.

---

# 17. Playlist Page Redesign

File:

    playlists_view.dart

This should receive significant visual attention.

## Playlist overview

Show playlist cards.

Each card:

    Artwork collage
    Playlist name
    Track count
    Locker count
    Missing count
    Sync state

Example:

    Workout

    84 tracks
    79 in locker
    5 missing

    ● Synced

## Search

    Search playlists...

## Filters

    All
    Synced
    Needs Attention
    Watching
    Not Watching

Only expose filters supported by actual application state.

---

# 18. Playlist Detail Page

Separate playlist overview from track management.

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

Track list should clearly indicate where each track exists.

Example:

    ✓ Local
    ✓ Locker
    ⚠ Missing

This is important because the application's playlist replication behavior depends on locker-only tracks.

---

# 19. Playlist Sync Visualization

Add a compact synchronization summary.

Example:

    PLAYLIST STATUS

    84 total

    █████████████████░░ 94%

    79 available in locker
    5 missing

    Last reconciliation:
    4 minutes ago

Use existing sync state.

Do not calculate misleading percentages.

---

# 20. Queue Redesign

File:

    queue_view.dart

Make Queue a live operations page.

Header:

    UPLOAD QUEUE

Statistics:

    Active
    Waiting
    Completed
    Failed

## Active

Show:

    Artwork
    Track
    Artist
    Operation
    Progress
    Current state

Example:

    Uploading

    █████████████░░░ 82%

## Waiting

Show queued tracks.

## Failed

Give each failure:

    Error summary
    Retry

## Bulk controls

    Retry Failed
    Clear Completed
    Pause
    Resume

Only expose controls that already exist in application logic.

---

# 21. Queue Navigation Indicator

Display pending queue count beside Queue.

Example:

    Queue
    17

Use existing queue state.

Do not poll excessively.

Use existing reactive state.

---

# 22. Sync History Redesign

File:

    history_view.dart

Convert history into a timeline/activity interface.

Filters:

    All
    Uploads
    Playlists
    Scans
    Errors

Timeline:

    13:42
    ✓ Upload completed
    Artist — Song

    13:38
    ✓ Playlist reconciled
    Workout — 84 tracks

    13:20
    ⚠ Match requires review

Each item should support:

    View Details

Details can show:

    timestamp
    operation
    account
    item
    result
    error
    relevant metadata

Do not remove historical data.

---

# 23. Family Mode Redesign

File:

    family_view.dart

Make account management visually obvious.

Header:

    FAMILY MUSIC LOCKER

    3 connected accounts

## Account cards

Each account card:

    Avatar
    Name
    Connection state
    Upload count
    Playlist count

Action:

    Manage

## Account management

Show:

    Connection
    Permissions
    Upload destination
    Playlist behavior

Preserve existing account functionality.

---

# 24. Family Upload Destination

This should be one of the clearest workflows.

When uploading:

    UPLOAD DESTINATION

    Where should this music go?

    ● Jake
    ○ Michaela
    ○ Account 3

Or:

    ☑ Jake
    ☑ Michaela
    ☐ Account 3

If multiple accounts are selected, clearly display:

    Uploading to 2 accounts

Do not change backend upload semantics.

---

# 25. Account Destination Preview

Before a multi-account upload, show:

    UPLOAD DESTINATION

    Track:
    Artist — Song

    Targets:

    ✓ Jake
    ✓ Michaela

    2 accounts

    [Cancel]
    [Upload]

This reduces accidental uploads to the wrong account.

---

# 26. Settings Redesign

File:

    settings_view.dart

Break the large settings page into logical groups.

## Account

    YouTube Music
    Accounts
    Family Mode

## Library

    Music folders
    Scanning
    Metadata
    Artwork

## Uploads

    Upload behavior
    Verification
    Retry behavior
    Concurrency

## Playlists

    Playlist watching
    Replica behavior
    Synchronization

## System

    API
    Database
    Logs
    Diagnostics

Do not change the actual settings.

Only reorganize their presentation.

---

# 27. Settings Components

Create reusable setting widgets:

    SettingsSection
    SettingsTile
    SettingsToggle
    SettingsDropdown
    SettingsValueTile
    SettingsDangerTile

Example:

    UPLOAD BEHAVIOR

    Automatic Uploads
    Automatically upload new music
                              ON

    Verify Uploads
    Verify tracks after upload
                              ON

Keep settings visually simple.

---

# 28. Search

Add global search if existing backend capabilities support it.

Search categories:

    Tracks
    Artists
    Albums
    Playlists

Example:

    "Metallica"

Results:

    TRACKS
    Enter Sandman
    Nothing Else Matters

    ALBUMS
    Metallica

    PLAYLISTS
    Metal Favorites

Do not build a large search infrastructure if it isn't needed for MVP.

A local client-side search over loaded data is acceptable initially.

---

# 29. Empty States

Every major page needs a useful empty state.

Examples:

## Empty Library

    Your music locker is empty.

    Add a music folder to get started.

    [Add Music Folder]

## Empty Playlists

    No YT Music playlists found.

    Connect an account and sync playlists.

## Empty Queue

    Everything is caught up.

    No uploads are waiting.

## Empty History

    No sync activity yet.

Empty states should explain:

- what happened
- why the page is empty
- what the user can do next

---

# 30. Loading States

Avoid blank screens.

Use:

- skeleton rows
- skeleton cards
- progress indicators
- meaningful loading text

Example:

    Loading your music library...

Do not show a spinner indefinitely without context.

---

# 31. Error States

Create a consistent error component.

Example:

    Couldn't load playlists.

    The YouTube Music connection may have expired.

    [Retry]

For technical errors:

    Details ▼

Do not expose raw stack traces by default.

Allow technical details behind an expandable section.

---

# 32. Dialog Redesign

Audit:

    metadata_editor_dialog.dart

and all other dialogs.

Dialogs should:

- have consistent width
- have consistent padding
- have clear titles
- use primary action on the right
- avoid excessive fields on one screen
- use sections when dialogs are large

For very large dialogs, convert to a full-screen responsive page on mobile.

---

# 33. Metadata Editor

Improve visual grouping.

Sections:

    BASIC INFORMATION

    Title
    Artist
    Album
    Album Artist

    TRACK INFORMATION

    Track #
    Disc #
    Genre
    Year

    ARTWORK

    Artwork preview
    Replace artwork

    YT MUSIC

    Matching status
    Upload status

Use existing metadata functionality.

Do not change the underlying model.

---

# 34. Responsive Rules

Desktop:

    max content width where appropriate
    multi-column cards
    navigation rail

Tablet:

    reduced columns
    collapsible navigation

Mobile:

    bottom navigation
    single-column layout
    full-width cards
    horizontal filter scrolling
    full-screen dialogs where needed

Minimum target:

    360px width

Verify at:

    360
    390
    430
    768
    1024
    1440+

---

# 35. Accessibility

Ensure:

- buttons have semantic labels
- icons aren't the only way to understand an action
- adequate contrast
- keyboard navigation where applicable
- focus states
- tooltips for unfamiliar icons
- status information is not color-only
- touch targets are sufficiently large

---

# 36. Performance

Red Music Locker should remain fast.

Avoid:

- unnecessary animations
- excessive blur
- large shader effects
- animated backgrounds
- rebuilding the entire library for one track update
- loading every artwork image simultaneously
- unnecessary network requests

Prefer:

- lazy lists
- lazy grids
- cached artwork
- const widgets
- selective provider watching
- pagination where already supported
- existing caching mechanisms

---

# 37. Artwork Handling

Artwork should become a major visual component.

Use:

- square artwork
- consistent aspect ratio
- placeholder artwork
- rounded corners
- lazy loading

Do not load full-resolution artwork when thumbnails are sufficient.

For lists, use small thumbnails.

For detail pages, use larger artwork.

---

# 38. Desktop Library Density

Desktop users should be able to manage large libraries efficiently.

Provide:

- compact list mode
- multi-select
- keyboard-friendly interaction
- sorting
- filtering
- search

Recommended sort options:

    Title
    Artist
    Album
    Date Added
    Upload Status

Only expose sorting supported by available data.

---

# 39. Mobile Library

Mobile list rows should prioritize:

    Artwork
    Title
    Artist
    Status

Secondary metadata can be hidden.

Swipe gestures should NOT be required for important actions.

Use:

    ⋮

for secondary actions.

---

# 40. Navigation State

Ensure the current page is always visually obvious.

Selected navigation item:

    icon
    label
    accent indicator

Do not use excessive red.

Red should communicate selection/action.

---

# 41. Animation

Use subtle animations only.

Allowed:

- page transitions
- selection changes
- progress changes
- card hover
- expandable sections

Avoid:

- constant motion
- animated backgrounds
- unnecessary particle effects
- excessive scaling

Target:

    fast
    responsive
    stable

---

# 42. Dark Mode

Red Music Locker should remain dark-first.

Ensure:

- cards aren't pure black against black
- surfaces have subtle hierarchy
- dividers are subtle
- red isn't overused

Hierarchy:

    Background
        ↓
    Surface
        ↓
    Elevated Surface
        ↓
    Modal / Dialog

---

# 43. Light Mode

If light mode already exists, keep it functional.

Do not design light mode independently from scratch.

Map the same semantic colors:

    background
    surface
    elevated
    primary
    error
    warning
    success

Ensure all new widgets work in both modes.

---

# 44. Component Extraction

Large views must be progressively decomposed.

Prioritize:

    playlists_view.dart
    family_view.dart
    settings_view.dart
    metadata_editor_dialog.dart

Move repeated sections into reusable widgets.

Do not create hundreds of tiny files.

Extract when a component:

- is reused
- has its own state
- is visually complex
- is independently testable
- makes the parent page easier to understand

---

# 45. State Management Rules

Existing Riverpod/state-management implementation should remain.

Widgets should consume state rather than directly duplicating business logic.

Avoid:

    API request
    parse response
    mutate unrelated state
    build UI

all inside one build method.

Prefer:

    Provider/Controller
          ↓
    View Model / State
          ↓
    UI

Do not rewrite functioning providers merely for style.

---

# 46. API Boundary

The UI redesign must not change API contracts.

Existing:

    services
    repositories
    API clients

remain authoritative.

UI components should consume their existing data.

If the UI requires data that does not currently exist:

1. Determine whether it can be derived locally.
2. If not, document the requirement.
3. Only then consider a backend/API change.

Do not silently modify API behavior.

---

# 47. Testing Strategy

Add widget tests for shared components.

At minimum test:

    AppStatusBadge
    AppTrackRow
    AppPlaylistCard
    AppStatCard
    AppSearchBar
    AppSelectionToolbar
    AppEmptyState
    AppErrorState

Test responsive behavior where practical.

---

# 48. Page-Level Testing

For each page verify:

## Dashboard

- loads
- statistics appear
- Sync Now works
- activity appears
- attention items appear

## Library

- loads tracks
- search works
- filters work
- grid works
- list works
- selection works
- existing metadata editor opens

## Uploads

- account state appears
- uploads display
- filters work
- existing actions work

## Playlists

- playlists load
- cards display
- playlist details open
- tracks display
- sync works
- replica behavior remains intact

## Queue

- active jobs display
- progress updates
- retry works
- completed items display

## History

- events display
- filters work
- details open

## Family

- accounts display
- account switching works
- upload destinations work
- multi-account functionality remains intact

## Settings

- all existing settings remain functional

---

# 49. Integration Testing

After UI changes, specifically verify:

    OAuth login
    Account linking
    Account switching
    Library scan
    Track matching
    Upload
    Upload verification
    Queue processing
    Playlist synchronization
    Playlist replication
    Family uploads
    Multi-account destination selection
    History recording

The UI redesign is NOT complete until these continue working.

---

# 50. Visual Regression Checklist

Capture screenshots at:

    360px
    390px
    430px
    768px
    1024px
    1440px
    1920px

For:

    Dashboard
    Library
    Uploads
    Playlists
    Queue
    History
    Family
    Settings

Review:

- clipping
- overflow
- alignment
- inconsistent spacing
- excessive empty space
- text wrapping
- card sizing
- navigation behavior

---

# 51. Documentation

Create:

    docs/ui-redesign/

Files:

    README.md
    design-system.md
    component-library.md
    responsive-design.md
    page-guidelines.md
    migration-notes.md

Document:

- colors
- typography
- spacing
- components
- page patterns
- responsive behavior
- decisions

---

# 52. Implementation Order

Do NOT redesign all pages simultaneously.

Use this order:

## Phase 1 — Baseline

- Audit
- Analyzer
- Tests
- Architecture documentation

## Phase 2 — Design System

- Colors
- Typography
- Spacing
- Radius
- Theme

## Phase 3 — Shared Components

- Headers
- Cards
- Status badges
- Track rows
- Playlist cards
- Search
- Empty/loading/error states

## Phase 4 — App Shell

- Navigation
- Account selector
- Global sync status
- Responsive navigation

## Phase 5 — Dashboard

Complete dashboard redesign.

## Phase 6 — Library

Complete library redesign.

## Phase 7 — Uploads

Complete YTM Uploads redesign.

## Phase 8 — Playlists

Complete playlist overview and detail redesign.

## Phase 9 — Queue

Complete queue redesign.

## Phase 10 — History

Complete history redesign.

## Phase 11 — Family

Complete family/multi-account UI redesign.

## Phase 12 — Settings

Complete settings redesign.

## Phase 13 — Dialogs

Metadata editor
Account selector
Upload destination
Confirmation dialogs

## Phase 14 — Responsive Pass

Test all pages across mobile/tablet/desktop.

## Phase 15 — Accessibility

Keyboard
Semantics
Contrast
Touch targets

## Phase 16 — Performance

Artwork
Lists
Provider rebuilds
Animations

## Phase 17 — Final QA

Full analyzer
Full test suite
Integration testing
Visual review

---

# 53. Git Commit Strategy

Use separate commits.

Recommended:

    ui: add red music locker design system

    ui: add shared library components

    ui: redesign application shell

    ui: redesign dashboard

    ui: redesign music library

    ui: redesign ytm uploads

    ui: redesign playlists

    ui: redesign queue

    ui: redesign sync history

    ui: redesign family mode

    ui: redesign settings

    ui: improve responsive layouts

    ui: improve accessibility

    ui: optimize artwork and list rendering

Do not combine the entire redesign into one massive commit.

---

# 54. Definition of Done

The redesign is complete only when:

## Visual

- [ ] Consistent Red Music Locker design system
- [ ] Premium dark UI
- [ ] Clear hierarchy
- [ ] Consistent spacing
- [ ] Consistent cards
- [ ] Consistent status badges
- [ ] Consistent dialogs
- [ ] Artwork used appropriately

## Dashboard

- [ ] Locker status
- [ ] Statistics
- [ ] Sync action
- [ ] Recent activity
- [ ] Attention-required section

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
- [ ] Playlist detail
- [ ] Sync state
- [ ] Locker-only representation
- [ ] Missing tracks
- [ ] Replica controls

## Queue

- [ ] Active jobs
- [ ] Waiting jobs
- [ ] Completed jobs
- [ ] Failed jobs
- [ ] Progress

## History

- [ ] Timeline
- [ ] Filters
- [ ] Details

## Family

- [ ] Account cards
- [ ] Account selection
- [ ] Upload destinations
- [ ] Multi-account workflow

## Settings

- [ ] Logical categories
- [ ] Existing settings preserved
- [ ] Improved readability

## Responsive

- [ ] 360px
- [ ] 390px
- [ ] 430px
- [ ] Tablet
- [ ] Desktop
- [ ] Wide desktop

## Functional

- [ ] OAuth still works
- [ ] Account linking still works
- [ ] Account switching works
- [ ] Uploads still work
- [ ] Matching still works
- [ ] Queue still works
- [ ] Playlist sync still works
- [ ] Playlist replication still works
- [ ] Family mode still works
- [ ] Multi-account uploads still work

## Quality

- [ ] flutter analyze passes
- [ ] flutter test passes
- [ ] no new analyzer warnings
- [ ] no broken routes
- [ ] no dead buttons
- [ ] no placeholder functionality
- [ ] no accidental backend changes

---

# 55. Final Product Goal

Red Music Locker should ultimately feel like:

    ┌─────────────────────────────────────────────┐
    │  RED MUSIC LOCKER             Jake ▼        │
    ├─────────────┬───────────────────────────────┤
    │             │                               │
    │  Home       │  MUSIC LOCKER                 │
    │  Library    │                               │
    │  Uploads    │  1,284 Tracks    93% Synced   │
    │  Playlists  │                               │
    │  Queue      │  ┌─────────┐ ┌─────────┐      │
    │  History    │  │ Library │ │ Upload  │      │
    │             │  └─────────┘ └─────────┘      │
    │  ─────────  │                               │
    │  Family     │  RECENT ACTIVITY              │
    │  Settings   │  ✓ Upload completed           │
    │             │  ✓ Playlist synced            │
    │             │  ⚠ 3 tracks need review       │
    │             │                               │
    ├─────────────┴───────────────────────────────┤
    │ ● YTM Connected   ↑ 17 queued   ✓ Synced    │
    └─────────────────────────────────────────────┘

The application should communicate at a glance:

    "My music is safe.
     My accounts are connected.
     My uploads are progressing.
     My playlists are synchronized.
     And if something needs me, I know exactly what."

That is the target experience.
