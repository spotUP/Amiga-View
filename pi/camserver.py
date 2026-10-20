#!/usr/bin/env python3
"""camserver.py -- runs on the Raspberry Pi next to the Amiga: serves the latest
frame of an HDMI/DVI-to-USB grabber as a PNG, so the demo system can SEE the
real machine's screen (a demo takes the OS over, so amiagent's own screenshot
is blind exactly when it matters).

  camserver.py [--device /dev/video0] [--size 720x576] [--input-format yuyv422]
               [--channel N] [--standard PAL]
               [--fps 10] [--snap-fps 2] [--port 8090] [--listen 127.0.0.1] [--test]

An ANALOG grabber (the STK1160 S-Video/composite box beside the Replay since
2026-10-05) needs two more choices an HDMI grabber does not have: which input
(--channel; the STK1160 lists Composite0..3 and S-Video = 4) and which TV
standard (--standard PAL; the driver wakes up in NTSC-M at 720x480, and a PAL
Amiga then rolls). It offers only uyvy422. The Replay's scandoubler must be OFF
for S-Video: at 31 kHz each captured line holds two Amiga lines and the screen
appears twice side by side (measured 2026-10-05).

  GET /snapshot.png   the newest frame (PNG, lossless; header X-Frame-Age-Ms).
                      503 when no frame is newer than 5 s: a stale picture of
                      a machine that has since crashed is worse than none.
  GET /stream.mjpg    multipart/x-mixed-replace MJPEG of the separated FIELDS: an
                      interlaced 25 fps PAL capture becomes 50 pictures a second
                      at 720x288 (one field = one Amiga frame; show it 2x tall).
  GET /health         JSON: ok, age_ms, restarts, size, source, field order, stream.

One ffmpeg child holds the device and rewrites latest.png (atomically) at
--snap-fps; it is restarted when it dies (a grabber that is unplugged and
plugged back in) AND when it is alive but has written no frame for
--stall-seconds (the Replay switched off and on: the stk1160 stream stalled and
the service served 503 until a hand restart, measured 2026-10-05). --test uses ffmpeg's test card instead of a device, which is
how the suite checks this without hardware. Python 3 stdlib + ffmpeg only.
"""
import argparse, http.server, json, os, queue, struct, subprocess, tempfile, threading, time

STALE_MS = 5000


V4L2_FOURCC = {"uyvy422": "UYVY", "yuyv422": "YUYV"}
BOUNDARY = "uprough"
BLACK_UYVY = bytes([0x80, 0x10, 0x80, 0x10])    # two black pixels, U Y V Y
AUDIO_RATE = 48000
AUDIO_CHUNK = AUDIO_RATE // 100 * 4                # 10 ms of s16le stereo
AUDIO_KEEP = 50


class Capture:
    """One capture, two outputs: the PNG snapshot (latest.png at --snap-fps) and a
    live MJPEG of the separated FIELDS (2 x --fps; one PAL field = one Amiga frame).
    Three processes: the source (v4l2-ctl, or ffmpeg's test card), the stream encoder
    and the snapshot encoder; camserver pumps the raw frames between them (cmds()).

    The device is read by `v4l2-ctl --stream-mmap` and piped into ffmpeg as raw
    video. ffmpeg's own v4l2 reader got only 5.8-6.1 of the stk1160's 25 frames a
    second on the Pi 4 while v4l2-ctl got 25.2 (measured 2026-10-06, ledger
    thoughts/shared/plans/2026-10-06-50fps-amiga-view.md F1). v4l2-ctl also sets
    input, standard and format BEFORE streaming: started the other way round the
    driver logs `offset out of bounds` and discards frames."""

    def __init__(self, a):
        self.a = a
        # One field per driver buffer (V4L2_FIELD_ALTERNATE, the patched stk1160): a field leaves
        # as soon as it is captured. In a whole interlaced frame the first field waited a field
        # period (~20 ms) for the second, and camserver then had to hold the second ~20 ms to
        # space the pair (measured 2026-10-21: 9.8 and 28.4 ms from frame end to HTTP out).
        self.alt = a.fields == "alternate" and not a.test and a.reader == "v4l2-ctl"
        self.dir = tempfile.mkdtemp(prefix="amiga-cam-")
        self.png = os.path.join(self.dir, "latest.png")
        self.restarts = -1
        self.stop = False
        self.child = None
        self.reader = None
        self.snap = None
        self.short_frames = 0     # frames the driver handed over with fewer (or more) bytes than a frame
        self.started = time.time()
        self.jpeg = None
        self.jpeg_seq = 0
        self.jpeg_time = 0.0
        self.cond = threading.Condition()
        self.audio = None             # arecord
        self.audio_chunks = []        # newest AUDIO_KEEP chunks of AUDIO_CHUNK bytes
        self.audio_seq = 0            # number of the newest chunk
        self.audio_time = 0.0
        self.audio_restarts = -1
        self.audio_rms = []           # per-chunk RMS of the last second, for /health
        self.acond = threading.Condition()

    def setup_device(self):
        a = self.a
        w, h = a.size.split("x")
        cmd = ["v4l2-ctl", "-d", a.device]
        if a.channel is not None:
            cmd += ["-i", str(a.channel)]
        if a.standard:
            cmd += ["-s", a.standard.lower()]
        # field= always: the driver keeps the last format set, so a run in one mode would leave
        # the next run of the other mode with the wrong buffer layout (half-black fields).
        fmt = "width=%s,height=%s,pixelformat=%s,field=interlaced" % (
            w, h, V4L2_FOURCC.get(a.input_format, a.input_format))
        if self.alt:
            fmt = "width=%s,height=%d,pixelformat=%s,field=alternate" % (
                w, int(h) // 2, V4L2_FOURCC.get(a.input_format, a.input_format))
        cmd += ["-v", fmt]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def frame_bytes(self):
        w, h = self.buf_size().split("x")
        return int(w) * int(h) * 2          # uyvy422 / yuyv422: 2 bytes a pixel

    def buf_size(self):
        """WxH of one buffer from the source: a field in alternate mode, else the frame."""
        w, h = self.a.size.split("x")
        return "%sx%d" % (w, int(h) // 2) if self.alt else self.a.size

    def cmds(self):
        """(source, stream encoder, snapshot encoder): three processes, camserver in the middle.

        ONE ffmpeg with two outputs (the stream and a 1/s snapshot) stalled the whole graph
        ~0.6-0.9 s once a second on the Pi 4 -- 34 fields/s instead of 50 -- whatever the
        snapshot's filter (fps / select) or encoder (png / mjpeg); the stream alone ran a
        smooth 47-50 (measured 2026-10-06, ledger F2). So camserver reads the raw frames and
        feeds two encoders; the snapshot one is fed only when it is idle, so it can never
        hold the stream up. The test card takes the same path (ffmpeg as the source)."""
        a = self.a
        if a.test:
            # -re: at the card's own frame rate, like a grabber (unpaced it ran at thousands a second)
            source = ["ffmpeg", "-nostdin", "-loglevel", "error", "-re", "-f", "lavfi", "-i",
                      "testsrc2=size=%s:rate=%d" % (a.size, a.fps), "-f", "rawvideo", "-pix_fmt", a.input_format,
                      "pipe:1"]
        elif a.reader == "v4l2-ctl":
            # DEFAULT. --stream-to-hdr: each frame prefixed by "rdhV" + its real byte count (big-endian);
            # read_frame() pads a short one. 25 frames/s from the stk1160 (the Replay's fields end 1-2
            # isoc packets before line 288, so ~70% of buffers are short). --stream-no-query: without it
            # v4l2-ctl QUERYSTDs and sets the "PAL or SECAM" mask, the saa7113 decodes SECAM and the
            # picture loses its colour (ledger F2b, 2026-10-20).
            # No -i / -s here: v4l2-ctl prints "Video input set to ..." on stdout ahead of the first
            # header, read_frame() found no "rdhV", the source ended before frame 1 and the encoder,
            # fed nothing, exited -22. setup_device() sets input and standard first.
            source = ["v4l2-ctl", "-d", a.device, "--stream-mmap", "--stream-no-query", "--stream-to-hdr=-"]
        else:
            # ffmpeg's own v4l2 reader, raw frames to stdout. It discards every buffer that is
            # not a whole frame, so from the Replay it passes ~6 frames/s -- but all of them whole and
            # in colour (measured 2026-10-06: 40 of 40). Setting input + standard happens in ITS open.
            source = ["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "v4l2"] + \
                     (["-standard", a.standard] if a.standard else []) + \
                     (["-channel", str(a.channel)] if a.channel is not None else []) + \
                     ["-input_format", a.input_format, "-video_size", a.size, "-framerate", str(a.fps),
                      "-i", a.device, "-fps_mode", "passthrough", "-flush_packets", "1", "-f", "rawvideo",
                      "pipe:1"]  # passthrough: real frames only, never repeated to fill a 25 fps output
        # -probesize/-analyzeduration: the raw format is fully stated, so do not let ffmpeg read ~5 MB
        # first -- at 1 snapshot a second that held the first PNG back ~6 s after every (re)start.
        raw = ["-probesize", "32", "-analyzeduration", "0", "-f", "rawvideo", "-pix_fmt", a.input_format,
               "-video_size", self.buf_size()]
        # -flush_packets 1: without it ffmpeg's 32 KB pipe buffer released fields in bursts.
        # -thread_type slice: the mjpeg encoder's default frame threading held 3 fields back (a
        # field came out only when later ones went in: 1, 1, 2, 2 parts for frames 0-3 fed 300 ms
        # apart), ~60 ms of latency at 50 fields/s. Slice threads put both fields out within
        # ~10 ms of their frame and still encode 217 fields/s on the Pi 4 (measured 2026-10-21).
        # Alternate: the buffers already are the fields, 2 x --fps of them; else split each frame.
        if self.alt:
            rate, vf = 2 * a.fps, []
        else:
            rate, vf = a.fps, ["-vf", "setfield=%s,separatefields" % a.field_order]
        stream = (["ffmpeg", "-nostdin", "-loglevel", "error"] + raw + ["-framerate", str(rate), "-i", "-"] + vf + [
                  "-c:v", "mjpeg", "-pix_fmt", "yuvj422p", "-q:v", str(a.quality),
                  "-thread_type", "slice", "-flush_packets", "1", "-f", "mpjpeg", "-boundary_tag", BOUNDARY, "pipe:1"])
        # A field is shown line-doubled to the frame size, so the snapshot keeps --size.
        snap_vf = ["-vf", "scale=%s:flags=neighbor" % a.size.replace("x", ":")] if self.alt else []
        snap = (["ffmpeg", "-nostdin", "-loglevel", "error"] + raw + ["-framerate", str(a.snap_fps), "-i", "-"] + snap_vf + [
                "-compression_level", "1", "-f", "image2", "-update", "1", "-atomic_writing", "1", "-y", self.png])
        return source, stream, snap

    def read_stream(self, out):
        """Split ffmpeg's multipart MJPEG into JPEGs; keep the newest, wake the viewers.

        separatefields emits both fields of a frame back to back (measured 2026-10-21: 181 of 483
        gaps under 5 ms, the rest 25-50 ms), although they were captured a field period apart. A
        viewer that keeps only the newest (stream() here, the app's view) then loses the first
        of the pair. So a part that comes under half a period after the previous one is held
        until one period after it -- unless the previous one was itself held: that one was the
        second of its pair, so this is the first of the next and goes out at once. (Counting
        parts as even/odd instead got the pairs wrong from the first part on: measured
        2026-10-21, gaps 38/2 ms with nothing held.)

        The hold used to apply to any part under half a period after the previous one. Once
        anything backed up, the next frame's first field also came straight after the held
        second field, so EVERY field waited: output paced at exactly 2 x --fps = 50.0 fields/s
        against the stk1160's 50.38. The surplus filled the driver's whole vb2 queue and stayed
        there: 174-228 ms (median 188) from a frame's end-of-frame timestamp to its DQBUF, DQBUF
        gaps 40.0 ms instead of 39.7 (measured 2026-10-21, Amiga-View research note
        2026-10-21_latency.md). Holding only the second field caps the cost at one period per
        frame, under the 39.7 ms a frame takes to arrive, so a backlog drains."""
        period = 1.0 / (2 * float(self.a.fps))
        last, held = 0.0, False
        while True:
            line = out.readline()
            if not line:
                return
            if not line.startswith(b"--"):
                continue
            length = None
            while True:
                h = out.readline()
                if not h or h in (b"\r\n", b"\n"):
                    break
                k, _, v = h.decode("latin-1").partition(":")
                if k.strip().lower() == "content-length":
                    length = int(v.strip())
            if not h or length is None:
                return
            body = out.read(length)
            if len(body) < length:
                return
            now = time.time()
            # Alternate mode: fields arrive a field period apart already; never hold.
            held = not self.alt and not held and now - last < period / 2
            if held:
                time.sleep(last + period - now)
                now = last + period
            last = now
            with self.cond:
                self.jpeg, self.jpeg_seq, self.jpeg_time = body, self.jpeg_seq + 1, time.time()
                self.cond.notify_all()

    HDR_MAGIC = b"rdhV"

    def read_frame(self, out, size):
        """One whole frame of exactly `size` bytes, or None at the end. From v4l2-ctl the
        frame carries a header with its real length: a short one is padded with black
        (its missing bottom lines), a long one cut; from the test card it is plain."""
        if self.a.test or self.a.reader != "v4l2-ctl":
            f = out.read(size)
            return f if len(f) == size else None
        h = out.read(8)
        if len(h) < 8 or h[:4] != self.HDR_MAGIC:
            return None
        n = struct.unpack(">I", h[4:])[0]
        f = out.read(n)
        if len(f) < n:
            return None
        if n != size:
            self.short_frames += 1
        if n < size:
            f += BLACK_UYVY * ((size - n) // 4) + BLACK_UYVY[:(size - n) % 4]
        return f[:size]

    def pump(self, src, stream, snap):
        """Raw frames from the source to the stream encoder; one per 1/--snap-fps to the
        snapshot encoder, through a one-slot queue that drops when it is still busy."""
        size, every = self.frame_bytes(), 1.0 / float(self.a.snap_fps)
        slot, last_snap = queue.Queue(maxsize=1), 0.0

        def feed_snap():
            while True:
                f = slot.get()
                if f is None:
                    return
                try:
                    snap.stdin.write(f)
                    snap.stdin.flush()
                except (BrokenPipeError, ValueError, OSError):
                    return
        threading.Thread(target=feed_snap, daemon=True).start()
        try:
            while True:
                f = self.read_frame(src.stdout, size)
                if f is None:
                    return
                stream.stdin.write(f)
                now = time.time()
                if now - last_snap >= every:
                    try:
                        slot.put_nowait(f)
                        last_snap = now
                    except queue.Full:
                        pass
        except (BrokenPipeError, ValueError, OSError):
            return
        finally:
            for p in (stream, snap):
                try:
                    p.stdin.close()
                except OSError:
                    pass
            try:
                slot.put_nowait(None)
            except queue.Full:
                pass

    def run(self):
        while not self.stop:
            self.restarts += 1
            self.started = time.time()
            source, stream_cmd, snap_cmd = self.cmds()
            if not self.a.test and self.a.reader == "v4l2-ctl":
                self.setup_device()
            self.reader = subprocess.Popen(source, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self.snap = subprocess.Popen(snap_cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL)
            self.child = subprocess.Popen(stream_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                          stderr=subprocess.DEVNULL)
            threading.Thread(target=self.pump, args=(self.reader, self.child, self.snap), daemon=True).start()
            self.read_stream(self.child.stdout)
            self.kill()
            for p in (self.child, self.reader, self.snap):
                p.wait()
            if not self.stop:
                time.sleep(2)

    def run_audio(self):
        """arecord in 10 ms periods; keeps the newest chunks for /audio.pcm viewers."""
        dev = self.a.audio_device
        while not self.stop:
            age = self.age_ms()
            if age is None or age > 3000:     # video first: its STREAMON resets the device's audio
                time.sleep(0.5)
                continue
            self.audio_restarts += 1
            self.audio = subprocess.Popen(["arecord", "-q", "-D", dev, "-f", "S16_LE", "-r", str(AUDIO_RATE),
                                           "-c", "2", "-t", "raw", "--period-time=10000", "--buffer-time=80000"],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            while True:
                c = self.audio.stdout.read(AUDIO_CHUNK)
                if len(c) < AUDIO_CHUNK:
                    break
                n = len(c) // 2
                sm = struct.unpack("<%dh" % n, c)
                rms = (sum(v * v for v in sm) / n) ** 0.5
                with self.acond:
                    self.audio_chunks.append(c)
                    del self.audio_chunks[:-AUDIO_KEEP]
                    self.audio_rms.append(rms)
                    del self.audio_rms[:-100]
                    self.audio_seq += 1
                    self.audio_time = time.time()
                    self.acond.notify_all()
            try:
                self.audio.kill()
            except OSError:
                pass
            self.audio.wait()
            time.sleep(1)

    def audio_health(self):
        with self.acond:
            r = self.audio_rms[:]
        if not r:
            return None
        rms = (sum(v * v for v in r) / len(r)) ** 0.5
        return round(20 * __import__("math").log10(max(rms, 1e-3) / 32768), 1)

    def kill(self):
        for p in (self.child, self.reader, self.snap):
            if p is not None and p.poll() is None:
                p.kill()

    def watchdog(self):
        """Kill a capture that is alive but delivers nothing (neither a snapshot nor
        a stream frame); run() starts a new one. Counted from the newest of the last
        snapshot, the last stream frame and the capture's own start, so a source that
        is simply off is retried every --stall-seconds, not hammered."""
        while not self.stop:
            time.sleep(1)
            child = self.child
            if child is None or child.poll() is not None:
                continue
            try:
                last = max(os.stat(self.png).st_mtime, self.jpeg_time, self.started)
            except OSError:
                last = max(self.jpeg_time, self.started)
            if time.time() - last > self.a.stall_seconds:
                self.kill()

    def age_ms(self):
        try:
            return int((time.time() - os.stat(self.png).st_mtime) * 1000)
        except OSError:
            return None


def handler(cap):
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def send(self, code, ctype, body, extra=()):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            for k, v in extra:
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def stream(self):
            """multipart/x-mixed-replace: every field, as it arrives. Ends when the
            capture has delivered nothing for STALE_MS (the client may reconnect)."""
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=%s" % BOUNDARY)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            seq = 0
            try:
                while True:
                    with cap.cond:
                        if cap.jpeg_seq == seq:
                            cap.cond.wait(STALE_MS / 1000)
                        if cap.jpeg_seq == seq:
                            return
                        body, seq = cap.jpeg, cap.jpeg_seq
                    self.wfile.write(b"--%s\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n"
                                     % (BOUNDARY.encode(), len(body)) + body + b"\r\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                return

        def audio_stream(self):
            """Raw s16le 48000 Hz stereo, from the newest 10 ms chunk on, as it is captured.
            Ends when nothing was captured for STALE_MS (the client may reconnect)."""
            if cap.a.audio_device == "none":
                return self.send(404, "application/json", b'{"error":"audio off"}')
            self.send_response(200)
            self.send_header("Content-Type", "audio/x-raw")
            self.send_header("X-Audio-Format", "s16le; rate=%d; channels=2" % AUDIO_RATE)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            with cap.acond:
                seq = cap.audio_seq
            try:
                while True:
                    with cap.acond:
                        if cap.audio_seq == seq:
                            cap.acond.wait(STALE_MS / 1000)
                        if cap.audio_seq == seq:
                            return
                        k = min(cap.audio_seq - seq, len(cap.audio_chunks))
                        body, seq = b"".join(cap.audio_chunks[-k:]), cap.audio_seq
                    self.wfile.write(body)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                return

        def do_GET(self):
            age = cap.age_ms()
            path = self.path.split("?")[0]
            if path == "/snapshot.png":
                if age is None or age > STALE_MS:
                    return self.send(503, "application/json", json.dumps(
                        {"error": "no fresh frame", "age_ms": age}).encode())
                with open(cap.png, "rb") as f:
                    self.send(200, "image/png", f.read(), [("X-Frame-Age-Ms", str(age))])
            elif path == "/stream.mjpg":
                self.stream()
            elif path == "/audio.pcm":
                self.audio_stream()
            elif path == "/health":
                self.send(200, "application/json", json.dumps(
                    {"ok": age is not None and age <= STALE_MS, "age_ms": age, "restarts": cap.restarts,
                     "size": cap.a.size, "source": "test card" if cap.a.test else cap.a.device,
                     "channel": cap.a.channel, "standard": cap.a.standard, "field_order": cap.a.field_order,
                     "fields": "alternate" if cap.alt else "interlaced",
                     "stream_frames": cap.jpeg_seq, "short_frames": cap.short_frames,
                     "audio_device": cap.a.audio_device, "audio_chunks": cap.audio_seq,
                     "audio_restarts": cap.audio_restarts, "audio_rms_dbfs": cap.audio_health(),
                     "stream_age_ms": int((time.time() - cap.jpeg_time) * 1000) if cap.jpeg_time else None}).encode())
            else:
                self.send(404, "application/json", b'{"error":"not found"}')
    return H


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--device", default="/dev/video0")
    p.add_argument("--size", default="720x576")
    p.add_argument("--input-format", default="yuyv422")
    p.add_argument("--channel", type=int, help="the grabber input to use (analog grabbers: S-Video, composite)")
    p.add_argument("--standard", help="the TV standard of an analog input, e.g. PAL")
    p.add_argument("--fps", type=int, default=10)
    p.add_argument("--snap-fps", default="2")
    p.add_argument("--port", type=int, default=8090)
    p.add_argument("--listen", default="127.0.0.1")  # no login: reach it by an SSH tunnel
    p.add_argument("--test", action="store_true")
    p.add_argument("--stall-seconds", type=float, default=6.0,
                   help="restart ffmpeg when it has written no frame for this long")
    p.add_argument("--field-order", default="tff", choices=["tff", "bff"],
                   help="which field of an interlaced frame came first; checked on the hardware")
    p.add_argument("--fields", default="alternate", choices=["alternate", "interlaced"],
                   help="v4l2-ctl reader: one field per buffer (alternate, needs the patched stk1160; "
                        "~20 ms less latency) or whole interlaced frames split by ffmpeg")
    p.add_argument("--quality", type=int, default=5, help="MJPEG -q:v of the live stream (2 best .. 31)")
    p.add_argument("--reader", default="v4l2-ctl", choices=["ffmpeg", "v4l2-ctl"],
                   help="what reads the device: v4l2-ctl (every frame, 50 fields/s) or ffmpeg (whole frames only, ~13 fields/s)")
    p.add_argument("--audio-device", default="none",
                   help="ALSA capture device served at /audio.pcm (s16le, 48000 Hz, stereo), e.g. hw:CARD=STK1160,DEV=0; "
                        "started only once video flows (the stk1160 audio dies when video streaming starts under it)")
    a = p.parse_args()
    cap = Capture(a)
    threading.Thread(target=cap.run, daemon=True).start()
    threading.Thread(target=cap.watchdog, daemon=True).start()
    if a.audio_device != "none":
        threading.Thread(target=cap.run_audio, daemon=True).start()
    srv = http.server.ThreadingHTTPServer((a.listen, a.port), handler(cap))
    srv.daemon_threads = True               # a viewer that never disconnects must not hold shutdown
    try:
        srv.serve_forever()
    finally:
        cap.stop = True
        cap.kill()
        if cap.audio:
            cap.audio.kill()


if __name__ == "__main__":
    main()
