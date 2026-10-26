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

View: Actual Size (720x576), Double Size (1440x1152), Always on Top, Switch Synergy on Click. The window keeps its 5:4 aspect ratio when resized.

## With Deskflow

Deskflow on this Mac has the screen "replay" to the right of BMS-MAC001; the Synergy client on the A1200 receives input there. Place the Amiga-View window near the right edge of the Mac screen, so the pointer crosses the edge into "replay" close to the picture of the Amiga. The window always stays 16 points clear of that edge: Deskflow brings the pointer back from the Amiga just inside it, and a window there would catch the pointer so the next click sends input straight back to the Amiga. To leave the Amiga, move the pointer off its left edge; Cmd+Q and other Mac shortcuts go to the Amiga while it has the keyboard. Turn on "Always on Top" to keep the picture visible while you work.

### Switch Synergy on Click

Clicking in the video window (also the click that activates it) moves keyboard and mouse to the Amiga: on release, Amiga-View posts mouse moves that carry the pointer across the right edge of the desktop, the same edge crossing that switches Deskflow by hand. No Deskflow hotkey is needed; Deskflow ignores posted hotkeys, so a switchToScreen keystroke cannot be triggered from the app.

Grant Accessibility to Amiga-View (System Settings, Privacy and Security, Accessibility); without it the status line shows "Grant Accessibility to switch Synergy on click" and the click does nothing. At most one switch per 500 ms. Turn it off in View, "Switch Synergy on Click" (stored as `switchSynergyOnClick`, default on). To return, move the mouse off the Amiga's left edge.

## Licence

MIT (see LICENSE), except `pi/stk1160`, a modified Linux driver under GPL-2.0.
