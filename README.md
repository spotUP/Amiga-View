# Amiga-View

A small native macOS app that shows the live video of a real Amiga A1200, so you can test without walking to it. It only shows video. Keyboard and mouse control stay with Synergy / Deskflow.

## How it works

A Raspberry Pi 4 grabber runs `camserver.py` (from Up_Rough_Demo_System, `tools/amiga_cam`) and listens on the Pi's localhost only:

- `GET /stream.mjpg` multipart MJPEG, about 50 fields per second, each 720x288.
- `GET /snapshot.png` newest frame.

On launch Amiga-View checks whether `localhost:8090` answers. If not, it starts
`ssh -N -L 8090:localhost:8090 spot@amigrabber.local` (key login, BatchMode) and stops it again on quit. It then reads the MJPEG stream, keeps only the newest frame, and draws it scaled 2x vertically (720x576) with nearest-neighbour scaling. When the stream drops it reconnects with backoff (0.5 s doubling to 8 s) and polls `/snapshot.png` once per second meanwhile. The status line at the bottom left shows "Connecting", "Tunnel failed: reason", "No signal", or the measured FPS.

## Build and run

    swift build            # debug build
    swift test             # unit tests and end-to-end stream test (local test server, no Pi needed)
    scripts/bundle.sh      # release build into build/Amiga-View.app
    open build/Amiga-View.app

## Settings

Stored in UserDefaults for `com.spotup.amiga-view`; change with `defaults write`:

    defaults write com.spotup.amiga-view host localhost
    defaults write com.spotup.amiga-view port -int 8090
    defaults write com.spotup.amiga-view via spot@amigrabber.local

The tunnel is only started when `host` is `localhost` or `127.0.0.1` and `via` is not empty. Window position and size are remembered; "Always on Top" is remembered too.

## Menu

View: Actual Size (720x576), Double Size (1440x1152), Always on Top. The window keeps its 5:4 aspect ratio when resized.

## With Deskflow

Deskflow on this Mac has the screen "replay" to the right of BMS-MAC001; the Synergy client on the A1200 receives input there. Place the Amiga-View window against the right edge of the Mac screen, so the pointer crosses the edge into "replay" right next to the picture of the Amiga. Turn on "Always on Top" to keep the picture visible while you work.
