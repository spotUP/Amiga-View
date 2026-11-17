---
date: 2026-10-27
topic: Session handoff - Deskflow left/right modifier fix, frame rate in toolbar, README Reset section
tags: [handoff, deskflow, toolbar, readme]
status: final
---

# Handoff 2026-10-27

## Task(s)
- README Reset section: explain how Ctrl-Amiga-Amiga reaches the A1200 over Deskflow. Done (commit b1f4e36).
- Frame rate moved from the picture overlay into the toolbar. Done (commit a6c0e40).
- Upstream Deskflow fix so a macOS server sends right-hand modifiers as right-hand keys
  (Ctrl-Cmd-Cmd now reboots the A1200). Done, PR open, human test passed.
- Fork build of Deskflow installed in /Applications. Done.

## Critical References
- Deskflow ledger: `thoughts/spot/2026-10-27-deskflow-left-right-modifiers.md` (root cause, build and test commands).
- Setup facts: `thoughts/spot/hw-setup-facts.md` (Pi, capture, Deskflow config, SynergyClient reset keys).
- Frame rate code: `Sources/AmigaView/AppDelegate.swift` (`frameRateText()`, `updateFrameRateItem()`,
  `statusMessage()` returns nil while frames are fresh), `Sources/AmigaView/Toolbar.swift` (`.frameRate` item,
  toolbar identifier `main.2`), `Sources/AmigaView/VideoView.swift` (status label hides when empty).
- Test: `Tests/AmigaViewTests/CaptureMenuTests.swift` `testFrameRateShowsInTheToolbar`.

## Recent Changes
- Amiga-View, branch main, NOT pushed: b1f4e36 (README Reset section), a6c0e40 (frame rate in toolbar).
- Deskflow fork `~/Code/deskflow`, branch `fix/macos-server-left-right-modifiers`, commit 367174b4a, pushed to
  spotUP/deskflow. PR https://github.com/deskflow/deskflow/pull/10338 (Fixes #8486, also #5098).
- `/Applications/Deskflow.app` is now the fork build (version 1.27.0.20). The release 1.27.0 bundle is saved as
  `~/Code/deskflow-backup/Deskflow-1.27.0-release.zip`. Client "replay" reconnected after the swap.

## Learnings
- SynergyClient (UHCTools) on the A1200 cold-reboots on Ctrl-LeftAmiga-RightAmiga. F12 maps to RightAmiga,
  so Ctrl-Cmd-F12 works with stock Deskflow; Ctrl-Cmd-Cmd needs the fork / PR #10338.
- Deskflow root cause: `OSXKeyState::handleModifierKeys` diffed only the device-independent modifier mask and
  always sent the left key. Fix reads the device-dependent `NX_DEVICE*KEYMASK` bits.
- Deskflow CI pins clang-format 20.1.0: run `uvx clang-format==20.1.0 -i <files>`.
- Deskflow rebuild: `nice -n 19 cmake --build build -j4`; tests: `cd build && ./src/unittests/platform/OSXKeyStateTests`.
- The fork build links Homebrew Qt by absolute path (`/opt/homebrew/opt/qtbase`). Removing or upgrading brew
  qtbase across a major version breaks the installed app.
- The fork bundle is unsigned, so macOS Accessibility permission may need to be granted again after each rebuild/copy.
- `open` on the fork bundle exited silently earlier; starting `Contents/MacOS/Deskflow` directly works.
  Cause unverified (stale `/tmp/deskflow-gui` socket or single-instance check, deskflow-gui.cpp:101).
- `swift test --num-workers` needs `--parallel`.

## Artifacts
- PR: https://github.com/deskflow/deskflow/pull/10338
- Ledger: `thoughts/spot/2026-10-27-deskflow-left-right-modifiers.md`

## Next Steps
1. Push Amiga-View main (b1f4e36, a6c0e40) when wanted.
2. Follow PR #10338 review; answer reviewer comments on the fork branch.
3. After a Deskflow release contains the fix: reinstall the official release in /Applications, and update the
   README Reset section to say Ctrl-Cmd-Cmd works (F12 workaround only for older Deskflow).
4. Untested: Ctrl-Cmd-F12 reboot path (human test).

## Other Notes
- Toolbar hides in full screen, so the frame rate is not visible there.
- Toolbar identifier change to `main.2` resets a saved hidden-toolbar state once.
- Open by user choice, waiting for a repro: `thoughts/spot/2026-10-24-stuck-on-replay.md`.
