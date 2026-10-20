---
date: 2026-10-21
topic: Amiga-View tearing frames and 34 vs 50 parts/s
status: fps fixed on the Pi (camserver.py field pacing); tearing root cause proven, fix is in the kernel driver (open)
---

# Tearing and 34 vs 50 parts/s, measured 2026-10-20 ~23:50 (Pi uptime 11 min)

The "50" is PAL fields: 25.19 interlaced 720x576 frames/s from the stk1160, split by
`separatefields` into 2 x 720x288 fields. The two problems have **different causes**.

## Baseline (before)

| Measure | Value |
|---|---|
| Pi ffmpeg encoder out (`/health` stream_frames delta over the 5 s curl) | 252 fields / 5 s = 50.4/s |
| Pi localhost curl 5 s, `grep -ac '^--'` | 245, 242, 243 parts |
| Mac via tunnel, 5 s | 240, 241 parts; 10 s client: 48.6/s, avg part 34.9 KB |
| Mac part gap histogram (ms: count) | <2: 126, 2-5: 55, 5-10: 40, 10-15: 12, 15-25: 20, 25-35: 78, 35-50: 138, >50: 14 |
| short buffers (`/health` short_frames / frames) | 10739 / 14608 = 73%; in the 5 s window 98/126 = 78% |
| Pi CPU (`top -b -n1`) | 70% idle on 4 cores; stream ffmpeg 45-57% of one core, python 9-15%, v4l2-ctl 2-9%. Not the limit. |
| dmesg | `URB packet 42, status -18` (EXDEV, isoc packet missed) ~25/s; all 1940 logged lines name packet 42 |

## (2) 34 not 50 parts/s: fields published in pairs, viewers keep only the newest

- The stk1160 hands over a buffer only when both fields are in, so `separatefields` emits field 1
  and field 2 of a frame back to back (181 of 483 gaps under 5 ms, the rest 25-50 ms), though they
  were captured 20 ms apart.
- camserver's `stream()` handler sends only the newest JPEG (`body, seq = cap.jpeg, cap.jpeg_seq`):
  when field 2 lands before the handler takes field 1, field 1 is lost. The app also keeps only the
  newest frame and draws once per display refresh, so a <5 ms pair shows as one picture.
- How many are lost depends on load (bigger JPEGs, 2 clients): 168/5 s = 34/s before the reboot,
  243/5 s = 48.6/s right after; the encoder makes 50.4/s in both cases.

**Fix shipped (one file, ~/amiga/camserver.py, backup camserver.py.bak-2026-10-21):** `read_stream()`
holds a field that comes under half a field period after the previous one until one field period
(20 ms) after it. A field that comes later is never held, so the device's 25.19 frames/s (faster
than 25) builds no backlog. Cost: +20 ms latency on the second field of each pair.

| After (service restarted) | Value |
|---|---|
| Pi localhost curl 5 s | 250 parts (encoder 252) = 50/s |
| Mac via tunnel, 10 s | 501 parts = 50.2/s |
| Mac gap histogram | <5: 16, 5-10: 25, 10-15: 76, 15-25: 265, 25-35: 101, 35-50: 15, >50: 2 |
| short buffers | 103/126 = 82% (unchanged; device side, see below) |

## (1) Tearing: a missed isoc packet shifts the rest of the field by 2044 bytes

Raw capture: service stopped ~5 s, `v4l2-ctl --stream-mmap --stream-no-query --stream-count=75
--stream-to-hdr` (25.19 fps), parsed on the Mac with numpy. The Amiga picture was static (7 whole
frames vs the first whole one: 0 differing rows).

- Short buffers are short by **2044, 4088, 6132 bytes** (38, 17, 1 of 75; 19 whole): whole multiples
  of one isoc packet's payload (2044), not of a line (1440). The missing data is not "the last lines".
- In every short buffer of the first 25, per field: from some row on, the field equals the
  reference field read **2044 bytes further on** (<1% of bytes differ by >40), i.e. one packet's
  bytes are gone and everything after it moved up 1 line + 604 bytes (302 pixels) = a horizontal
  tear. One shift per missing packet: 2044-short frames have one torn field, 4088-short have both.
- The tear row drifts ~5 rows a frame (field 0: 154, 164, ... 183, 188; field 1: 108, 113, 118):
  a band crawling down the picture, matching the always-packet-42 error beating against the field.
- camserver's padding (black at the end, `read_frame`) only fills the tail; it cannot undo the shift,
  and the frame handed to ffmpeg is already torn by the driver.

Root cause level: kernel, stk1160 driver (6.18.50+rpt-rpi-v8). On a packet with error status it
logs (`print_err_status`) and skips the packet without advancing the buffer position, so the next
packet's bytes are written where the lost ones belonged. Fix there: on an errored packet, advance the
position by the packet payload (2044) so the hole stays in place (a 302-pixel gap on one line instead
of a shifted rest of field); or remove the reason packet 42 is missed (Pi 4 VL805 xHCI isoc schedule;
not investigated). Both are outside camserver.py, so not shipped. Not fixable in userspace without
guessing where the packet went missing.

## Owner eye-check
- Motion should look smoother (50 distinct fields/s instead of ~34).
- Tearing remains: a horizontal shear band that crawls down the picture, in ~3 of 4 frames.
