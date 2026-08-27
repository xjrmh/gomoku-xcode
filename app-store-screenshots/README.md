# Just Gomoku App Store screenshots

The publish-ready iPhone screenshot set is in `final-6.9-inch/`. A compact gallery preview is available as `final-contact-sheet.jpg`.

- Export size: 1320 × 2868 px, portrait
- Format: RGB PNG, no alpha channel
- Source capture: iPhone 17 Pro Max simulator on iOS 26.5
- Status bar: fixed at 9:41 with full signal, Wi-Fi, and battery
- UI treatment: source screenshots are preserved exactly and only scaled, rounded, and placed over deterministic marketing backgrounds

The export size is one of Apple's accepted 6.9-inch screenshot resolutions. Apple currently accepts one to ten screenshots and scales the highest-resolution set for smaller iPhone display classes when needed.

Source specification: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/

## Gallery order and copy

1. **Five in a row. Zero distractions.** — Pure strategy in a calm, focused space.
2. **Meet your next opponent.** — Choose Easy, Medium, or Hard.
3. **A hint, when you want it.** — Get a nudge only when you ask.
4. **Play it your way.** — Choose board size, stones, appearance, and haptics.
5. **Made for light and dark.** — A focused board in either appearance.
6. **Private by design.** — No analytics or advertising identifiers.

## Rebuild

Run the composer with a Python environment that includes Pillow:

```sh
python3 app-store-screenshots/compose_screenshots.py
```

The script verifies the source and output dimensions, removes transparency from the final exports, writes a checksum manifest, and rebuilds the contact sheet.
