# Improvement A: Deskflow indicator and watchdog

Log formats (~/deskflow.log, set by `[log] file=` in ~/Library/Deskflow/Deskflow.conf):
- `[2026-10-26T23:59:44.572] INFO: switch from "BMS-MAC001" to "replay" at 0,539`
- `[2026-10-26T16:58:02.515] DEBUG: locked by mouse buttonID: 0`

Files: Sources/AmigaViewCore/DeskflowLog.swift (parser, DeskflowState, FileTail), Sources/AmigaView/DeskflowMonitor.swift (glue), AppDelegate.swift (poll in refreshStatus), VideoView.swift (border), README.md.
Tests: DeskflowLogTests (testParsesRealLines, testWatchdogNeedsThreeLocksInTwoSecondsOnAmiga, testSlowLocksDoNotTrigger, testTailReadsOnlyNewLinesAndSurvivesTruncation); DeskflowMonitorTests.testLogDrivesBorderStatusAndRelease (temp log file, injected clock and poster).
Fail checks: removed the locked-line parse -> parser test and monitor test failed; set borderWidth to constant 0 -> monitor test checked (see summary); restored afterwards.
Open: initial owner assumed to be the Mac at start (no log line yet); not tried against live Deskflow; border is 4 pt on the root layer (visual check by user needed); log rotation by inode/truncation only tested for truncation; clock uses arrival time, not log timestamps.
