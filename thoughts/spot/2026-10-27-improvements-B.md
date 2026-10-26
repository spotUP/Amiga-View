# Picture options and initial Deskflow state (2026-10-27)

## Crop measurement
Source: `http://localhost:8090/snapshot.png` (3 snapshots, identical numbers). It is 720x576, a 720x288 field doubled (row pairs equal).
Method: PIL + numpy; a plain "any pixel above threshold" bounding box is useless (sensor noise gives the full frame), so the column and row MEAN profiles were read at the edges.
- Amiga border colour is grey (mean ~187). Left col 0 and top row 0 are already grey: no left/top margin.
- Right: cols 0..707 grey/content (col 707 mean 174), cols 708..719 black (mean ~10): 12 px margin.
- Bottom: rows 0..573 content (rows 572-573 mean 177), rows 574-575 black (mean 9): one field line.
- Default crop in field pixels: x 0, y 0, width 708, height 287 (display 708x574). `ViewGeometry.defaultCrop`.
- Unverified: I did not look at the image; the crop edge was not checked on a screen. Whether the grey right margin (cols ~683..707) is wanted is a judgement; adjust via defaults cropX/cropY/cropWidth/cropHeight.
- Unverified: contentsRect y is counted from the bottom of the image (non-flipped layer); no pixel render check. Visual check: with Crop Overscan on, the last field line should be gone at the bottom, nothing at the top.

## Files
- Core: `ViewGeometry.swift` (cropRect, displaySize, aspect(of:), contentsRect, fit(content:), integerFit, scanlineAlphas), `PictureOption.swift` (new), `SynergySwitch.swift` (isClickClearOfEdge), `DeskflowLog.swift` (FileTail.history, DeskflowState(history:)).
- App: `VideoView.swift` (crop, integerScaling, scanlines, scanlineLayer, onClick carries screen location), `AppDelegate.swift` (menu items, applyPicture, switchSynergy(clickAt:), performSwitch seam, defaults/frameAutosaveName injection, fullScreenPrimary), `DeskflowMonitor.swift`.
- Tests: `Tests/AmigaViewCoreTests/PictureTests.swift`, `Tests/AmigaViewTests/PictureMenuTests.swift` (menu wiring: crop+integer, scanlines, full screen item, edge click), `DeskflowLogTests.testHistoryGivesInitialState`, `DeskflowMonitorTests.testStartWhileAmigaHasInputShowsBorder`.

## Failure checks (feature broken temporarily, then restored)
- crop (contentsRect forced to full): testCropAndIntegerScaling fails.
- integer (integerFit bypassed): testCropAndIntegerScaling fails.
- edge click (rule forced true): testClickNearTheEdgeDoesNotSwitch + PictureTests edge fail.
- Deskflow history (state not primed): testStartWhileAmigaHasInputShowsBorder fails.

## Open
- Full screen itself (ctrl-cmd-F, aspect, edge click) needs a human test; tests only prove menu item, collection behaviour and the click rule.
- Scanline look at small window sizes (nearest minification drops rows) unchecked visually.
- Wiring tests use a test-only AppDelegate (buildWindow/buildMenu called directly, not applicationDidFinishLaunching).
