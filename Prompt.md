You are the implementation agent for the Red Music Locker UI/UX modernization.

The repository contains an existing, functioning Red Music Locker application.

A detailed implementation plan exists at:

    plan.md

Your job is to COMPLETE THE WORK IN plan.md.

Do not create a new plan.
Do not replace the plan with your own approach.
Do not stop after partially implementing it.
Use plan.md as the authoritative task list and work through it systematically.

==================================================
PRIMARY OBJECTIVE
==================================================

Complete the remaining Red Music Locker UI/UX modernization described in plan.md.

The final application should be:

- polished
- modern
- dark-first
- fast
- responsive
- consistent
- easy to navigate
- music-library focused
- synchronization focused
- multi-account friendly

The application should feel like a premium music locker rather than a generic admin dashboard.

==================================================
CRITICAL RULE — PROTECT EXISTING FUNCTIONALITY
==================================================

The existing application contains important working functionality.

DO NOT rewrite or unnecessarily modify:

- backend APIs
- API endpoints
- OAuth
- authentication
- token handling
- account linking
- YT Music integration
- upload logic
- track matching
- duplicate detection
- upload verification
- queue processing
- playlist synchronization
- playlist replica logic
- family synchronization
- multi-account behavior
- database schema
- database migrations
- Docker
- deployment
- environment configuration

The UI modernization must consume the existing functionality.

Preferred architecture:

    Existing API
        ↓
    Existing Services
        ↓
    Existing Providers / State
        ↓
    New UI Components
        ↓
    User

Do not create duplicate business logic in the UI.

==================================================
FIRST: READ AND AUDIT
==================================================

Before modifying anything:

1. Read plan.md completely.
2. Inspect the repository structure.
3. Identify the current implementation of:
   - theme
   - navigation
   - dashboard
   - library
   - uploads
   - playlists
   - queue
   - history
   - family
   - settings
   - dialogs
   - account selector
   - state management
4. Compare the current repository against every requirement in plan.md.
5. Determine which requirements are:
   - already complete
   - partially complete
   - missing
6. Do not redo functionality that is already correctly implemented.
7. Do not assume a feature is missing simply because it is implemented differently.

Create or update:

    docs/ui-redesign/implementation-status.md

Track:

    COMPLETE
    PARTIAL
    NOT STARTED

for the major plan sections.

==================================================
BASELINE
==================================================

Before making UI changes, run:

    flutter pub get
    flutter analyze
    flutter test

Record the results.

If there are pre-existing failures:

- document them
- do not incorrectly attribute them to your changes
- do not perform unrelated cleanup

==================================================
IMPLEMENTATION ORDER
==================================================

Follow this order unless the repository structure requires a minor adjustment:

PHASE 1
Design system

PHASE 2
Shared UI components

PHASE 3
Application shell

PHASE 4
Dashboard

PHASE 5
Music Library

PHASE 6
YTM Uploads

PHASE 7
Playlists

PHASE 8
Queue

PHASE 9
Sync History

PHASE 10
Family Mode

PHASE 11
Settings

PHASE 12
Dialogs

PHASE 13
Responsive/mobile

PHASE 14
Accessibility

PHASE 15
Performance

PHASE 16
Testing and regression

Do not jump randomly between pages.

==================================================
PHASE 1 — DESIGN SYSTEM
==================================================

Create a centralized design system.

Prefer:

    lib/core/theme/

or the closest appropriate existing architecture.

Implement:

- colors
- spacing
- typography
- radii
- theme configuration

Do not scatter new literal colors throughout the application.

Use the existing Red Music Locker branding as the source of truth.

The design should be:

- dark
- clean
- premium
- restrained
- high contrast
- fast

Red should be an accent, not the color of every component.

==================================================
PHASE 2 — SHARED COMPONENTS
==================================================

Build reusable components before redesigning every page.

Target components include:

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

Do not create unnecessary micro-components.

Reuse existing functional components where appropriate.

==================================================
PHASE 3 — APPLICATION SHELL
==================================================

Improve the existing navigation without changing routes.

Desktop:

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

Implement responsive navigation rather than squeezing the desktop navigation onto mobile.

Add:

- reusable account selector
- global sync status
- queue pending badge

Use existing application state.

Do not create duplicate polling systems.

==================================================
PHASE 4 — DASHBOARD
==================================================

Redesign the dashboard as:

    LOCKER STATUS

The user should immediately understand:

1. Is everything healthy?
2. What is happening?
3. Does anything need attention?

Include real data for:

- local tracks
- uploaded tracks
- missing tracks
- sync percentage where valid
- current account
- recent activity
- problems requiring attention

Primary action:

    SYNC NOW

Secondary actions:

    Scan Library
    Upload Missing
    Manage Playlists

Do not turn the dashboard into a duplicate Library or Queue page.

==================================================
PHASE 5 — MUSIC LIBRARY
==================================================

Redesign around managing music.

Implement:

- search
- filters
- grid view
- list view
- selection
- bulk actions
- track status
- track details

Use the shared track components.

Preserve all existing:

- scan behavior
- matching
- deletion
- metadata editing
- upload functionality

Do not rewrite the library data layer.

==================================================
PHASE 6 — YTM UPLOADS
==================================================

Redesign uploads around:

    YOUTUBE MUSIC

Show:

- connected account
- uploaded count
- sync information
- upload status
- filters
- track list

Use shared components.

Preserve existing upload behavior exactly.

==================================================
PHASE 7 — PLAYLISTS
==================================================

This is a HIGH PRIORITY page.

The current playlists implementation is large and contains important functionality.

Do not rewrite playlist synchronization.

Refactor the UI progressively.

Create:

- playlist overview
- playlist cards
- playlist detail
- sync summary
- track status
- filters
- replica controls

Preserve:

    Locker Only (1:1 Ordered)

and all existing playlist replication behavior.

The UI must clearly communicate:

- total tracks
- tracks available in locker
- missing tracks
- streaming-only tracks
- sync state
- replica state

==================================================
PHASE 8 — QUEUE
==================================================

Turn Queue into an operations center.

Show:

- active
- waiting
- completed
- failed

For active items show:

- artwork
- track
- artist
- operation
- progress
- status

Preserve:

- retry
- cancellation
- existing queue processing
- existing error behavior

==================================================
PHASE 9 — HISTORY
==================================================

Turn Sync History into a timeline/activity interface.

Include:

- uploads
- playlist operations
- scans
- errors

Use shared activity components.

Preserve historical data.

Do not change the history backend.

==================================================
PHASE 10 — FAMILY MODE
==================================================

Make Family Mode account-centered.

Use account cards.

Show:

- account
- connection status
- relevant statistics
- manage action

Improve multi-account upload destination selection.

Make it extremely clear where an upload will go.

For example:

    TARGET ACCOUNTS

    ✓ Jake
    ✓ Michaela
    ☐ Account 3

    Uploading to 2 accounts

Preserve all existing multi-account functionality.

Do not alter account permissions or backend behavior.

==================================================
PHASE 11 — SETTINGS
==================================================

Break the large settings interface into logical sections.

Use:

    ACCOUNT
    LIBRARY
    UPLOADS
    PLAYLISTS
    SYSTEM

Create reusable settings components.

Preserve every existing setting and its behavior.

Do not change setting semantics.

==================================================
PHASE 12 — DIALOGS
==================================================

Modernize:

- Metadata editor
- Account selector
- Upload destination
- Authentication
- Confirmation dialogs
- Folder browser

Do not rewrite their underlying functionality.

Metadata editor should visually group:

    Basic Information
    Track Information
    Artwork
    YouTube Music

On mobile, large dialogs should become full-screen or full-height interfaces where appropriate.

==================================================
PHASE 13 — RESPONSIVE DESIGN
==================================================

Every major page must work at:

    360px
    390px
    430px
    768px
    1024px
    1440px
    1920px

Check:

- no horizontal overflow
- no clipped text
- no inaccessible controls
- no broken cards
- no oversized dialogs
- no unusable navigation
- no broken tables

Mobile should prioritize:

- artwork
- title
- artist
- status
- primary action

Secondary actions may live under:

    ...

Do not require swipe gestures for important operations.

==================================================
PHASE 14 — ACCESSIBILITY
==================================================

Check:

- semantic labels
- keyboard navigation
- focus states
- contrast
- touch targets
- screen-reader labels
- tooltips
- color-independent statuses

Do not rely solely on red/green colors to communicate state.

==================================================
PHASE 15 — PERFORMANCE
==================================================

Red Music Locker prioritizes speed.

Avoid:

- unnecessary animations
- animated backgrounds
- excessive blur
- shader-heavy effects
- huge artwork loads
- unnecessary provider rebuilds
- rebuilding entire libraries for individual changes
- unnecessary network calls

Use:

- lazy lists
- lazy grids
- cached artwork
- const widgets
- selective provider watching
- existing caching
- pagination where supported

Do not sacrifice performance for visual effects.

==================================================
LARGE FILE REFACTORING
==================================================

Priority files include:

    playlists_view.dart
    family_view.dart
    settings_view.dart
    metadata_editor_dialog.dart
    uploads_view.dart
    queue_view.dart

Reduce complexity by extracting meaningful UI components.

Do NOT split files simply to make line counts smaller.

Extract when a component:

- is reused
- has independent state
- is visually complex
- is independently testable
- makes the parent page easier to understand

==================================================
STATE MANAGEMENT
==================================================

Keep the existing state-management architecture.

Do not replace Riverpod or the existing state architecture merely because a new architecture might look cleaner.

New UI should consume existing providers/controllers.

Do not put API calls or business decisions directly into widget build methods.

==================================================
NO DUPLICATE LOGIC
==================================================

Before implementing any new UI behavior, search the repository for existing functionality.

If something already exists:

    USE IT.

Examples:

Upload:

    Existing upload service/provider
        ↓
    New upload UI

Queue:

    Existing queue provider
        ↓
    New queue UI

Playlist replication:

    Existing replica logic
        ↓
    New playlist UI

Account switching:

    Existing account state
        ↓
    New account selector

Do not create parallel implementations.

==================================================
TEST AFTER EACH MAJOR PHASE
==================================================

After each major page or architectural change:

    flutter analyze
    flutter test

Fix regressions immediately.

Do not accumulate dozens of unrelated errors and attempt to fix everything at the end.

==================================================
FUNCTIONAL REGRESSION TESTING
==================================================

After UI work verify:

AUTHENTICATION

- login
- logout
- OAuth
- account connection

ACCOUNTS

- switch account
- multiple accounts
- family mode

LIBRARY

- scan
- search
- filters
- selection
- metadata editing

UPLOADS

- upload
- queue
- progress
- retry
- verification
- duplicate handling

PLAYLISTS

- playlist loading
- playlist watching
- synchronization
- replica behavior
- locker-only behavior
- missing tracks

FAMILY

- account selection
- upload destination
- multi-account uploads

HISTORY

- events recorded
- events displayed

==================================================
UI REGRESSION CHECK
==================================================

Before completion review every major page for:

- broken layout
- inconsistent spacing
- inconsistent colors
- inconsistent typography
- dead buttons
- duplicate actions
- clipped content
- horizontal overflow
- inaccessible controls
- broken dialogs
- broken navigation

==================================================
GIT DISCIPLINE
==================================================

Use logical commits.

Prefer:

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

Do not create one enormous commit containing unrelated work.

==================================================
WHEN TO STOP
==================================================

STOP and report instead of making speculative changes if:

- a backend API change appears necessary
- database changes appear necessary
- OAuth changes appear necessary
- authentication changes appear necessary
- playlist synchronization behavior needs modification
- upload matching behavior needs modification
- multi-account behavior needs modification
- existing functionality conflicts with the UI requirements
- an existing test fails for an unrelated reason

Do not silently modify protected functionality just to make the UI easier to implement.

==================================================
SELF-AUDIT REQUIREMENT
==================================================

After completing each phase:

1. Re-read the relevant section of plan.md.
2. Compare it against the actual implementation.
3. Identify anything missed.
4. Fix omissions.
5. Run analyzer/tests.
6. Update:

    docs/ui-redesign/implementation-status.md

Do not mark a task COMPLETE until it actually satisfies the plan.

==================================================
FINAL AUDIT
==================================================

When all implementation work is finished:

1. Re-read ALL of plan.md.
2. Audit every checkbox.
3. Search the repository for remaining old UI implementations.
4. Check for duplicate components.
5. Check for hard-coded colors that should use the design system.
6. Check responsive layouts.
7. Run:

    flutter analyze
    flutter test

8. Perform a final functional regression review.

==================================================
FINAL REPORT
==================================================

At the end provide a concise but complete report containing:

## Completed

List every completed plan section.

## Partial

List anything that remains partial.

## Not Completed

List anything not completed.

## Files Created

List new files.

## Files Modified

List important modified files.

## Components Created

List shared UI components.

## Pages Redesigned

List every redesigned page.

## Responsive Work

List responsive improvements.

## Accessibility

List accessibility improvements.

## Performance

List performance improvements.

## Tests

Report:

    flutter analyze:
    PASS / FAIL

    flutter test:
    PASS / FAIL

If failures exist, list the exact failures.

## Protected Functionality

Explicitly confirm whether these were changed:

    Backend API:
    OAuth:
    Authentication:
    Upload engine:
    Matching:
    Queue engine:
    Playlist synchronization:
    Playlist replicas:
    Family sync:
    Multi-account behavior:
    Database:

Use:

    NOT CHANGED

unless an actual change was required and documented.

## Remaining Issues

List anything still unresolved.

Do not claim the project is complete if major requirements in plan.md remain unfinished.

==================================================
MOST IMPORTANT INSTRUCTION
==================================================

Use plan.md as the source of truth.

Complete the work systematically.

Do not redesign the application from scratch.

Do not rewrite working backend functionality.

Do not substitute your own feature priorities for the plan.

Improve the UI around the existing Red Music Locker functionality.

The finished application should be:

    FAST
    CLEAN
    DARK
    PREMIUM
    RESPONSIVE
    MUSIC-FOCUSED
    EASY TO USE
    SAFE FOR MULTI-ACCOUNT USE

while preserving the existing synchronization and upload functionality.
