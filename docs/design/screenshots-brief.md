# kWatch — App Store Screenshots Design Brief

**Designer:** <name>
**Project:** Kraftly kWatch
**Deliverable due:** YYYY-MM-DD
**Budget:** $200–400

## Concept

Five screenshots that walk a new user through kWatch's core value:
1. Menu bar live
2. Dashboard overview
3. History trends
4. Settings customization
5. Pro paywall

Each screenshot should be a beautiful, polished rendering of the actual app, NOT a wireframe. Use the design tokens in `kFoundation/Sources/DesignSystem/` (Colors, Spacing, Typography).

## Required screenshots (5 total)

### Screenshot 1 — "Menu bar at a glance"
- Hero shot. Single Mac screen with kWatch menu bar icons visible at the top.
- Captions overlaying in SF Pro Display: "See your Mac in 8 glances."
- 3 visible menu bar icons: CPU gauge (62%), RAM bar (8.1/16 GB), Disk percentage.
- Background: a clean macOS desktop with Finder visible.

### Screenshot 2 — "Dashboard"
- The kWatch Dashboard window showing 6 metric cards in a 3×2 grid.
- Cards: CPU, Memory, Disk, Network, Temperature, Battery.
- Each card shows: large number, small sparkline trend, sub-label.
- Caption: "All seven metrics. One window."

### Screenshot 3 — "24h history"
- The History view showing a line chart for CPU over 24 hours.
- Range picker: 24h / 7d / 30d (24h selected).
- Two metrics overlaid: CPU (top, blue) and Memory (bottom, purple).
- Caption: "24h / 7d / 30d trends. See when things spike."

### Screenshot 4 — "Customize"
- Settings window showing the "Menu Bar" tab.
- Visible controls: which metrics to show, sampling interval, theme picker.
- Caption: "Yours, from top to bottom."

### Screenshot 5 — "Go Pro"
- The Paywall view, prominently showing the crown icon, feature list, and price.
- Caption: "Unlock 30-day history & custom alerts."

## Size variants for each screenshot

- 1280×800 (16:10, standard)
- 1440×900 (16:10, popular)
- 2560×1600 (retina 16:10)
- 2880×1800 (retina 16:10, high-DPI)

Total files: 5 screenshots × 4 sizes = 20 PNG files.

## Color & style

- Background: dark (#0F1012) for menu-bar / dashboard / history; light for settings / paywall
- Accent: #2563EB (kWatch brand blue, per CLAUDE.md §5.4)
- Type: SF Pro Display (Apple system font, freely available)
- Avoid: emoji, drop shadows, glossy buttons

## What NOT to include

- No real user names or emails
- No real metric values that look scary (e.g. 100% CPU looks alarming)
- No third-party logos
- No comparison to iStat Menus or other apps

## Deliverables

ZIP named `kwatch-screenshots-<designer>-<date>.zip`. Each PNG named:
`kwatch-01-menubar-1280x800.png` etc.

## Acceptance criteria

- All 20 PNG files delivered
- All text in English (Chinese / Japanese variants handled separately by you, the engineer)
- Visual matches the kWatch design system in `kFoundation/Sources/DesignSystem/`
- Designer confirms commercial rights transferred

## Designer Notes

Two pre-existing brief inconsistencies to keep in mind when laying out the renders. (1) The Concept list item 1 names "Menu bar live" while Screenshot 2 below describes a 6-card Dashboard — both can coexist, but the hero should not double as the dashboard. (2) Screenshot 2's caption claims "All seven metrics. One window." yet the card list enumerates six (CPU, Memory, Disk, Network, Temperature, Battery). Please flag a preferred resolution (drop one card, or update the caption) before final export so we do not ship a self-contradicting screenshot.
