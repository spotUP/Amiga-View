---
date: 2026-10-27
topic: CRT shader (ledger section J) via librashader Metal
status: design, waiting for user decisions (cost checkpoint)
---

# CRT shader for Amiga-View (librashader + Mega Bezel on Metal)

Research evidence: scratchpad librashader-findings.md (session 6542398c); summary below.

## Facts verified

- librashader runtime and C API: `MPL-2.0 OR GPL-3.0-only` (librashader-0.11.2 Cargo.toml:35; capi Cargo.toml on master). Latest release v0.12.1 (2026-10-11); no prebuilt macOS dylibs on the release page. Build: `cargo run -p librashader-build-script -- --profile optimized`. Rust 1.95 is installed here.
- Taking the MPL-2.0 option and shipping the dylib unmodified, with its notice and a source link, keeps Amiga-View MIT. Static linking against the header is unsupported upstream.
- Mega Bezel base package: GPLv3 (slang-shaders bezel/Mega_Bezel README). Ship the .slangp/.slang files as separate data in the bundle (aggregation), with the GPL text and attribution next to them. Not legal advice; per-file headers not yet checked.
- Metal C API (include/librashader.h, guarded by `__APPLE__ && LIBRA_RUNTIME_METAL && __OBJC__`): takes `id<MTLCommandQueue>`, `id<MTLCommandBuffer>`, `id<MTLTexture>`. Calls: `libra_preset_create_with_options`, `libra_preset_free`, `libra_mtl_filter_chain_create(preset*, queue, opt*, out*)`, `libra_mtl_filter_chain_frame(chain*, cmdbuf, frame_count, image, output, viewport*, mvp*, frame_opt*)`, `_set_param`, `_get_param`, `_free`. Not thread safe.
- Mega Bezel on Metal: README says full support; issue #75 (SMOOTH-ADV blurry) reported fixed; #78/#79 texture-size crashes closed. Slower than RetroArch near 4K with reflections.
- Prior art: UpRough (Rust, objc2-metal, librashader 0.11.2 FilterChainMetal, CAMetalLayer BGRA8, upload RGBA per frame, slang-shaders submodule pinned at cb8e5341). Same shape as here; reuse its pinned slang-shaders commit and preset tiers. ~/Code/mega-bezel-reflection-shader-web is a hand-adapted WebGL fork with no LICENSE: not a source.
- Mega Bezel tree is 20 MB, but presets reach into the wider slang-shaders tree (75 MB total); the shipped subset must be computed from the preset includes, not guessed.

## Current picture path (to replace)

FrameDecoder.decode (JPEG to CGImage) -> ViewGeometry.displayImage (field 720x288 doubled to 576) -> VideoView.videoLayer.contents (CALayer, .resize). Scanlines are a second CALayer with a 1-px-wide alpha image (ViewGeometry.scanlineAlphas), scaled by Core Animation: rows bunch when the window height is not a whole multiple of 576. That is the reported "looks bad".

## Design

1. **Build**: `scripts/librashader.sh` clones librashader at a pinned tag (v0.12.1) into build/, runs the build script for Metal only, copies `librashader.dylib` + `librashader.h`. bundle.sh embeds the dylib in Contents/Frameworks (rpath @executable_path/../Frameworks) and signs it with the app. The dylib is not committed.
2. **Bridge**: new SwiftPM Objective-C target `LibrashaderBridge` (one .h/.m) that includes librashader.h with LIBRA_RUNTIME_METAL and exposes a tiny ObjC class: `initWithPreset:queue:error:`, `renderSource:toTarget:commandBuffer:viewport:frameCount:`, `setParameter:value:`. Chosen over a Swift module map because the header needs ObjC mode for `id<MTL...>`; the shim also keeps the not-thread-safe chain on one queue.
3. **View**: VideoView's picture layer becomes a CAMetalLayer. Each decoded frame: CGImage of the cropped field (native 720xN, no CPU doubling) uploaded to one reused MTLTexture (replaceRegion), then either the filter chain (shader on) or a plain blit (shader off) into the drawable, then present. Crop and Integer Scaling stay ViewGeometry's job (viewport). frame_count increments per arrived frame so the shader's interlace/flicker timing follows the Amiga, not the display.
4. **Shaders**: `scripts/fetch-shaders.sh` checks out slang-shaders at the pinned commit (cb8e5341, same as UpRough) and copies only the files reachable from the chosen presets (walk `#include` and preset references) into the bundle's Resources/shaders with the GPL-3.0 text.
5. **Menu**: View > Scanlines is replaced by View > CRT Shader with Off + the chosen presets; stored in UserDefaults via PictureOption (reuse). The CPU scanline layer and ViewGeometry.scanlineAlphas are deleted.
6. **Snapshot / recording**: keep the raw Amiga picture (current behaviour), unless the user picks otherwise.
7. **Failure**: preset load error -> fall back to plain blit, show the error once in the status line; never a black window.

## Tests (reachability)

- One reachability test: app delegate selects CRT Shader preset via the menu action -> VideoView renders a frame -> bridge frame-call counter == 1 and the drawable pixel differs from the plain-blit pixel (sentinel). Uses a tiny test preset (one pass) to stay fast; Mega Bezel load measured separately.
- Unit: include walker returns the exact file set for one preset; ViewGeometry viewport for crop + integer scaling.
- Measure: preset load time and GPU time per frame for each shipped preset at window and full-screen size, written to this doc.

## Cost

About 4 sonnet agent runs (build script + bundling; bridge + Metal view; shader fetch + menu; tests + measurements) plus one Opus review. Main unknowns: Mega Bezel compile time at preset load (seconds; may need a loading message), Retina full-screen GPU cost, header compiling in SwiftPM's ObjC target. Bundle grows by about 5 MB dylib + 20-40 MB shaders.

## User decisions (2026-10-27)

- Presets: all 9 MBZ presets (MBZ__0__SMOOTH-ADV-GLASS ... MBZ__5__POTATO).
- Snapshot and recording: raw Amiga picture (unchanged).
- Start now.
- Reflections required (user, 2026-10-27): the default preset when CRT Shader is first turned on is MBZ__3__STD (has reflection); the spike in J3 must render a reflection preset, not a NO-REFLECT one.

## Spike results (J2/J3, bf3a340)

- MBZ__3__STD loads and renders through LBFilterChain. Cold preset load 14.8 s (shader compile); Metal chain options have no cache switch (filter_chain_mtl_opt_t: version, force_no_mipmaps only).
- GPU time at 1440x1080: 44 ms first frame, then ~11.5 ms. Budget at 50 Hz is 20 ms. Full screen on Retina is ~4x the pixels, so drawing the chain at full drawable pixels will likely miss the budget.
- librashader.h has only PFN typedefs; the bridge declares the 10 exported symbols by hand, tied to the pinned v0.12.1.

Design changes from these numbers:
- Preset load runs on a background queue; the view stays black meanwhile (R11, user 2026-10-27; was: plain blit continues); status line shows "Loading CRT shader..." until ready. A load is cancelled/ignored if the user picks another preset first.
- The chain renders into an offscreen texture capped at a measured size (start: output height <= 1080 px, aspect kept), then one linear blit scales it to the drawable. The cap is a constant in ViewGeometry, measured in J8 at window and full screen.
- Measure warm load (second load in the same process, and after an app relaunch) in J8; if relaunch is still ~15 s, look at librashader's shader cache crate before calling it done.
