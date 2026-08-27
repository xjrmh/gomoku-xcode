# Design QA — Selected Option 1, Centered Board

## Comparison Target

- Source visual truth: `/Users/lizheng/Downloads/gomoku-xcode/design-audit/2026-08-26-redesign-exploration/05-option-1-revised-move-caption.png`
- Implementation screenshot: `/Users/lizheng/Downloads/gomoku-xcode/design-renders/implementation-option-1-centered.png`
- Full-view comparison: `/Users/lizheng/Downloads/gomoku-xcode/design-renders/option-1-centered-comparison.png`
- Target surface: compact iOS gameplay screen in light appearance.
- Implementation device: iPhone 17 Pro simulator, iOS 26.5, 402 × 874 points at 3×.
- Source pixels: 852 × 1846, representing the requested 390 × 844 concept viewport.
- Implementation pixels: 1206 × 2622.
- Normalization: the source was scaled to 1206 pixels wide and vertically centered against the 1206 × 2622 implementation pane. The combined comparison was exported at 2× as 4824 × 5244 pixels.
- State: both show AI · Hard and Move 13 in light appearance. The source contains illustrative clocks, turn copy, and stone placement; the implementation shows live persisted game data.

## Findings

No actionable P0, P1, or P2 visual differences remain.

The following visible differences are intentional rather than defects:

- The generated source board is vertically stretched and does not contain a square N × N play field. The implementation preserves a square 15 × 15 board so touch mapping, replay, rules, and stone geometry remain correct.
- The implementation includes the real iOS status bar and Dynamic Island. The source intentionally omitted device chrome; app-owned content was compared below that boundary.
- The source says `Black's turn` with illustrative 04:35 / 04:52 clocks. The persisted implementation state correctly says `Your move` for the human white side and shows its live clocks.
- The exact stones differ because the implementation renders the real saved 13-move game rather than copying decorative mock data.
- Native iOS 26 Liquid Glass is slightly more neutral and context-dependent than the generated glass approximation. The hierarchy, translucency, connected control grouping, and edge treatment match the design intent.
- The board is vertically centered between the pinned HUD and action dock per the latest user direction; this intentionally creates more space above the board than the earlier generated concept.

## Required Fidelity Surfaces

- **Fonts and typography:** native San Francisco semantic styles match the source's platform-native character. Status remains semibold, clocks use restrained subheadline sizing, mode and move labels use secondary caption hierarchy, and dock labels are centered without truncation. Accessibility text sizes explicitly reflow the HUD into two rows instead of compressing essential values.
- **Spacing and layout rhythm:** the HUD spans the compact viewport with an 8-point outer inset; the board uses a 14-point screen inset; `Move 13` sits directly below and aligns to the board's trailing edge; the 288-point action island remains centered above the bottom safe area. The square-board constraint creates more flexible space above the dock than the malformed source board, but the dock's bottom relationship remains faithful.
- **Colors and visual tokens:** the app background is warm off-white; the board is a uniform pale-maple surface with quiet brown grid, edge, and star-point tokens. Glass controls use native adaptive material. Black and porcelain-white stones retain distinct edges in light and dark appearances.
- **Image quality and asset fidelity:** no rasterized UI, placeholder art, handcrafted SVG, or fake icon asset was introduced. The interactive board remains a resolution-independent SwiftUI Canvas and all controls use shipping SF Symbols.
- **Copy and content:** `Move 13` is removed from the HUD and rendered as the requested small trailing caption below the board. `Undo`, `Hint`, `New Game`, and `AI · Hard` match the selected design. Live turn and clock values remain model-driven.

## Full-View And Focused Evidence

- Full-view evidence: `/Users/lizheng/Downloads/gomoku-xcode/design-renders/option-1-centered-comparison.png` places the normalized source and final simulator capture together. It verifies hierarchy, margins, glass grouping, centered board treatment, caption placement, and dock placement.
- A separate focused crop was not needed: the normalized full-view comparison retains roughly 1206 pixels per viewport, leaving all HUD text, icons, grid lines, caption, and dock labels clearly readable.

## Comparison History

1. **First implementation pass:** established the match HUD, uniform intersection grid, star points, glossy stones, last-move ring, trailing move caption, and three-action dock. The HUD reflowed to two rows at the standard viewport, creating a P2 hierarchy mismatch.
2. **Second implementation pass:** compacted normal-size typography and spacing so the HUD remained on one row. The glass surface still hugged its intrinsic content and the action island remained wider than the source, leaving P2 width drift.
3. **Third implementation pass:** expanded the HUD glass to the intended full-width inset and reduced the action island to 288 points. Color and stone rendering were also refined. Visual comparison found no remaining P0/P1/P2 mismatch.
4. **Accessibility refinement:** the UI audit exposed Dynamic Type compression and an undersized semantic status region. The HUD now explicitly switches to its two-row layout at accessibility sizes and maintains 44-point semantic height. The focused accessibility audit and full test suite both pass after the fix.
5. **Centered-board refinement:** the compact screen now overlays its square board at the vertical center of the available gameplay area while keeping the HUD and dock pinned. A geometry cap reduces the board on shorter screens. The final 19-test suite, including the accessibility audit and board interaction flow, passes after the layout change.

## Interaction, Accessibility, And Test Checks

- Board placement, mode selection, New Game configuration, Settings, and History navigation were exercised by UI tests.
- Undo and Hint retain their existing enabled/disabled rules and actions.
- New Game is a real menu with restart, PvP, and AI difficulty choices rather than static chrome.
- All three dock actions provide at least 44-point touch height.
- The board preserves named accessibility actions, announcements, keyboard input, haptics, and precision placement.
- XCTest accessibility audit passed for Dynamic Type, hit regions, and sufficient element descriptions.
- Full test result: 19 of 19 tests passed on iPhone 17 Pro, iOS 26.5.
- The shared target also completed a clean macOS Debug build after the cross-platform SwiftUI changes.

## Implementation Checklist

- [x] Consolidate turn, clocks, and mode in one Liquid Glass HUD.
- [x] Remove the persistent segmented mode control.
- [x] Replace checkerboard cells with a uniform intersection board and star points.
- [x] Keep the production board square and input mapping correct.
- [x] Replace the last-move dot with the selected hollow ring.
- [x] Move `Move 13` below the board and align it right.
- [x] Build a centered Undo / Hint / New Game glass island.
- [x] Keep About reachable through Settings after removing the third toolbar icon.
- [x] Reflow the HUD for accessibility text sizes.
- [x] Vertically center the compact board between the HUD and action dock.
- [x] Build, capture, compare, exercise interactions, and run the complete test suite.

## Follow-up Polish

- P3: dark appearance, 19 × 19 precision placement, iPad split layout, and macOS inspector remain good candidates for a separate visual QA pass because this source target specifies only the compact light screen.

final result: passed
