# Amiga-View

A small native macOS app that shows the live video of a real Amiga A1200, so you can test without walking to it. It only shows video. Keyboard and mouse control stay with Synergy / Deskflow.

## How it works

A Raspberry Pi 4 grabber runs `camserver.py` (from Up_Rough_Demo_System, `tools/amiga_cam`) and listens on the Pi's localhost only:

- `GET /stream.mjpg` multipart MJPEG, about 50 fields per second, each 720x288.
- `GET /snapshot.png` newest frame.
- `GET /audio.pcm` live sound from the grabber's audio input: raw s16le, 48000 Hz, stereo (camserver `--audio-device`).

On launch Amiga-View checks whether `localhost:8090` answers. If not, it starts
`ssh -N -L 8090:localhost:8090 amigrabber` (key login, BatchMode; `amigrabber` is the Host entry in ~/.ssh/config that names the key ~/.ssh/amigrabber_ed25519) and stops it again on quit. It then reads the MJPEG stream, keeps only the newest frame, and draws it scaled 2x vertically (720x576) with nearest-neighbour scaling. When the stream drops it reconnects with backoff (0.5 s doubling to 8 s) and polls `/snapshot.png` once per second meanwhile. The status line at the bottom left shows "Connecting", "Tunnel failed: reason", "No signal", or the measured FPS.

## Build and run

    swift build            # debug build
    swift test             # unit tests and end-to-end stream test (local test server, no Pi needed)
    scripts/bundle.sh      # release build into build/Amiga-View.app, with the icon drawn by scripts/make-icon.swift
    open build/Amiga-View.app

## Sound

Amiga-View plays `/audio.pcm` on the default output. It keeps about 60 ms buffered so the sound stays with the picture: after a gap it waits until 60 ms are buffered again, and a backlog over 150 ms is dropped. When camserver serves no audio, it retries quietly with the same backoff as the video.

## Measuring

    "$(swift build --show-bin-path)/Amiga-View" --stats

prints every 5 s to stderr: frames drawn per second, audio bytes received, audio buffered (ms), underruns, dropped frames. UserDefaults keys can be given for one run as arguments, e.g. `-host 127.0.0.1 -port 8097 -via ""`.

## Settings

Stored in UserDefaults for `com.spotup.amiga-view`; change with `defaults write`:

    defaults write com.spotup.amiga-view host localhost
    defaults write com.spotup.amiga-view port -int 8090
    defaults write com.spotup.amiga-view via amigrabber

The tunnel is only started when `host` is `localhost` or `127.0.0.1` and `via` is not empty. Window position and size are remembered; "Always on Top" is remembered too.

## Menu

View: Actual Size (720x576), Double Size (1440x1152), Always on Top, Crop Overscan, Integer Scaling, Scanlines, Enter Full Screen (ctrl-cmd-F), Switch Synergy on Click, Sound. The window keeps the aspect ratio of the picture when resized.

- Crop Overscan: shows only the area where the Amiga draws, 708x287 field pixels (the grabber's black margins on the right and bottom go away). Override the rectangle with the `cropX`, `cropY`, `cropWidth`, `cropHeight` defaults (field pixels, from the top left).
- Integer Scaling: draws the picture at the largest whole multiple of its size that fits the window, centred on black; the normal fit when even 1x does not fit.
- Scanlines: darkens the second display row of every field line by 35 percent.
- Enter Full Screen: standard macOS full screen. Press Esc or ctrl-cmd-F to leave it (the status line says so for 3 s on entering); keys only reach the Mac while it has the input. Clicks within 16 points of the right edge of the desktop do not switch Synergy, because Deskflow returns the pointer there.
- Each option is stored in the defaults (`picture.cropOverscan`, `picture.integerScaling`, `picture.scanlines`) and survives a restart.

## Snapshot and recording

The File menu saves what the window shows.

- **Save Snapshot** (cmd-S) writes the newest frame as a PNG to the Desktop, named `Amiga-View 2026-10-27 at 14.03.09.png`. It is the displayed picture: every line doubled (720x576), cropped when Crop Overscan is on.
- **Start Recording** / **Stop Recording** (cmd-R) writes `Amiga-View <date> at <time>.mov` to Movies: H.264 video at the displayed size, plus AAC sound when Sound is on. Picture times follow frame arrival, so a stalled stream shows as a pause; sound is timed by sample count from the first frame. The status line shows `Recording 00:12` and the frame rate. Quitting finishes the file. A frame backlog is dropped rather than slowing the display.

## With Deskflow

Deskflow on this Mac has the screen "replay" to the right of BMS-MAC001; the Synergy client on the A1200 receives input there. Place the Amiga-View window near the right edge of the Mac screen, so the pointer crosses the edge into "replay" close to the picture of the Amiga. The window always stays 16 points clear of that edge: Deskflow brings the pointer back from the Amiga just inside it, and a window there would catch the pointer so the next click sends input straight back to the Amiga. To leave the Amiga, move the pointer off its left edge; Cmd+Q and other Mac shortcuts go to the Amiga while it has the keyboard. Turn on "Always on Top" to keep the picture visible while you work.

### Who has the input

Amiga-View follows the Deskflow server log (`~/deskflow.log`, or the path in the `deskflowLog` default). At start it reads the last 64 KB to learn who has the input (the newest `switch` line), then follows the end. While "replay" has the keyboard and mouse, the video gets a border in the system accent colour and the status line reads "Amiga has keyboard and mouse - leave off the left edge". Both go away when the input is back on the Mac.

Deskflow sometimes believes a mouse button is held and then refuses to switch screens (it logs `locked by mouse buttonID: 0` over and over). When the log shows 3 such lines within 2 seconds while the Amiga has the input, and Accessibility is granted, Amiga-View posts one left mouseUp (at most once per 2 s) and shows "Released a stuck mouse button" for 3 s. This mitigates a Deskflow state bug whose root cause is still open.

### Switch Synergy on Click

Clicking in the video window (also the click that activates it) moves keyboard and mouse to the Amiga: on release, Amiga-View posts mouse moves that carry the pointer across the right edge of the desktop, the same edge crossing that switches Deskflow by hand. No Deskflow hotkey is needed; Deskflow ignores posted hotkeys, so a switchToScreen keystroke cannot be triggered from the app.

Grant Accessibility to Amiga-View (System Settings, Privacy and Security, Accessibility); without it the status line shows "Grant Accessibility to switch Synergy on click" and the click does nothing. At most one switch per 500 ms. Turn it off in View, "Switch Synergy on Click" (stored as `switchSynergyOnClick`, default on). To return, move the mouse off the Amiga's left edge.

## Licence

MIT (see LICENSE), except `pi/stk1160`, a modified Linux driver under GPL-2.0.
