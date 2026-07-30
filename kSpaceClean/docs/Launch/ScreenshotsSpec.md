# Screenshots Spec — kSpaceClean v1.0

## Required Dimensions
Mac App Store requires screenshots in these dimensions (5 minimum, 10 maximum):

| Display | Resolution | Required? |
|---|---|---|
| 2560×1600 | MacBook Pro 13" (default) | YES — at least 3 |
| 2880×1800 | MacBook Pro 15"/16" | YES — at least 1 |
| 1440×900 | MacBook Air 13" | optional but recommended |
| 1280×800 | Legacy | optional |

We recommend producing **5 screenshots at 2560×1600** (universal) + **1 hero shot at 2880×1800**.

## Required Scenes

### Screenshot 1 — Hero (2880×1800)
- **Scene:** Main scan results view, 4-level tree fully expanded
- **Copy overlay:** "Reclaim gigabytes in one tap."
- **Caption (alt text):** Four-level risk-graded tree showing system caches, application leftovers, and old downloads with checkboxes
- **File name:** `sclean-hero-2880x1800.png`

### Screenshot 2 — Smart Categories (2560×1600)
- **Scene:** Sidebar showing 6 categories with item counts and total sizes
- **Copy overlay:** "Six categories. Endless clarity."
- **File name:** `sclean-categories-2560x1600.png`

### Screenshot 3 — Risk Grading (2560×1600)
- **Scene:** Detail view of a category with mixed Recommended/Optional/Caution/Dangerous items, color-coded badges
- **Copy overlay:** "4-level risk. No surprises."
- **File name:** `sclean-risk-2560x1600.png`

### Screenshot 4 — Cleanup Confirmation (2560×1600)
- **Scene:** The CleanupConfirmSheet showing risk-graded summary before action
- **Copy overlay:** "Confirm what you're deleting. Always."
- **File name:** `sclean-confirm-2560x1600.png`

### Screenshot 5 — Menu Bar Widget (2560×1600)
- **Scene:** System menu bar showing kSpaceClean icon with live disk usage popover
- **Copy overlay:** "One click from anywhere."
- **File name:** `sclean-menubar-2560x1600.png`

## Production Notes
- All screenshots must be **retina** (@2x). Render at 2× and downsample.
- All text overlays use SF Pro Display, 56pt, white with 2pt black stroke for legibility on any background.
- Avoid real customer data — use synthetic fixtures (created in ScreenshotFixtureKit).
- Aspect ratio: 16:10 landscape (matches all MacBook Retina displays).

## File Locations
Save final PNGs in `kSpaceClean/docs/Launch/Screenshots/` (one folder per locale):
- `kSpaceClean/docs/Launch/Screenshots/en-US/`
- `kSpaceClean/docs/Launch/Screenshots/zh-CN/` (overlay text translated)
- `kSpaceClean/docs/Launch/Screenshots/ja/` (overlay text translated)