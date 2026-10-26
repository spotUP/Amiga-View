# Snapshot and recording (improvements C)

Done. Files:
- Sources/AmigaViewCore/ViewGeometry.swift: `displayImage(from:crop:)` (pure, crop then 2x nearest).
- Sources/AmigaViewCore/CaptureFile.swift: file names (with " 2" suffix when taken), PNG encoding, mm:ss clock.
- Sources/AmigaViewCore/Recorder.swift: AVAssetWriter, own queue, drops backlog (max 25 frames) and never blocks.
- Sources/AmigaViewCore/AudioStreamClient.swift: lock-protected `onPCM` tap.
- Sources/AmigaView/AppDelegate.swift: File menu, `handleFrame`, `snapshotDirectory`/`recordingDirectory`/`recordingFinished` seams, flash status (3 s), "Recording mm:ss - N FPS", finish on terminate.
- Tests: Tests/AmigaViewCoreTests/CaptureTests.swift (4), Tests/AmigaViewTests/CaptureMenuTests.swift (3). README section added.

Failure checks (temporary breaks, reverted): no vertical doubling -> display test fails (and the app tests); audio write disabled -> audio-track assertion fails; fixed-rate timestamps -> stall duration test (0.08 vs 0.56) fails; date format without "at" -> name test fails; saveSnapshot and toggleRecording no-ops -> both wiring tests fail.

Open:
- Stopping is asynchronous (status "Saving ..." then "Saved ..."); quitting blocks until finished.
- Sound toggled while recording does not add/remove the audio track; audio presence is fixed at start.
- Not run by hand with the real Amiga stream or real ~/Desktop, ~/Movies (tests use temp dirs). Manual check: cmd-S and cmd-R in the running app.
- The Recording status is prefixed to the FPS/No signal text; Deskflow "Amiga has input" text overrides it.
