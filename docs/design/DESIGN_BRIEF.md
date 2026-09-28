# Sentinel — Design Brief

Sources: `ui-ux-pro-max` design-system run ("productivity tool, email triage, AI assistant, calm, dark mode" → Flat style, teal primary, Inter) and the `liquid-glass` skill (material hierarchy, contrast math, Flutter guidance). This file is the **single source of truth** for visuals. Feature code must use the tokens below via `app/lib/core/theme/`; no raw hex, font sizes, radii, durations or paddings in feature widgets.

## 1. Direction

**Calm precision.** A quiet, flat content layer (the mail, summaries, timelines) with one floating **Liquid Glass navigation layer** above it. Color is functional: it encodes category and urgency, never decoration. The app should feel like an instrument, not a marketing site.

Success test: "this feels clean and spatial" — never "someone added blur to everything".

## 2. Layer model (non-negotiable)

| Layer | Elements | Material |
|---|---|---|
| 1. Content | Email tiles, briefing text, timelines, stats | **Flat**: surface color + 1 dp hairline border. No blur, no shadows, no gradients. |
| 2. Structure | Sections, headers, chips rows, lists | **Flat**: spacing + typography do the work. |
| 3. Floating functional UI | Bottom navigation pill, collapsed top app bar | **Glass** (Regular tier). The only `BackdropFilter`s in the app (max 2 on screen). |
| Modal | Bottom sheets, dialogs | **Solid** `surfaceContainerHigh` + scrim. Never glass (no glass-on-glass over the nav). |

Never put `BackdropFilter` inside list items, cards or anything that scrolls.

## 3. Color tokens

Defined once in `SentinelColors` (a `ThemeExtension`) + an explicit Material 3 `ColorScheme` per theme.

### 3.1 Core

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#F8FAFC` | `#0B1220` | Scaffold |
| `surface` | `#FFFFFF` | `#111827` | Cards, tiles |
| `surfaceContainerHigh` | `#F1F5F9` | `#1E293B` | Sheets, dialogs, input fills |
| `outlineVariant` (hairline) | `#E2E8F0` | `#253047` | Card borders, dividers |
| `onSurface` (ink) | `#0F172A` | `#F1F5F9` | Primary text (≥ 12:1) |
| `onSurfaceVariant` (muted ink) | `#475569` | `#A3B1C6` | Secondary text (≥ 4.5:1) |
| `primary` | `#0F766E` | `#2DD4BF` | Primary actions, selection, links |
| `onPrimary` | `#FFFFFF` | `#042F2E` | Text on primary |
| `primaryContainer` | `#CCFBF1` | `#134E4A` | Selected nav indicator, subtle highlights |
| `caution` | `#C2410C` | `#FB923C` | Dry-run banner, "Scan running", warnings |
| `error` / danger | `#B91C1C` | `#F87171` | Errors, destructive confirmations |
| `success` | `#15803D` | `#4ADE80` | Done swipe background, success snackbar icon |

Teal-600 (`#0D9488`) from the generator fails 4.5:1 on white, so light `primary` uses teal-700.

### 3.2 Category colors (always paired with icon + text label — never color alone)

| Category | Label | Icon (`Icons.*`) | Light | Dark |
|---|---|---|---|---|
| `urgent_actionable` | Urgent | `priority_high_rounded` | `#B91C1C` | `#F87171` |
| `project_update` | Project | `account_tree_rounded` | `#1D4ED8` | `#60A5FA` |
| `transactional` | Receipt | `receipt_long_rounded` | `#B45309` | `#FBBF24` |
| `general_fyi` | FYI | `info_outline_rounded` | `#475569` | `#94A3B8` |
| `marketing_promo` | Marketing | `campaign_outlined` | `#7E22CE` | `#C084FC` |
| `spam` | Spam | `report_gmailerrorred_rounded` | `#57534E` | `#A8A29E` |

Category chip = 12 % alpha tint background + full-strength text/icon. Tile accent = 3 dp left bar in the category color.

### 3.3 Urgency

`UrgencyPips`: five 4×12 dp rounded bars, `urgency` of them filled. Fill color: 1–2 `onSurfaceVariant`, 3 `primary`, 4 `caution`, 5 `error`. Semantics label: "Urgency N of 5".

## 4. Liquid Glass material (navigation layer only)

`GlassSurface(tier: GlassTier.regular, borderRadius: …, child: …)` in `core/theme/glass.dart`:

```
ClipRRect(borderRadius)
 └─ BackdropFilter(ImageFilter.blur(sigmaX: blur, sigmaY: blur))
     └─ DecoratedBox(
          color: fill,                       // brand surface with alpha
          border: 1 dp hairline edge,
          gradient overlay: top inner highlight (edge alpha → 0 over top 40 %),
          boxShadow: soft shadow)
         └─ child
```

| Token | Light | Dark |
|---|---|---|
| `glass.regular.fill` | `#FFFFFF` @ 0.72 | `#111827` @ 0.78 |
| `glass.regular.blur` (sigma) | 20 | 20 |
| `glass.regular.edge` | `#FFFFFF` @ 0.55 | `#FFFFFF` @ 0.10 |
| `glass.regular.highlight` | `#FFFFFF` @ 0.60 | `#FFFFFF` @ 0.08 |
| `glass.regular.shadow` | `#0F172A` @ 0.10, blur 24, offset (0, 8) | `#000000` @ 0.45, blur 24, offset (0, 8) |
| `glass.solid.fill` (fallback) | `#FFFFFF` | `#172033` |

Fill alphas sit above the liquid-glass contrast thresholds (light ≥ 0.51, dark ≥ 0.59 for 4.5:1 text) because the nav bar carries text labels.

**Reduce transparency:** when the in-app setting "Reduce transparency" is on, or `MediaQuery.highContrastOf(context)` is true, render the solid fallback with no `BackdropFilter`. Wrap each glass surface in a `RepaintBoundary`.

### 4.1 Floating navigation pill
- 4 destinations, icon + label always visible: **Briefing** (`wb_twilight_rounded`), **Inbox** (`inbox_rounded`), **Projects** (`account_tree_rounded`), **Control** (`tune_rounded`).
- Height 64 dp; horizontal inset 16 dp; bottom = safe-area inset + 12 dp; radius 32 (pill).
- Selected item: `primaryContainer` indicator pill (radius 16) behind a filled icon, label `primary`, weight 600. Unselected: outlined icon, `onSurfaceVariant`.
- Inbox shows a small numeric badge of open urgent items (hide at 0).
- Scrollable content gets bottom padding = 64 + 12 + 16 + safe-area so nothing hides behind the pill.

### 4.2 Top app bar
Large title per tab (`SliverAppBar.large`). Expanded: flat, transparent. Collapsed (scrolled): switches to `GlassSurface` Regular with square corners and a bottom hairline.

## 5. Typography — Inter (bundled `assets/fonts/Inter-Variable.ttf`)

| M3 role | Size / line height | Weight | Use |
|---|---|---|---|
| `displaySmall` | 32 / 40 | 600 | Briefing greeting |
| `headlineSmall` | 24 / 32 | 600 | Screen titles (large app bar) |
| `titleLarge` | 20 / 28 | 600 | Section headers, sheet titles |
| `titleMedium` | 16 / 24 | 600 | Tile subject, card titles |
| `bodyLarge` | 16 / 24 | 400 | Briefing body, summaries in sheets |
| `bodyMedium` | 14 / 20 | 400 | Tile summary, secondary text |
| `labelLarge` | 14 / 20 | 500 | Buttons, chips |
| `labelMedium` | 12 / 16 | 500 | Nav labels, badges, timestamps |

Letter spacing: default (0) for body; −0.2 for display/headline. Numbers in stats, counters and timestamps use `FontFeature.tabularFigures()`. Body text never below 14 sp; must survive 200 % text scale (wrap, don't clip).

## 6. Spacing, shape, elevation

- Spacing scale (dp): `s1 4 · s2 8 · s3 12 · s4 16 · s5 20 · s6 24 · s8 32 · s10 40 · s12 48`. Page gutter 16 (24 when width ≥ 600).
- Radius roles: `control 12` (buttons, fields, icon buttons) · `card 16` (tiles, cards) · `sheet 28` (top corners of sheets/dialogs) · `nav 32` (pill) · `chip 999`. Nested corners follow inner = outer − padding.
- Elevation: content is flat (border, no shadow). Only glass surfaces cast the glass shadow. Sheets use M3 default elevation tint.
- Touch targets ≥ 48 × 48 dp; ≥ 8 dp between targets.

## 7. Motion

| Token | Value |
|---|---|
| `motion.fast` | 150 ms — state changes, chip select, toggle |
| `motion.base` | 220 ms — sheet content, list item insert/remove |
| `motion.slow` | 300 ms — page transitions, briefing reveal |
| Enter curve | `Curves.easeOutCubic` |
| Exit curve | `Curves.easeInCubic`, 70 % of enter duration |
| List stagger | 30 ms per item, first 6 items only |

Rules: every animation expresses cause → effect (swipe follows the finger; dismissed tile collapses; sheet rises from the tapped tile). When `MediaQuery.disableAnimationsOf(context)` is true, use `Duration.zero` and crossfades only. Page transitions: M3 shared-axis horizontal between tabs is **not** used (tabs switch instantly with a 150 ms fade); pushes use the platform default.

**Banned:** hover-to-raise or press-to-lift (translate / elevation / shadow increase), bouncing idle animations, parallax, decorative shimmer on real content (skeletons only while loading), confetti.

Press feedback = Material ink ripple / state layer only.

## 8. Components (build once in `lib/widgets/` or `lib/core/theme/`)

| Widget | Spec |
|---|---|
| `EmailTile` | Card radius 16, 1 dp border, padding 16. Row 1: category chip · project chip (if any) · spacer · relative time (`labelMedium`, tabular). Row 2: sender (`labelLarge`, muted). Row 3: subject (`titleMedium`, max 2 lines). Row 4: summary (`bodyMedium`, muted, max 2 lines). Row 5: `UrgencyPips` + status badges (Trashed / Unsubscribed / Dry run). 3 dp left accent bar in category color. Done items render at 60 % opacity with a check badge. |
| Swipe actions | `Dismissible`-style with thresholds: right (start→end) = Done, background `success` + check icon + "Done" label; left = Reclassify, background `primary` + label icon + "Reclassify". Icon and label slide in with the finger. Haptic `lightImpact` at threshold. Swipe right actually dismisses (with Undo snackbar 5 s); swipe left snaps back and opens the sheet. |
| `EmailDetailSheet` | Solid sheet, radius 28, drag handle. Title = subject; category + urgency row; summary (`bodyLarge`); "What to do" callout when `action_description` present (primaryContainer 40 %, icon `task_alt_rounded`); meta rows (sender, received, project, status); action buttons stacked full-width: primary `FilledButton` Mark done/Mark not done; `OutlinedButton`s Reclassify, Protect sender; Restore from Trash only if `is_trashed`. |
| `ReclassifySheet` | List of the 6 categories as radio tiles with icon + color + label; current one checked; confirm applies immediately and closes. |
| `CategoryChip` | Pill, height 28, 12 % tint, icon 16 + label `labelMedium`. |
| `StatTile` | Flat card: big number (`headlineSmall`, tabular) + label (`labelMedium` muted) + icon. 2×2 grid on phones. |
| `StatusBanner` | Full-width strip under the app bar: offline (error tint, `cloud_off_rounded`, Retry), dry-run (caution tint, `science_outlined`, "Dry run — nothing is really trashed or unsubscribed"), scan running (primary tint + linear progress). |
| `EmptyState` | Centered icon 48 in `primaryContainer` circle, title, one-sentence body, optional action button. |
| `ErrorState` | Same layout, `error` tint, message from `ApiException.userMessage`, Retry. |
| `Skeleton` | Rounded rectangles in `surfaceContainerHigh` with a subtle 1.2 s opacity pulse (0.5 ↔ 1.0); disabled under reduced motion. Tile skeleton mirrors `EmailTile` rows. |
| `SectionHeader` | `titleLarge` + optional trailing text button; 24 top / 8 bottom spacing. |
| `MarkdownBody` | `flutter_markdown_plus` styled with the text theme; links open externally via `url_launcher`; code uses monospace at 13 sp in `surfaceContainerHigh` blocks. |

## 9. Screens (wireframes)

### 9.1 Connect
```
┌─────────────────────────────┐
│  ◎ (shield glyph, primary)  │
│  Connect to Sentinel        │  headlineSmall
│  Your phone must be on      │  bodyMedium muted
│  Tailscale.                 │
│  [ Server URL            ]  │  prefilled http://desktop-h4gp2e6.tail87425d.ts.net:8765
│  [ API token        (eye)]  │  obscured, paste button
│  (error text under field)   │
│  [   Test & connect      ]  │  FilledButton, loading state
│  Where do I find the token? │  TextButton → sheet: "SENTINEL_API_TOKEN in the PC's .env"
└─────────────────────────────┘
```

### 9.2 Briefing (home)
```
 Good morning                      displaySmall ("Good afternoon/evening" by local time)
 Mon 28 Sep · Scanned 3 min ago    labelMedium muted + last-scan chip (tap → Control)
 [StatusBanner if offline / dry-run / scan running]
 ┌ Morning briefing · 08:00 ────┐  card, title + period chip + relative time
 │ Markdown body …              │  collapsed to ~12 lines with "Read more" expander
 └──────────────────────────────┘
 Needs you (3)            See all   SectionHeader → Inbox filtered Urgent
 [EmailTile compact] × ≤5           each with a trailing "Done" icon button
 At a glance
 [Open actions][Project updates]    StatTile 2×2
 [Unsubscribed][Trashed]
 Past briefings                →    ListTile → BriefingHistoryScreen
```
Empty (404): EmptyState "No briefing yet" / "Hermes writes one at 08:00 and 18:00." — rest of the screen still renders.

### 9.3 Inbox
```
 Inbox                     ⟳ Scan  large title + icon button (Scan now)
 (All)(Urgent)(Project)(Receipt)(FYI)(Marketing)(Spam)   horizontal filter chips, single-select
 Show done  ◯                        switch row (labelLarge)
 TODAY                               sticky day header (labelMedium, uppercase, muted)
 [EmailTile]
 [EmailTile]
 YESTERDAY
 …                                   infinite scroll (load next page 400 px before end)
```
Empty per filter: "Nothing urgent. Enjoy the quiet." etc.

### 9.4 Projects → Project timeline
```
 Projects
 ┌ Murphy-Labs/core ─────────── 4 ┐  name titleMedium, open-actions badge (caution) right
 │ 12 updates · 2 h ago · ▮▮▮▯▯   │  meta + max-urgency pips
 └────────────────────────────────┘
```
Timeline screen: title = project name; vertical line (outlineVariant, 2 dp) with dots colored by urgency; each node = time, subject, summary, action callout; tap → EmailDetailSheet.

### 9.5 Control
```
 Control
 ┌ System ─────────────────────────┐
 │ ● Online · v0.2.0               │ status dot (success/error) + version
 │ Mailbox  dl***@gmail.com        │
 │ Model    gemini-3.7-flash       │
 │ Last scan 3 min ago · 4 new     │ tap → Scan history
 │ [        Scan now        ]      │ FilledButton; shows progress + result
 └─────────────────────────────────┘
 Automation                          switches with one-line helper text each
   Dry run (caution color when on)
   Auto-unsubscribe · Auto-trash marketing · Mark processed as read
 Notifications
   Background alerts · Urgent emails · Project updates
   Minimum urgency  [1 ●━━━━ 5]      Slider with labelled stops
 Lists
   Protected senders (12)  →  ListsEditorScreen
   Project keywords (9)    →  ListsEditorScreen
   Unsubscribe history     →
 Appearance
   Theme  (System | Light | Dark)    SegmentedButton
   Reduce transparency               switch
 Connection
   Server  desktop-h4gp2e6…  →  edit sheet
   Disconnect                         TextButton, error color, confirm dialog
 About  Sentinel 0.1.0 (build 12)
```
Every toggle applies immediately (optimistic update, revert + snackbar on failure).

## 10. Icon & splash

Adaptive launcher icon: teal `#0F766E` background, white foreground glyph = rounded shield with a check mark (vector drawable, 108 dp canvas, glyph within the 66 dp safe zone). Monochrome layer for themed icons. Splash: `background` color with the glyph centered (Android 12 splash API via `styles.xml`).

## 11. Accessibility checklist (every screen)

Semantics labels on icon-only buttons · focus/reading order = visual order · 48 dp targets · AA contrast verified in both themes · 200 % text scale without overflow · reduced motion honoured · reduce transparency honoured · color never the only signal (icons + labels on categories, urgency has semantics text) · snackbars don't steal focus.

## 12. Anti-patterns (reject in review)

Glass on cards/tiles/sheets · nested blur · gradients or shadows on content · emoji as icons · raw hex / magic numbers in features · more than one filled primary button per view · hover/press lift · spinners without skeletons for > 300 ms loads · truncating summaries with no way to read the full text · blank screens on error.
