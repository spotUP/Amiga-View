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

## Kernel fix for the tear: patched stk1160 (built, NOT installed)

Source: `pi/stk1160/`, stock files from raspberrypi/linux tag `stable_20260911` (matches the
running `6.18.50+rpt-rpi-v8`, built 2026-09-11, package 1:6.18.50-1+rpt1); first commit is the
pristine copy, the next is the patch (`git diff` of the two shows the whole change).
Change: `stk1160_process_isoc` on an errored packet inside a field calls `stk1160_skip_video`,
which advances `buf->pos` and `bytesused` by the last good packet's payload (`len - 4`, 2044
measured), so the rest of the field stays in place and only a stale strip remains. Counter
`isoc_ctl.lost_pkts`, printed rate-limited with `dev_dbg` (enable via dynamic debug).

Status: compiled on the Pi (no warnings, `~/stk1160-build/stk1160.ko`). Install and the
before/after measurement were NOT done: `sudo` on the Pi needs a password (`sudo -n` refused), and
installing a module needs root.

Install by hand on the Pi (one time per kernel):
```
cd ~/stk1160-build && make && systemctl --user stop amiga-cam \
 && sudo mkdir -p /lib/modules/$(uname -r)/updates && sudo cp stk1160.ko /lib/modules/$(uname -r)/updates/ \
 && sudo depmod -a && sudo modprobe -r stk1160 && sudo modprobe stk1160 \
 && /sbin/modinfo stk1160 | head -3 && systemctl --user start amiga-cam
```
Revert: `sudo rm /lib/modules/$(uname -r)/updates/stk1160.ko && sudo depmod -a`, reload the module.
After a kernel update (apt): the new kernel has its own modules dir, so the patched module is
not used; fetch the matching tag's driver files into `pi/stk1160/`, re-apply the patch, then
repeat the command above (headers package must match: `sudo apt install linux-headers-$(uname -r)`).

## After the patched module (installed 2026-10-21 00:08, measured 00:29)

| Measure | Value |
|---|---|
| Loaded module | srcversion DF9F29A103C21784221566B = /lib/modules/6.18.50+rpt-rpi-v8/updates/stk1160.ko (stock F3D8524B8BA1A037A15BF78) |
| Pi localhost curl 5 s | 250 parts = 50/s |
| short buffers (`/health` short_frames delta) | 0 of 254 in the 5 s window (was 78%); total stuck at 132 since load |
| dmesg `status -18` | still present (USB loss is unchanged; the patch keeps the hole in place instead of shifting the field) |
| `out of bounds offset` / `offset out of bounds` | at the ratelimit cap (120/min) both before (stock, 23:38-23:40) and after; not caused by the patch |

Note: `dmesg | grep -c` over a 5 s window reads 0 because the ring buffer is full; count from `journalctl -k` per minute instead.
Open: the owner's eye check that the tear band is gone.

## Offset frames after the patch: the skip overshoots by 1024 bytes (measured 2026-10-21 ~00:50)

Owner: "same tear band", "some frames shifted down and right" (screenshot
`~/Pictures/claude-inbox/CleanShot 2026-10-21 at 00.44.38@2x.png`). Method: binary usbmon
(`/dev/usbmon1`, MON_IOCX_GETX from Python, service running, nothing restarted) logging every isoc
completion of the video endpoint (0x82, 64 packets per URB): per packet status, actual_length and the
4-byte header. 250 URBs (2 s), then 1125 URBs. usbmon unloaded afterwards.

| Measure | Value |
|---|---|
| Packet sizes (actual_length) | 3072 (11378), 2048 (3242), 4 (1091), 8 (100), odd tails (588, 1612, ...) |
| Lost packets (status -18) | 51 of 250 URBs, always index 42 |
| Index 42 when received | 3072 x179, 4 x15, never 2048 (indices 40/41/43/44 get 2048 ~51 times each) |
| Payload per field without a loss | 414720 = 720*2*288 in 49 of 49 |
| Shortfall of a field with one loss | exactly 2044 in 50 of 51 (one field short by 31260, not explained) |
| `last_payload` at each loss | 3068 in every sampled case (the packet before is a 3072 one) |
| Losses at a field marker / in blanking | 0 of 51 (all mid-field, pos 12272..406980) |

So the lost packet is always one of the device's 2048-byte packets (2044 payload), while the patch
skips by the previous packet's payload, 3068. The rest of the field lands 1024 bytes late = 512
pixels right (pixels past x=208 wrap to the next field line = 2 frame lines down). The screenshot
agrees: below the tear row the text sits ~871 screenshot px right of the same text above it
(1232 px wide for 720 = 1.71x, so ~509 capture px, i.e. 512). Before the patch the field moved
2044 bytes early (up/left); now it moves 1024 bytes late (down/right). Hypotheses 2-4 (marker lost,
camserver pairing, whole-frame shift) ruled out: every loss is mid-field and the field marker
packets all arrive.

Header byte 1 (low 6 bits) is a per-packet sequence counter (..., 0x29, lost, 0x2b, ...), so a
loss is visible in the stream, but the lost packet's size is not: the device mixes 3072 and 2048
packets (3-4 of 3072 between each 2048) to hit the field rate.

Fix (proposed, not built): `pi/stk1160/stk1160-video.c`. Do not guess the size at loss time.
On an errored packet record `hole_pos = buf->pos` and `holes++` (no advance). At field end (the
next 0x80/0xc0 marker, before `pos = 0` / `stk1160_buffer_done`), compute
`deficit = width*2*(height/2) - buf->pos`; if `holes == 1 && 0 < deficit <= 3068`, move the field
bytes `[hole_pos, pos)` later by `deficit` in field-linear coordinates (line by line from the end,
since field lines interleave in the buffer: offset(p) = (p / bpl)*2*bpl + (odd ? 0 : bpl) + p % bpl),
and add `deficit` to `bytesused`. Exact for any lost size; at most one field memmove (<415 KB) per
loss, ~10/s. More than one loss in a field or a bigger deficit: leave as is (rare). The cheaper
"skip 2044" variant matches today's measurements only by coincidence of the device's packet mix.
Upstream cause (VL805 xHCI misses the 2048-byte packet in slot 42) still not investigated.

## Shortfall fix (installed 2026-10-21 ~00:55)

Replaces the 3068-byte guess. On a lost packet the driver no longer moves `pos`; it records `holes`
and `hole_pos` per field. At field end (0x80 marker, and `stk1160_buffer_done` for the second field)
`stk1160_field_end()` computes shortfall = bpl*(height/2) - pos; with exactly one hole and
1 <= shortfall <= max_pkt_size-4 it moves the bytes after the hole later by the shortfall
(`stk1160_fix_field()` in `pi/stk1160/stk1160-fieldfix.h`, backwards, interleaved mapping shared with
`stk1160_copy_video` via `stk1160_field_addr()`) and adds the shortfall to `bytesused`.
Host test `pi/stk1160/fieldfix_test.c`: 10 cases (5 hole offsets, both parities) all correct with the fix;
the old skip model misplaces 5693..412672 bytes per case.

Pi: srcversion DF9F29A103C21784221566B -> 21ACE068F5BBA68C50E48BC. The kernel has no dynamic debug, so
counters are exposed as read-only module parameters (`lost_total`, `fixed_total`, `unfixed_total`
in /sys/module/stk1160/parameters). Measured over 5 s windows (no restart between):

| Window | parts | lost | corrected | left unfixed | short_frames delta |
|---|---|---|---|---|---|
| 1 | 250 | 131 | 127 | 2 | 2 |
| 2 | 250 | 126 | 126 | 0 | 0 |
| 3 | 249 | 129 | 129 | 0 | 0 |
| 4 | 250 | 128 | 129 | 0 | 0 |
| 5 | 250 | 128 | 126 | 1 | 0 |

(Counts are approximate to +-1 because the reads race the stream.) About 98% of lost packets are
corrected; the 1-2 per 5 s left unfixed (2+ holes or shortfall out of range) still yield a short
frame (short_frames rose 1 -> 6 over ~35 s). Not done: the usbmon field-total check (corrected fields
ending at 414720 is inferred from short_frames = 0 in clean windows). Open: the unfixed cases.
