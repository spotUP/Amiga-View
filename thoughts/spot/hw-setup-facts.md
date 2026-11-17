# Hardware / Setup facts (read-only gathered 2026-10-27)
## Hardware
- Pi: Raspberry Pi 4 Model B Rev 1.1 (ssh: cat /proc/device-tree/model). IPs 192.168.0.72 and .50 (hostname -I), host amigrabber.local.
- Capture: USB STK1160 (lsusb: 05e1:0408 Syntek STK1160 Video Capture Device) on /dev/video0 (v4l2-ctl). Analog S-Video/composite box (pi/camserver.py:11-16).
- Input: --channel 4 = S-Video (camserver.py:13; unit file). PAL, 720x576, uyvy422, 25 fps. Replay scandoubler must be OFF for S-Video (camserver.py:15-17).
- Audio: same device, ALSA card STK1160 (arecord -l: card 3 STK1160 USB Audio); unit uses --audio-device hw:CARD=STK1160,DEV=0; stream s16le 48000 stereo (README.md:11).
- Also on Pi USB: FTDI FT232 serial (0403:6001) for serial bridge (~/amiga/serialbridge.py) - not Amiga-View's.
- Network: Pi on LAN (192.168.0.x); A1200 at 192.168.0.74 (README/commit 05071ee); camserver binds 127.0.0.1 only, "no login: reach by SSH tunnel" (camserver.py:482).
- Exact video cable (S-Video cable from Amiga/Replay out) not documented beyond "S-Video/composite box beside the Replay since 2026-10-05" (camserver.py:11).
## Pi software
- OS Debian 13 trixie, kernel 6.18.50+rpt-rpi-v8, Python 3.13.5 (ssh cat /etc/os-release, uname -r, python3 --version). ffmpeg and arecord installed (/usr/bin).
- camserver.py: Python stdlib + ffmpeg (+ arecord from alsa-utils) (camserver.py:33 docstring; imports line 34). Default port 8090, --listen default 127.0.0.1 (lines 481-482).
- Started by user systemd unit ~/.config/systemd/user/amiga-cam.service (Restart=always, RestartSec=3, WantedBy=default.target; loginctl Linger=yes so it runs at boot without login). ExecStart: /usr/bin/python3 %h/amiga/camserver.py --device /dev/video0 --size 720x576 --input-format uyvy422 --channel 4 --standard PAL --fps 25 --snap-fps 1 --field-order tff --port 8090 --audio-device hw:CARD=STK1160,DEV=0. Copy in Up_Rough_Demo_System/tools/amiga_cam/amiga-cam.service (not read).
- Source: camserver.py comes from ~/Code/UpRough/Up_Rough_Demo_System/tools/amiga_cam (note underscores; README.md:5 of Amiga-View). Repo copy in /Users/spot/Code/Amiga-View/pi/camserver.py. Pi copy at ~/amiga/camserver.py.
- Patched stk1160: pi/stk1160/ (Makefile:1-8: out-of-tree, kernel source raspberrypi/linux stable_20260911, kernel 6.18.50+rpt, obj-m += stk1160.o, KDIR=/lib/modules/$(uname -r)/build). stk1160-fieldfix.h: pure helpers repairing a field after lost USB packet (stk1160_fix_field); fieldfix_test.c host test.
- Install on Pi: ~/stk1160-build/install.sh (ssh cat): make; stop amiga-cam; copy stk1160.ko to /lib/modules/$K/updates/; depmod -a; modprobe -r/modprobe stk1160; start amiga-cam. Installed module present at /lib/modules/6.18.50+rpt-rpi-v8/updates/stk1160.ko. Needs kernel headers (build dir). No dkms (dkms: not found) so must be rebuilt after kernel upgrade.
## Mac
- ~/.ssh/config: Host amigrabber / HostName amigrabber.local / User spot / IdentityFile ~/.ssh/amigrabber_ed25519 (no Port/other lines shown).
- Deskflow: screen "replay" to the right of BMS-MAC001 (README.md:77). Log ~/deskflow.log via [log] file= in ~/Library/Deskflow/Deskflow.conf (thoughts/spot/2026-10-27-improvements-A.md:3). Server conf ~/Library/Deskflow/deskflow-server.conf, hotkeys Meta+Alt+Control+F12 (to replay) / F11 (back) (thoughts/spot/2026-10-24-stuck-on-replay.md:20). enableHeartbeat=false (same, :21).
## Amiga
- A1200 at 192.168.0.74 (git log 05071ee). Synergy client named "replay"; reports shape=0,0 680x540 (stuck-on-replay.md:52).
- wasabid: UP-Term kit Install, tick wasabid -> installs wasabid 0.11b2 in C:, key in ENVARC:wasabi.key, marked block in S:User-Startup, started at boot, port 1234 (~/Code/UP-Term/vtcon/tools/nas/README.md:113-115; tools/rig/install_rig.py:1549-1560). Key copied on Mac to ~/.config/up-term/replay-wasabi.key (README.md:73). Needs private LAN, never forward 1234 (nas/README.md:108-111). Client: vendored Resources/wasabi/wasabi.py run with /usr/bin/python3.
## Could not confirm
- Synergy client on the A1200: SynergyClient from UHCTools (Patrik, 2026-10-27). It resets on Ctrl-LeftAmiga-RightAmiga via ColdReboot(); F12 maps to RightAmiga, so Ctrl-Cmd-F12 resets from a Mac whose Deskflow sends both Cmd keys as LeftAmiga (deskflow/deskflow#5098). F12 alone collides with nothing: the Deskflow hotkey is Meta+Alt+Control+F12.
- Exact cable/adapter from A1200 to the STK1160; "Replay" (FPGA Amiga) vs A1200 naming mixed in camserver.py docs: unclear whether the video source is the A1200's own output or a Replay board.
- Exact STK1160 EasyCAP branding; modinfo unavailable on Pi (not in PATH, /sbin/modinfo exists).
- tools/amiga_cam in UpRough is at Up_Rough_Demo_System (not Up-Rough-Demo-System); its README is about an older HDMI/MS2130 setup, not current.
- Pi network is wired vs wifi not checked; Deskflow version not checked.
