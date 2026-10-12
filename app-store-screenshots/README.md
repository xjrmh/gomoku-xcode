# Just Gomoku App Store screenshots

The publish-ready screenshot sets are in `final-6.5-inch/`, `final-6.9-inch/`, and `final-ipad-13-inch/`. Compact gallery previews are available as `final-contact-sheet.jpg` and `final-ipad-contact-sheet.jpg`.

- 6.5-inch export size: 1284 × 2778 px, portrait
- 6.9-inch export size: 1320 × 2868 px, portrait
- 13-inch iPad export size: 2064 × 2752 px, portrait
- Format: RGB PNG, no alpha channel
- Source capture: iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators on iOS/iPadOS 26.5
- Status bar: fixed at 9:41 with full signal, Wi-Fi, and battery
- UI treatment: source screenshots are preserved exactly and only scaled, rounded, and placed over deterministic marketing backgrounds

Use `final-6.5-inch/` when App Store Connect requests 1284 × 2778 or 1242 × 2688 screenshots. Use `final-6.9-inch/` for the 6.9-inch display slot and `final-ipad-13-inch/` for the 13-inch iPad slot. Apple currently accepts one to ten screenshots.

Source specification: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/

## Gallery order and copy

1. **Five in a row. Zero distractions.** — Pure strategy in a calm, focused space.
2. **Meet your next opponent.** — Choose Easy, Medium, or Hard.
3. **A hint, when you want it.** — Get a nudge only when you ask.
4. **Play it your way.** — Choose board size, stones, appearance, and haptics.
5. **Made for light and dark.** — A focused board in either appearance.
6. **Private by design.** — No analytics or advertising identifiers.
7. **Every game, ready to replay.** — Review results and replay every move.

## Rebuild

Run the composer with a Python environment that includes Pillow:

```sh
python3 app-store-screenshots/compose_screenshots.py
```

The script verifies the source and output dimensions, removes transparency from every export set, writes checksum manifests, and rebuilds both contact sheets.
