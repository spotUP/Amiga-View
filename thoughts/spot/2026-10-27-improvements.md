# Amiga-View improvements (ledger, 2026-10-27)

The user chose all four from the idea list. Each is done when it can be reached from the menu or the app, has a test, is committed, and the build is reinstalled in /Applications.
Run order: A, B, C, one sonnet agent each. They run one after another because all three touch AppDelegate and VideoView.

- [x] D. Icon + LICENSE. Commits c8f3775 and d83a52c. Licence: MIT for the app, GPL-2.0 for pi/stk1160 (the user's choice).
- [x] A. (397afd8; findings -A.md; live check pending; initial-state gap moved to B) Input indicator + watchdog for input stuck on the Amiga.
  - Parse ~/deskflow.log in a pure Core type.
  - While replay has the input: show a border and a status line.
  - "locked by mouse buttonID" lines arriving repeatedly mean the user is trying to leave and Deskflow refuses. Then post a synthetic mouseUp.
  - This is a mitigation. The root cause (why Deskflow believes a button is held) is still open; see 2026-10-24-stuck-on-replay.md.
- [x] B. (a019c7f picture options, 63797ee log history seed; findings -B.md; manual LOCAL checks pending) + seed Deskflow state from last switch line at start. Picture options in the View menu: Crop Overscan, Integer Scaling, Full Screen, Scanlines. Each is stored in UserDefaults.
  - Gotcha: a full-screen window covers the right edge. Ignore click-switch clicks within SynergySwitch.edgeClearance of the desktop's right edge, or the returning pointer is trapped again.
- [x] C. (f6fe223; findings -C.md; manual LOCAL check pending) Snapshot (Cmd+S, PNG to ~/Desktop) + recording (Cmd+R, .mov to ~/Movies, H.264 + AAC, timed by frame arrival).
- [x] Final (installed in /Applications 2026-10-27; README sections done; not pushed): bundle.sh, install to /Applications, README sections, push to GitHub only if the user asks.

2026-10-27: the user tested snapshot, recording, the View menu options and Deskflow live: all pass. The user first reported "cant exit fullscreen", then corrected it to "i can exit fullscreen"; no fix was made. Not verified: EdgeGuard also runs on windowDidResize/windowDidMove in full screen. On a single display it would shift the full-screen window 16 pt left.

- [x] 4bca8eb: Esc leaves full screen; entering shows the hint for 3 s.
- [x] a5f1f37 EdgeGuard full screen (after fix: full screen at 0,43 1800x1126; Esc back to 1056,146): measured before fix, the full-screen window sat at x=-16 (1800x1126). Fix: EdgeGuard stands down from windowWillEnterFullScreen to windowDidExitFullScreen, then clears the edge again. Regression test EdgeGuardTests.testFullScreenWindowIsNotMovedOffTheEdge. User report "ctrl command f does nothing": not reproduced when the app is frontmost; earlier the app had 0 windows (cause unknown, open).

2026-10-27 (later session): pushed a5f1f37 to GitHub at the user's request.
- [x] c359c4d (pushed, installed in /Applications): the recording line now stacks above the Deskflow status, flashes and the accessibility warning. Regression test CaptureMenuTests.testRecordingLineStaysVisibleWhileAmigaHasInput (fails on the old code). Manual LOCAL check pending.
- Open, by the user's choice "wait for repro": the app once had 0 windows, so Ctrl-Cmd-F did nothing. Investigate only when it happens again.

## E. Reset Amiga (2026-10-27)
Decisions: keys cannot reset (user test: Ctrl+LCmd+RCmd via Synergy does nothing; A1200 Ctrl-A-A is keyboard hardware). User chose Amiga-side listener: wasabid already runs there and its REBOOT verb calls ColdReboot (user: C:Reboot works).
Gotcha: wasabi discovery with no host found an fs-uae rig (127.0.0.1:1236), so the app always passes an explicit host (`amigaHost`, default 192.168.0.66 from UpRough thoughts/spot/a1200.json; key comes from ~/.config/wasabi/config, same as upterm key file).
- [x] E1 vendor wasabi.py (UpRough ffefb8325 = upstream be4c055) into Resources/wasabi, mock_wasabid.py for tests
- [x] E2 AmigaReset core (args, outcome text, settings) + unit tests
- [x] E3 Amiga menu "Reset Amiga..." with confirm, status flash; bundle.sh copies script
- [x] E4 reachability test: menu -> real wasabi.py -> mock daemon logs REBOOT
- [x] E5 README, build, install, manual LIVE check by user (Amiga was off: no ping at .66/.74)

- E1-E4 done, installed in /Applications 2026-10-27. Running instance (pid 7084, from build/) still has the old binary until relaunched.
- E5 live reset FAILED (2026-10-27): wrong host (.66, Amiga now at .74) and wasabid refused ~/.config/wasabi/config key ("bad key"). Fix 05071ee: default .74, key from ~/.config/up-term/replay-wasabi.key (user choice). Installed. Live retest pending; the UP-Term key was never tested against the Amiga (auto mode blocked the test).
- E5 live reset PASSED (user, 2026-10-27) with 05071ee. Not pushed.

## F. Amiga settings in the app (2026-10-27)

Decisions (user): key stored in the Keychain (secure field), falling back to UP-Term's key file when the Keychain item is empty; standard Settings window on Cmd+, with Host, Port, Key.

- [x] F1 Core: AmigaKeychain (generic password, service com.spotup.amiga-view.wasabi) + AmigaReset.key() prefers it over the key file. Tests. (d05b736)
- [x] F2 Settings window (Amiga-View > Settings..., Cmd+,): Host, Port, Key (secure), key file path note. Save writes amigaHost/amigaPort + Keychain. Reachability test: open via menu action, set fields, save, reset reads the new values (mock wasabid). (d05b736)
- [x] F3 README: Settings section for the window; wasabid as optional dependency (needs wasabid on the A1200 + /usr/bin/python3 on the Mac; without it only Reset fails). (User request mid-task.) (d05b736)
- [x] F4 Build, tests (nice 19), install to /Applications, ask user for live check. (installed 2026-10-27, signed Amiga-View Dev; live check passed (user 2026-10-27: "all pass"))
- [x] F5 Signing without paid Apple account (user request mid-task): scripts/make-signing-identity.sh creates the self-signed "Amiga-View Dev" code-signing identity bundle.sh already looks for (exists on this Mac, made by hand, undocumented). README "Signing" section: run the script once; why (Accessibility grant + Keychain access survive rebuilds); a downloaded build: right-click Open / System Settings Open Anyway / xattr -dr com.apple.quarantine. Do not run the script here (identity already exists; would change the user's keychain). (d05b736)

## G. First release (user request 2026-10-27, mid-task F)

- [x] G1 (8e4830f; 7 TODO(user) markers in README: cable, Replay vs A1200 output + audio path, Pi wired/Wi-Fi, Synergy client source + command, Deskflow version, enableHeartbeat, add Pi install.sh + amiga-cam.service to repo?) Docs: hardware needed (A1200, Pi 4 grabber + stk1160 USB capture, audio input, network, Synergy client on Amiga, Deskflow on Mac, optional wasabid) and step-by-step hw/sw setup (Pi, camserver, ssh Host entry, Deskflow screen, Amiga side).
- [x] G2 (073b4f5; `scripts/bundle.sh --release` -> build/Amiga-View-0.1.0.zip, verified 0.1.0) Version in Info.plist, release build script producing a zip (ditto) for the release.
- [x] G4 Screenshot: user full-screen shot, downscaled to 1800 px, docs/screenshot.png in commit 393347a (shows "51 FPS" and the Amiga pointer at the left edge; user supplied it as is).
- [x] G3 Release notes (thoughts/spot/release-notes-0.1.0.md) and GitHub release v0.1.0 with Amiga-View-0.1.0.zip: https://github.com/spotUP/Amiga-View/releases/tag/v0.1.0 (tag at 393347a, main pushed).
- [x] G5 (e34d548, tag v0.1.1, https://github.com/spotUP/Amiga-View/releases/tag/v0.1.1, zip verified 0.1.1 + signature; installed in /Applications 2026-10-27, signature ok, launched; old 0.1.0 moved to session scratchpad old-app; live check passed (user 2026-10-27: "pass")) (user 2026-10-27: "release it") Release 0.1.1 = v0.1.0 + 1632d21 shader cache. Steps: Info.plist 0.1.1 (build 2), commit, wait for other session build to finish, scripts/bundle.sh --release, tag v0.1.1, push main + tag, gh release with thoughts/spot/release-notes-0.1.1.md + zip, install in /Applications.

## H. Input border (user report 2026-10-27, mid-task F)

Report: blue border not visible on the left in full screen; user finds it ugly. It marks "Amiga has keyboard and mouse" (Deskflow), not recording. Decision (user): remove the border, keep the status text.
- [x] H1 Remove the accent border from VideoView/AppDelegate; status line text stays. Update tests + README "Who has the input". (5057889)

## I. Tab bar (user report 2026-10-27)

Report: a tab bar shows a single tab "Amiga-View". It is macOS automatic window tabbing (View > Show Tab Bar, or "Prefer tabs" in System Settings); Amiga-View has one window, so tabs do nothing.
- [x] I1 Opt the window out of tabbing (tabbingMode .disallowed), regression test on the window, README not needed. (3badbdd)

- [x] I2 Toolbar (user chose: toolbar, hidden in full screen). Commit a3ab112; test CaptureMenuTests.testToolbarButtonsRunTheMenuActions fails with buildToolbar() removed. Installed in /Applications. live check passed (user 2026-10-27: "all pass").
- G1 facts: scratchpad hw-setup-facts.md (session a59ed3db). Unknown: Synergy client source on A1200, exact video cable, Pi wired or wifi, Deskflow version.

## J. Scanlines (user report 2026-10-27)

Report: Scanlines look bad, at least in a window. Not investigated yet; suspect: the dark rows are drawn at 576 lines and then scaled to a window height that is not a whole multiple, so rows bunch up unevenly.
- User direction: scanlines need a real GPU shader (Metal) to make sense; preferably RetroArch's Mega Bezel Reflection shader (HyperspaceMadness, slang, many passes). Big: needs a slang-to-Metal path (SPIRV-Cross or librashader) and a licence check before any code. Cost checkpoint with user before starting. User (2026-10-27): there is an existing repo with the Mega Bezel shader for a web target; maybe it can be repurposed. Find out which repo and check it before designing. Candidates found locally: ~/Code/hippoplayer.se (thoughts/shared/handoffs/2026-06-01_crt-shader-experimental.md, web CRT shader) and ~/Code/UpRough/Up_Rough_Demo_System (web/maker/src-tauri/shaders/slang/bezel/Mega_Bezel/, plus plan thoughts/shared/plans/2026-06-22-native-metal-slang-shaders.md, which is a native Metal slang path and the most direct fit). Read those (by section) first. User then named ~/Code/mega-bezel-reflection-shader-web (RetroArch shader subsystem extracted to WASM + WebGL2, gl3_filter_chain, 36 passes, GPL-2.0+ shader code / MIT wrapper) and said it is hacked to run on the web; maybe start a clean Mac port from RetroArch sources instead. Constraint: Amiga-View is MIT; linking RetroArch-derived code (GPL) would force the app to GPL. Candidate: librashader (slang preset runtime with a native Metal backend, runs Mega Bezel; licence MPL-2.0/GPL-3 per memory, unverified). Decision (user, 2026-10-27): use librashader with its Metal backend; Amiga-View stays MIT. First step next session: verify librashader licence and Metal C API, then design (cost checkpoint).
Design: thoughts/spot/2026-10-27-crt-shader-design.md (decisions: all 9 MBZ presets, default MBZ__3__STD with reflections, capture stays raw, start now).
- [x] J2 (bf3a340; bundle.sh edited, not yet run end to end) scripts/librashader.sh (pinned v0.12.1, Metal-only dylib + header into build/) and bundle.sh embeds + signs the dylib.
- [x] J3 (bf3a340; MBZ__3__STD cold load 14.8 s, ~11.5 ms GPU at 1440x1080; design addendum "Spike results") LibrashaderBridge ObjC SwiftPM target; spike: create chain from one MBZ preset on a headless MTLDevice, render one frame.
- [x] J4 (3726f7a; 156 files, 12.9 MB in build/shaders; no walker gap; headers GPLv3 + some GPLv2+; slang-shaders has no root licence file) scripts/fetch-shaders.sh: slang-shaders @cb8e5341, copy only files reachable from the 9 presets + GPL-3.0 text into Resources/shaders.
- [x] J5 (1f3ec4a; PictureRenderer, chain at <=1080 px then linear scale; source texture must be .shared; MBZ__3__STD 2880x2160 uncapped ~40 ms, 1440x1080 ~11.5 ms) VideoView on CAMetalLayer: texture upload, chain or plain blit, crop/integer scaling via viewport, frame_count per arrived frame, fallback on preset error.
- [x] J6 (1f3ec4a; CRTShader enum, key picture.crtShader, default changed by user decision 2026-10-27 to Standard (MBZ__3__STD), done ce2cebb; bundle.sh copy untested) View > CRT Shader menu (Off + 9 presets) via PictureOption; delete CPU scanline layer and scanlineAlphas.
- [x] J7 (1f3ec4a reachability + viewport/cap; d0d4106 include-walker test Tests/scripts + bridge test on build/shaders) Reachability test (menu -> frame call counter, pixel differs) + include-walker unit test + viewport test.
- [x] J8 (69e7962 licences + README; bundle.sh verified end to end; load 2.2-3.0 s warm disk, 14.8 s was cold disk; Metal runtime has no shader cache; dev rpath leak fixed in latest commit with guard) Measure load time + GPU time per preset (window + full screen) into design doc; README + licence notices (MPL dylib, GPL shaders).
- [x] J9 (review done, R1-R6 fixed b269943; 0.1.0 installed /Applications 2026-10-27, signature ok; live check passed (user 2026-10-27: "all pass")) Opus review, bundle, install in /Applications, live check by user.
- [x] J1 (done by J2-J9: CPU scanline layer deleted, librashader Metal chain in 1f3ec4a; closed by user 2026-10-27) (user 2026-10-27: fresh session, design first) Measure the current look (window and full screen), then replace the CPU scanline pass with a Metal shader drawing the picture. Size: one design step before code.

### J9 review fixes (review: scratchpad j9-review.md, range bf3a340..d26f1da)
- [x] R1 (91250cf, test in b269943) source texture race: ring of 3 .shared source textures + semaphore signalled on completion; upload after nextDrawable (PictureRenderer.swift:63-79, 98-99).
- [x] R2 (b269943) stale preset loads still compile serially (VideoView.swift:95, 106-107): skip stale generation before compile; picking current preset is a no-op.
- [x] R3 (c3c42fb) bundle.sh runs swift build before scripts/librashader.sh: fresh clone fails to link.
- [x] R4 (measured: all presets <20 ms median at 1728x1080; SMOOTH-ADV 16.6 median / 21.0 max) per-preset GPU time at 1080 cap for all 9 presets (J8 measured only Standard); main-thread nextDrawable block if > 20 ms.
- [x] R5 (b269943, guard only: view layer already sRGB) CAMetalLayer colorspace unset: set sRGB.
- [x] R6 (b269943) drawableSize updated only in layout(): one misplaced frame on resize/full screen.
- R7 by design, reported to user: shader on + picture > 1080 px loses integer scaling (one linear scale).
- [x] R8 (cdd2882) full screen not full (user live check, screenshot CleanShot 2026-10-27 at 11.25.56): with a chain, VideoView.pictureRect was the 4:3 (integer) fit, so Mega Bezel drew screen and bezel into ~1440x1152 px in the middle of 3600x2252. Fix: chain path draws into the whole drawable (Mega Bezel places the screen itself). Test PictureRendererTests.testShaderChainDrawsIntoTheWholeDrawable. Then rebundle, reinstall, user rechecks.
- [x] R9 shader load time (user 2026-10-27: "takes pretty long to init on the mac, much faster in retroarch on pc"). Warm load 2.2-3.0 s, cold 14.8 s; librashader Metal runtime has no cache (librashader-cache used by other runtimes only). Research: which stage costs the time (preprocess, glslang, spirv-cross, Metal compile) and the root-cause cache (librashader Metal runtime patch). Findings: thoughts/spot/2026-10-27-shader-cache-research.md (copied from old scratchpad); profile in progress (2026-10-27 session 2, sonnet agent) -> thoughts/spot/2026-10-27-shader-load-profile.md. Stages per pass: preprocess, glslang to SPIR-V, SPIRV-Cross reflect, SPIR-V to MSL, newLibraryWithSource x2, pipeline state. librashader-cache (persy DB in ~/Library/Caches/librashader) caches glslang SPIR-V for d3d12 via CachedCompilation + disable_cache option; Metal has no MSL impl and no option; upstream has none. Next: profile one MBZ__3__STD load with `sample` to find the dominant stage, then patch librashader (carried .patch applied by scripts/librashader.sh): (a) CachedCompilation for MSL ~60-80 lines; if SPIRV-Cross dominates, also cache MSL + reflection; if Metal compile dominates, MTLBinaryArchive.
  - Profile done (thoughts/spot/2026-10-27-shader-load-profile.md): warm 2.0-2.4 s = glslang 46%, SPIRV-Cross reflect 30%, SPIR-V->MSL 18%, Metal 1.4%. Cold 24.6 s first-ever is the system Metal cache (out of our reach).
  - Decision: cache stages 2-4 per pass in the Metal runtime (MSL text + ShaderReflection, bincode) via librashader-cache cache_shader_object, key = blake3(version tag, pass index, GLSL vertex+fragment, sorted semantics Debug text). Semantics built without compiling (new pub fn in librashader-reflect presets.rs, shared with compile_preset_passes). Option disable_cache in FilterChainOptionsMetal (Rust only, C ABI unchanged; default cache on). Carried as patches/librashader/*.patch applied by scripts/librashader.sh (rebuild when patch hash changes).
  - [x] R9a patch + script  - [x] R9b bridge test (HOME -> temp dir: db file appears, second load < 1/3 of first, pixels equal)  - [x] R9c measure, bundle, install
  - Done 1632d21 (not pushed, installed in /Applications 2026-10-27). MBZ__3__STD: original 2.2 s, parallel compile 697 ms, cache hit 91 ms, same pixels.
  - Two bugs found on the way, both fixed in the patch: (1) librashader-cache get_cache opened Persy from several rayon threads; the second open hit the file lock and remove_cache() deleted the db. Fixed with an open mutex. (2) bincode cannot decode ShaderReflection (halfbrown maps call deserialize_any: AnyNotSupported), so every get missed. Switched to rmp-serde (already in the lock via librashader-pack), CACHE_VERSION v2. Rust test cache_tests::cached_pass_round_trips_through_its_bytes fails with bincode, passes with rmp.
  - [x] Live check (user): switch CRT shader twice in the app; second switch to the same preset is near-instant. User 2026-10-27: "pass".
- [x] R10 Mega Bezel intro animation on shader load (user 2026-10-27: "disable the mega bezel jingle during launch"). Fix: VideoView's load closure sets HSM_INTRO_WHEN_TO_SHOW (OFF|Game Load|Shader Load|Repeat, default 1) to 0 on every loaded chain; bridge gains `parameter:` (libra_mtl_filter_chain_get_param) for the test. Live check passed (user 2026-10-27: "all pass").
- [x] R11 Unshaded picture visible while the shader loads (user 2026-10-27: "i see the amiga screen unshaded for a bit before the shader applies hide it before that"). Replaces the J design decision "plain blit continues meanwhile": while shaderState is .loading, draw black (status line still says Loading CRT shader). A failed load still falls back to the plain picture. Live check passed (user 2026-10-27: "all pass").
- [x] R12 Cmd-Return toggles full screen (user 2026-10-27: "command and enter should toggle fullscreen"). Hidden View menu item (isHidden, allowsKeyEquivalentWhenHidden) beside Enter Full Screen, which keeps ctrl-cmd-F. Test PictureMenuTests.testCommandReturnTogglesFullScreen (fails before, passes after, fails on revert). Hint text and README name it. R8 confirmed live by the user ("fullscreen is glorious now"). Live check passed (user 2026-10-27: "all pass").
