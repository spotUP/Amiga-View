---
date: 2026-10-27
topic: Deskflow macOS server sends right-hand modifiers as left (Ctrl-Amiga-Amiga reset)
status: PR open (deskflow/deskflow#10338), waiting for review
---

# Deskflow left/right modifier fix (upstream)

Why: Ctrl-Cmd-Cmd from the Mac never reaches the A1200 as Ctrl-LeftAmiga-RightAmiga, so
SynergyClient (UHCTools) never calls ColdReboot. Workaround from Patrik: F12 = RightAmiga
in SynergyClient, so Ctrl-Cmd-F12 resets.

Root cause: `OSXKeyState::handleModifierKeys` (src/lib/platform/OSXKeyState.cpp) diffs only the
device-independent modifier mask and always sends `kKey*_L`. A second Cmd press while the first
is held does not change the mask, so no event at all. Upstream: #5098 closed as dupe of #8486
(open). PR #9916 (merged 2026-08-10) fixed only the client side.

Decision (user, 2026-10-27): fork + upstream PR.

Checkout: ~/Code/deskflow, fork spotUP/deskflow, branch fix/macos-server-left-right-modifiers.

- [x] Fork, clone, branch
- [x] Fix: device-dependent NX_DEVICE*KEYMASK bits pick side; fallback left when no device bits
- [x] Unit test OSXKeyStateTests::handleModifierKeys_leftAndRight
- [x] Build (Qt6 via brew) + run OSXKeyState tests: 7/7 pass. App: ~/Code/deskflow/build/bin/Deskflow.app. Rebuild: `nice -n 19 cmake --build build -j4`; test: `cd build && ./src/unittests/platform/OSXKeyStateTests`
- [x] Revert-check: device bits forced to 0 gives FAIL isKeyDown(COMMAND_R_BUTTON); restored, 7/7 pass
- [x] clang-format: CI pins 20.1.0 (`uvx clang-format==20.1.0 -i <files>`); the 5 changed files already conform, no diff
- [x] Commit 367174b4a, pushed to spotUP/deskflow, PR https://github.com/deskflow/deskflow/pull/10338
- [x] Human test PASSED (user, 2026-10-27): fork server, Ctrl-Cmd-Cmd reboots the A1200
- [x] Fork build installed as /Applications/Deskflow.app (1.27.0.20); release 1.27.0 saved in ~/Code/deskflow-backup/Deskflow-1.27.0-release.zip
