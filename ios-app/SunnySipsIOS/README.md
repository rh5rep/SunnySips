# SunnySips iOS (SwiftUI App Source)

This folder contains a complete SwiftUI iPhone app source that reads your hosted snapshot JSON:

- `https://rh5rep.github.io/SunnySips/latest/index.json`
- `https://rh5rep.github.io/SunnySips/latest/<area>.json`

## What is implemented

- Snapshot index + area payload decoding
- Network fetch with cache fallback
- Area selection (`core-cph`, `indre-by`, `norrebro`, `frederiksberg`, `osterbro`)
- Time slot picker (current + forecast hours if present in snapshots)
- Filters: bucket (`all/sunny/partial/shaded`), name search, minimum score
- Map + list + split view modes
- Cafe detail sheet with Apple Maps and Street View deep links
- Color theme aligned with your coffee/gold branding direction

## Quick start in Xcode

1. Open `/Users/rami/Documents/SunnySips/ios-app/SunnySipsIOS/SunnySips.xcodeproj`.
2. Select the `SunnySips` scheme.
3. Run on an iPhone simulator.

## Source layout

- `SunnySips/App`: app entry, root content view, config, theme
- `SunnySips/Models`: JSON models for snapshot payloads
- `SunnySips/Services`: network + cache service
- `SunnySips/ViewModels`: screen state and filtering logic
- `SunnySips/Views`: map/list/detail UI

## Configuration

If your GitHub Pages URL changes, edit:

- `SunnySips/App/AppConfig.swift`
