# Red Music Locker — Responsive Design Strategy

The application layout adapts fluidly across mobile phones, tablets, and wide desktop displays without layout breakage, clipped fields, or RenderFlex overflows.

---

## 1. Breakpoint System

The application employs three primary breakpoint tiers:

| Tier | Width Range | Target Devices | Layout Mode |
| :--- | :--- | :--- | :--- |
| **Mobile** | `< 600px` | Phones (iPhone SE, iPhone 14/15, Pixel, Galaxy) | Single-column, bottom navigation bar, full-screen dialogs |
| **Tablet** | `600px – 1024px` | iPads, Android tablets, compact desktop windows | Dual-pane or compact grid, rail navigation (icons only) |
| **Desktop** | `> 1024px` | Laptops, desktop monitors, ultra-wide displays | Multi-column, expanded rail navigation with text labels |

---

## 2. Navigation Behavior

The primary shell navigation dynamically transforms depending on viewport width:

### Mobile Viewport (`< 600px`)
- **Widget**: `NavigationBar` (Material 3 bottom navigation bar).
- **Position**: Pinned to the bottom of the viewport with safe area padding.
- **Content**: Primary destination icons with active pill indicator.
- **Advantage**: Thumb-accessible navigation on handheld devices without consuming horizontal space.

### Tablet Viewport (`600px – 1024px`)
- **Widget**: `NavigationRail` (collapsed).
- **Position**: Pinned to the left side of the viewport.
- **Label Type**: `NavigationRailLabelType.none` or `.selected`.
- **Advantage**: Leaves maximum screen width available for table columns and media grids while keeping quick-switch navigation accessible.

### Desktop Viewport (`> 1024px`)
- **Widget**: `NavigationRail` (expanded).
- **Position**: Left sidebar with branding logo, app title, version tag, and full text destination labels.
- **Width**: Constrained to 220px–240px.
- **Advantage**: Full clarity, professional desktop feel, and instant visual orientation.

---

## 3. Viewport Behaviors

### Mobile (`360px – 430px`)
- **Page Headers**: Titles and action buttons wrap using `Wrap` or stack vertically to prevent horizontal overflow.
- **Stat Cards**: Render as a 2-column or 1-column wrapped grid (`Wrap` with `runSpacing: 12`).
- **Data Lists**: Track lists switch to compact density mode (`isDense: true`), hiding less critical columns (bitrate, file size) while keeping title, artist, and primary action menu.
- **Input Forms**: Multi-field rows (such as Folder Path + Browse button) switch to vertical column arrangements so buttons don't crush text inputs.
- **Empty States**: Wrapped in `SingleChildScrollView(physics: BouncingScrollPhysics())` so soft keyboards or short screens never trigger vertical RenderFlex overflow.

### Tablet (`768px – 1024px`)
- **Stat Cards**: Display in 2 or 4 equal columns.
- **Media Grids**: Render 3 to 4 album cards per row.
- **List Tables**: Show title, artist, album, duration, and status badge.

### Desktop (`1024px – 1440px+`)
- **Max Width Bounds**: Views are constrained to comfortable reading and interaction widths (or fill available canvas with generous horizontal margins).
- **Media Grids**: Render 5 to 6 cards per row with smooth hover lift effects.
- **Full Column Exposure**: Lists display complete metadata including audio format, bitrate, file size, match confidence score, and replica sync badges.

---

## 4. Dialog & Modal Behavior

Dialogs adapt significantly between mobile and desktop environments.

### `MetadataEditorDialog` & Modal Forms
- **Desktop (`>= 600px`)**:
  - Presented as a centered modal `Dialog`.
  - Width: Constrained to `620px`.
  - Max Height: `90%` of screen height.
  - Border Radius: `AppRadius.dialog` (16px).
  - Bottom Actions: Horizontal row aligned to the trailing edge.
- **Mobile (`< 600px`)**:
  - Presented as a near-full-screen modal (`insetPadding: EdgeInsets.all(8)`).
  - Width: `double.infinity` (matches screen width).
  - Max Height: `96%` of screen height.
  - Border Radius: `AppRadius.card` (12px).
  - Bottom Actions: Action buttons stack vertically (`CrossAxisAlignment.stretch`) using `LayoutBuilder`, ensuring primary "Save & Upload" and "Cancel" buttons are always large, touch-accessible, and never clipped.
  - Header: Section titles are truncated with ellipsis if viewport is extremely narrow.
  - Artwork Section: Image and action buttons automatically stack vertically on screens narrower than 450px.

---

## 5. Viewport Test Matrix

All 8 views and dialogs are verified using automated widget layout tests (`test/responsive_layout_test.dart`):

| Viewport Width | Device Target | Tested & Verified |
| :--- | :--- | :--- |
| **360px** | Small Android (Galaxy S8, Xperia) | PASS (0 overflow errors) |
| **390px** | Standard iPhone (iPhone 12/13/14) | PASS (0 overflow errors) |
| **430px** | Large iPhone (iPhone 14/15 Pro Max) | PASS (0 overflow errors) |
| **768px** | Tablet Portrait (iPad Mini, iPad 10.2) | PASS (0 overflow errors) |
| **1024px** | Tablet Landscape / Small Laptop | PASS (0 overflow errors) |
| **1440px** | Standard Desktop Monitor | PASS (0 overflow errors) |
