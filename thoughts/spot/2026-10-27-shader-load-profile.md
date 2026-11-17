# Mega Bezel (MBZ__3__STD) load profile, librashader v0.12.1 Metal

## Method
- Harness (scratchpad .../scratchpad/h/h.m): links build/librashader/librashader.dylib, calls libra_preset_create then libra_mtl_filter_chain_create twice in one process, prints wall ms. No librashader-src edits, no rebuild (dylib has Rust symbols, so `sample` resolves function names).
- `sample <pid> 12 1` (1 ms) during a warm run; percentages = samples on the calling (main) thread inside libra_mtl_filter_chain_create (2651 + 64 samples). Raw: scratchpad/h/s.txt, warm.txt.
- MTLCompilerService: its CPU time stayed 0.10-0.16 s total across the whole session (ps cputime); Metal time on the main thread includes any blocking wait for it, so the 1.4% below is the full Metal cost.

## Wall times
- First run ever after the build (cold Metal system cache): chain_create 24608 ms (run0), 2219 ms (run1, same process).
- Warm, fresh process: run0 2360 ms, run1 1976 ms. preset_create (file reads, preprocess) 2-4 ms, 15 ms on the very first call.

## Stage table (warm, share of chain_create wall; ms scaled to ~2.2 s)
| # | Stage | samples | % | ~ms |
|---|---|---|---|---|
| 2 | glslang GLSL->SPIR-V (parse 674, preprocess 169, SPIR-V gen 173, link 81, delete 42) | 1239 | 45.6 | 1000 |
| 3 | SPIRV-Cross parse + librashader reflection (type_description/process_struct, 330 of it String::from_utf8_lossy) | 801 (+~45 parse inside stage 2 tree) | 29.5 | 650 |
| 4 | SPIRV-Cross SPIR-V->MSL (spvc_compiler_compile 409 + 67) | 477 | 17.6 | 390 |
| 1 | slang preprocess/file reads: preset_create 2-4 ms plus ShaderPresetPack::load_from_preset (main thread, incl. LUT decode which runs on rayon workers) | 64 | 2.4 | 50 |
| 5 | newLibraryWithSource (all passes) | 17 | 0.6 | 14 |
| 6 | newRenderPipelineState | 22 | 0.8 | 18 |
| 7 | LUT replaceRegion upload 35, spvc_context_destroy 31, other ~29 | 95 | 3.5 | 75 |

Stage 1 preprocess (#include, pragma split) is inside glslang numbers only for the GLSL-level glslang preprocess; the librashader-preprocess crate itself is ~2-4 ms.

## Owners (build/librashader-src)
1: librashader-preprocess/src/lib.rs, librashader-pack load_from_preset. 2: librashader-reflect/src/front/glslang.rs (compile_spirv) via mtl filter_chain.rs compile_passes. 3: librashader-reflect/src/reflect/cross/mod.rs (CrossReflect::reflect, reflect_buffer_range_metas) via spirv_cross2 type_description/process_struct. 4: librashader-reflect/src/reflect/cross/msl.rs (CompileShader<MSL>). 5/6: librashader-runtime-mtl/src/graphics_pipeline.rs.

## Conclusions
- Stages 5 and 6 (Metal) are 1.4% warm: the macOS system shader cache already serves them, so MTLBinaryArchive / .metallib caching is not worth it for warm launches. (Cold 24.6 s is Metal populating that cache; not fixable by librashader caching, one-time per machine/MSL change.)
- 94% of warm time is stages 2+3+4 (glslang 46, reflection 30, MSL 18), all pure CPU, single-threaded, sequential per pass.
- Option (a) CachedCompilation for SPIR-V removes only ~46%: 2.2 s -> ~1.2 s.
- Recommended: cache the output of stages 2-4 together per pass, keyed by blake3 of the pass GLSL sources plus MSL version: store MSL vertex/fragment text plus serialized ShaderReflection (needs serde on the reflection structs). Warm load then drops to roughly Metal + LUT + pack = ~0.1-0.15 s. Do (a) first only if the larger patch is too big; it is a strict subset.
- Cheap independent win: reflection spends ~12% of total in String::from_utf8_lossy inside spirv_cross2 process_struct/type_description (name copies per struct member); upstream-style fix, would cut ~0.25 s without any cache.
- Caveat: one sample run, proportions only; 1 ms sampling lost some wall (samples ~3.6k over ~6 s of process life).

## Result (R9, 1632d21)
Patch patches/librashader/0001-metal-shader-cache.patch caches reflection + MSL per pass and compiles uncached passes in parallel. MBZ__3__STD through the bridge test: compiled 697 ms (was ~2.2 s sequential), cached 91 ms.
