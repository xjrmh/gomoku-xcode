# Design QA — Bottom-Pinned Mobile Match Dock

- Source visual truth: `/var/folders/w9/c5pmyygd46ggrzyzj0zqsr4h0000gn/T/codex-clipboard-5bda4d2f-fa8b-4479-935d-ab7f322d8cb9.png`, together with the user's refined requirements that the wide mobile dock retain left/right padding and sit at the bottom above the iPhone home indicator.
- Implementation screenshot: `/Users/lizheng/Downloads/gomoku-xcode/design-renders/mobile-bottom-dock.png`
- Full-view comparison: `/Users/lizheng/Downloads/gomoku-xcode/design-renders/mobile-bottom-dock-comparison.png`
- Viewport: iPhone 17 Pro simulator, iOS 26.5, 402 × 874 points at 3×.
- Source pixels: 502 × 168 component crop.
- Implementation pixels: 1206 × 2622 full-screen capture.
- Normalization: the prior and final 1206 × 2622 simulator captures were each scaled to half-width and placed side by side. The combined comparison was exported at 2× as 2412 × 2622 pixels.
- State: light appearance, AI / Hard, 13 moves, Your move. The source's move count and clocks differ because they are live game data rather than fixed dock copy.

## Findings

No actionable P0, P1, or P2 differences remain for the requested mobile dock placement.

- The glass surface uses a small, even 8-point inset from the left and right viewport edges in the 402-point compact layout.
- The dock is pushed to the bottom of the safe content area, leaving the system home-indicator region unobstructed.
- Undo and Hint receive equal flexible widths while retaining the centered symbol-plus-label treatment and divider from the source.
- The surrounding board, toolbar, mode control, clock row, and vertical layout remain visible without clipping or horizontal overflow.

## Required Fidelity Surfaces

- Fonts and typography: native San Francisco `subheadline` labels and SF Symbols remain unchanged, single-line, and legible.
- Spacing and layout rhythm: the dock's former 14-point outer inset is reduced to 8 points; a flexible spacer pins it to the safe-area bottom with an additional 8-point bottom inset. The internal 14-point padding, 10-point vertical padding, 26-point radius, clock spacing, and row rhythm are preserved. Each action fills one half of the available row.
- Colors and visual tokens: the existing neutral Liquid Glass surface and semantic primary/secondary foreground styles are unchanged.
- Image quality and asset fidelity: no raster assets or approximated icons were introduced. Shipping SF Symbols remain sharp at simulator density.
- Copy and content: `Moves`, both clocks, `Undo`, and `Hint` are preserved. Numeric differences from the source reflect the live game state.

## Full-View and Focused Evidence

- Full-view evidence: `/Users/lizheng/Downloads/gomoku-xcode/design-renders/mobile-bottom-dock-comparison.png` places the prior centered placement and final bottom-pinned placement side by side at the same viewport. It confirms the dock moves to the safe-area bottom while preserving the board, controls, width, and visual treatment.
- Focused evidence was not needed for this refinement because the changed relationship—dock position relative to the full screen and home-indicator safe area—is clearest in the full-view comparison. The supplied component crop remains the source of truth for the dock's internal treatment.

## Comparison History

1. First rendered pass — the dock reached both mobile edges and the two actions distributed evenly without truncation, overlap, or overflow.
2. Refinement pass — restored an 8-point horizontal inset at the user's request. The final capture shows even breathing room on both sides with no new clipping or alignment issue.
3. Bottom-placement pass — inserted flexible vertical space above the dock so it lands at the bottom safe-area boundary. The final iPhone 17 Pro capture confirms sufficient clearance for the home indicator.

## Interaction, Accessibility, and Test Checks

- Undo remains wired to `game.undo()` and Hint remains wired to `game.askForHint()`.
- Existing enabled/disabled logic remains in place through `game.canUndo` and `game.canHint`.
- Both controls preserve a minimum 44-point height and now gain larger horizontal hit regions.
- All 17 unit tests passed on the iPhone 17 Pro simulator.
- The two existing UI tests still fail independently of this width change: the persisted 13-move board makes the test's center tap land on an occupied cell, and the accessibility audit reports the previously known app-wide Dynamic Type issue.

## Implementation Checklist

- [x] Reduce the compact layout's outer horizontal dock inset to 8 points.
- [x] Expand the glass surface to near-full compact viewport width.
- [x] Pin the dock to the bottom safe-area boundary.
- [x] Preserve 8 points of additional clearance above the system home-indicator region.
- [x] Split Undo and Hint into equal flexible-width actions.
- [x] Preserve native symbols, typography, divider, disabled states, and 44-point minimum height.
- [x] Build, capture, visually compare, and run the unit test suite.

## Follow-up Polish

No dock-specific follow-up is required. The state-dependent UI test and existing Dynamic Type audit failure can be addressed separately.

final result: passed
