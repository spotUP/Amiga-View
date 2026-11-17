---
date: 2026-10-24
topic: Input stuck on the Amiga (replay) screen; Mac hotkeys eaten
status: open, not investigated beyond the log
---

# Input stuck on the replay screen

Owner report 2026-10-24: sometimes the pointer cannot leave the Amiga side by moving off the screen, and all
Mac hotkeys go to the Amiga, so the Amiga-View window cannot be left.

## Evidence (~/deskflow.log, 2026-10-24 around 02:07)

- Many `DEBUG: locked by mouse buttonID: 0` lines while on replay: the server believes mouse button 0 is
  held, and Deskflow never switches screens while a button is held. A lost button-up leaves it stuck.
- `INFO: quartz event tap was disabled by timeout, re-enabling` at 02:07:47: macOS disabled Deskflow's event
  tap for a moment; events in that window are dropped, a likely way to lose the button-up.
- The switch back worked once the lock cleared (02:07:45 switch from replay to BMS-MAC001).
- At 02:08:01 `disconnecting client "replay"`.
- Server options (~/Library/Deskflow/deskflow-server.conf): hotkeys Meta+Alt+Control+F12 (to replay) and
  Meta+Alt+Control+F11 (back to the Mac). Deskflow.conf has enableHeartbeat=false, so a frozen client is not
  dropped quickly.
- Amiga-View's SynergySwitch posts mouse moves to the right edge on mouseUp (VideoView.mouseUp,
  AppDelegate.switchSynergy).

## Open questions for the fix session

1. Where is the button-up lost: Amiga-View's posted events, the event tap timeout, or the replay client?
2. Does the F11 hotkey switch back while "locked by mouse button" is set?
3. Should heartbeat be enabled so a hung client releases input?

Work around now: one full click (press and release) clears the lock, then move off the left edge, or
press Ctrl+Option+Cmd+F11 (unverified which Mac key Deskflow maps to Meta).

## 2026-10-26 update

Owner report: trapped on the Amiga after pushing the Amiga-View window past the Mac's right edge;
Cmd+Q goes to the Amiga.

- Fixed in the app (uncommitted): `EdgeGuard` window delegate + `SynergySwitch.clearOfEdge` keep the
  window 16 pt left of the desktop's right edge. Deskflow returns the pointer at x 1790-1798 of 1800,
  so a window over the edge caught it and the next click switched straight back.
  Tests: `SynergySwitchTests.testClearOfEdge*`, `EdgeGuardTests` (fail with the clamp removed).
- Cmd+Q cannot be fixed in Amiga-View: while on replay the Deskflow server owns the keyboard and
  forwards every key. The escape is the Deskflow hotkey Ctrl+Option+Cmd+F11, still unverified (Deskflow
  on macOS may map Cmd to Super, not Meta, in which case `Meta+Alt+Control+F11` never fires).
- Log 23:01:48 to 23:07:12: 5 minutes stuck on replay with 930 `locked by mouse buttonID: 0` lines.
  This lock, not the window, is what blocks moving off the left edge. Cause still open (questions above).

## Open: Amiga screen edges react too early (owner report 2026-10-26)

Owner cannot click things at the edges of the Amiga screen. The replay client reports
`shape=0,0 680x540` to Deskflow. If the Amiga screen mode is a different size, Deskflow clamps and
switches at the reported shape, not the real screen edges. Fix lives in the replay client or the
Amiga screen mode, outside this repo. Need: the real Amiga screen size and where the client source lives.
Client source is NOT in ~/Code/creep-AmigaTools (no synergy/deskflow code there, checked 2026-10-26).
